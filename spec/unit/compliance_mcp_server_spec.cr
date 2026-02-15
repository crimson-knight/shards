require "./spec_helper"
require "json"
require "../../src/mcp/compliance_server"

module Shards
  describe ComplianceMCPServer do
    describe "TOOLS" do
      it "defines exactly 6 compliance tools" do
        ComplianceMCPServer::TOOLS.size.should eq(6)
      end

      it "has expected tool names" do
        names = ComplianceMCPServer::TOOLS.map(&.name)
        names.should contain("audit")
        names.should contain("licenses")
        names.should contain("policy_check")
        names.should contain("diff")
        names.should contain("compliance_report")
        names.should contain("sbom")
      end

      it "all tools have descriptions" do
        ComplianceMCPServer::TOOLS.each do |tool|
          tool.description.should_not be_nil
          tool.description.not_nil!.size.should be > 10
        end
      end

      it "all tools have object-type input schemas" do
        ComplianceMCPServer::TOOLS.each do |tool|
          tool.inputSchema.type.should eq("object")
        end
      end

      it "audit tool has severity and fail_above enums" do
        audit = ComplianceMCPServer::TOOLS.find { |t| t.name == "audit" }.not_nil!
        props = audit.inputSchema.properties.not_nil!
        severity = props["severity"]
        severity["type"].as_s.should eq("string")
        severity["enum"].as_a.map(&.as_s).should eq(["low", "medium", "high", "critical"])

        fail_above = props["fail_above"]
        fail_above["enum"].as_a.map(&.as_s).should eq(["low", "medium", "high", "critical"])
      end

      it "sbom tool has format enum" do
        sbom = ComplianceMCPServer::TOOLS.find { |t| t.name == "sbom" }.not_nil!
        props = sbom.inputSchema.properties.not_nil!
        fmt = props["format"]
        fmt["enum"].as_a.map(&.as_s).should eq(["spdx", "cyclonedx"])
      end

      it "tools serialize to valid JSON" do
        ComplianceMCPServer::TOOLS.each do |tool|
          json_str = tool.to_json
          parsed = JSON.parse(json_str)
          parsed["name"].as_s.should eq(tool.name)
          parsed["inputSchema"]["type"].as_s.should eq("object")
        end
      end
    end

    describe "#build_cli_args" do
      server = ComplianceMCPServer.new(Dir.current)

      it "maps audit with no arguments" do
        args = server.build_cli_args("audit", nil)
        args.should eq(["audit", "--format=json"])
      end

      it "maps audit with severity and offline" do
        arguments = JSON.parse(%({"severity": "high", "offline": true}))
        args = server.build_cli_args("audit", arguments)
        args.should eq(["audit", "--format=json", "--severity=high", "--offline"])
      end

      it "maps audit with fail_above and ignore" do
        arguments = JSON.parse(%({"fail_above": "critical", "ignore": "GHSA-1,GHSA-2"}))
        args = server.build_cli_args("audit", arguments)
        args.should eq(["audit", "--format=json", "--fail-above=critical", "--ignore=GHSA-1,GHSA-2"])
      end

      it "maps licenses with no arguments" do
        args = server.build_cli_args("licenses", nil)
        args.should eq(["licenses", "--format=json"])
      end

      it "maps licenses with check and detect" do
        arguments = JSON.parse(%({"check": true, "detect": true}))
        args = server.build_cli_args("licenses", arguments)
        args.should eq(["licenses", "--format=json", "--check", "--detect"])
      end

      it "maps licenses with include_dev" do
        arguments = JSON.parse(%({"include_dev": true}))
        args = server.build_cli_args("licenses", arguments)
        args.should eq(["licenses", "--format=json", "--include-dev"])
      end

      it "maps policy_check with no arguments" do
        args = server.build_cli_args("policy_check", nil)
        args.should eq(["policy", "check", "--format=json"])
      end

      it "maps policy_check with strict" do
        arguments = JSON.parse(%({"strict": true}))
        args = server.build_cli_args("policy_check", arguments)
        args.should eq(["policy", "check", "--format=json", "--strict"])
      end

      it "maps diff with from and to" do
        arguments = JSON.parse(%({"from": "v1.0", "to": "v2.0"}))
        args = server.build_cli_args("diff", arguments)
        args.should eq(["diff", "--format=json", "--from=v1.0", "--to=v2.0"])
      end

      it "maps compliance_report with sections and reviewer" do
        arguments = JSON.parse(%({"sections": "sbom,audit", "reviewer": "alice@example.com"}))
        args = server.build_cli_args("compliance_report", arguments)
        args.should eq(["compliance-report", "--format=json", "--sections=sbom,audit", "--reviewer=alice@example.com"])
      end

      it "maps sbom with default format" do
        args = server.build_cli_args("sbom", nil)
        args.should eq(["sbom", "--format=spdx", "--output=/dev/stdout"])
      end

      it "maps sbom with cyclonedx format" do
        arguments = JSON.parse(%({"format": "cyclonedx", "include_dev": true}))
        args = server.build_cli_args("sbom", arguments)
        args.should eq(["sbom", "--format=cyclonedx", "--output=/dev/stdout", "--include-dev"])
      end
    end

    describe "SUPPORTED_VERSIONS" do
      it "includes all 4 protocol versions" do
        ComplianceMCPServer::SUPPORTED_VERSIONS.should eq([
          "2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05",
        ])
      end

      it "has latest version as first entry" do
        ComplianceMCPServer::LATEST_VERSION.should eq("2025-11-25")
      end
    end

    describe "#negotiate_version" do
      server = ComplianceMCPServer.new(Dir.current)

      it "returns latest when client sends nil" do
        server.negotiate_version(nil).should eq("2025-11-25")
      end

      it "returns exact match for supported version" do
        server.negotiate_version("2024-11-05").should eq("2024-11-05")
        server.negotiate_version("2025-03-26").should eq("2025-03-26")
        server.negotiate_version("2025-06-18").should eq("2025-06-18")
        server.negotiate_version("2025-11-25").should eq("2025-11-25")
      end

      it "returns latest when client requests newer unknown version" do
        server.negotiate_version("2026-01-01").should eq("2025-11-25")
      end

      it "returns closest older version for unknown version between supported" do
        server.negotiate_version("2025-08-01").should eq("2025-06-18")
        server.negotiate_version("2025-01-01").should eq("2024-11-05")
      end

      it "returns oldest for version older than all supported" do
        server.negotiate_version("2020-01-01").should eq("2024-11-05")
      end
    end

    describe "SERVER_INFO" do
      it "has correct name" do
        ComplianceMCPServer::SERVER_INFO.name.should eq("shards-compliance")
      end

      it "has version matching Shards::VERSION" do
        ComplianceMCPServer::SERVER_INFO.version.should eq(Shards::VERSION)
      end
    end

    describe "CAPABILITIES" do
      it "advertises tools capability" do
        ComplianceMCPServer::CAPABILITIES.tools.should_not be_nil
      end
    end

    describe "HELP_TEXT" do
      it "includes usage information" do
        ComplianceMCPServer::HELP_TEXT.should contain("shards-alpha mcp-server")
      end

      it "lists all 6 tool names" do
        ComplianceMCPServer::HELP_TEXT.should contain("audit")
        ComplianceMCPServer::HELP_TEXT.should contain("licenses")
        ComplianceMCPServer::HELP_TEXT.should contain("policy_check")
        ComplianceMCPServer::HELP_TEXT.should contain("diff")
        ComplianceMCPServer::HELP_TEXT.should contain("compliance_report")
        ComplianceMCPServer::HELP_TEXT.should contain("sbom")
      end

      it "includes init command and examples" do
        ComplianceMCPServer::HELP_TEXT.should contain("init")
        ComplianceMCPServer::HELP_TEXT.should contain("Configure .mcp.json, skills, agents for Claude Code")
      end

      it "documents --interactive and --help flags" do
        ComplianceMCPServer::HELP_TEXT.should contain("--interactive")
        ComplianceMCPServer::HELP_TEXT.should contain("--help")
      end
    end
  end
end
