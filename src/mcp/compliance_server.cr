require "json"
require "mcprotocol"
require "../version"
require "./claude_config"

module Shards
  class ComplianceMCPServer
    # Supported MCP protocol versions, newest first.
    # The server negotiates the highest version both client and server support.
    SUPPORTED_VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    LATEST_VERSION     = SUPPORTED_VERSIONS.first

    SERVER_INFO = MCProtocol::Implementation.new(
      name: "shards-compliance",
      version: Shards::VERSION
    )

    CAPABILITIES = MCProtocol::ServerCapabilities.new(
      tools: MCProtocol::ServerCapabilitiesTools.new
    )

    TOOLS = [
      MCProtocol::Tool.new(
        name: "audit",
        description: "Scan dependencies for known vulnerabilities using the OSV database. Returns vulnerability details with severity levels.",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "severity" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "enum"        => JSON::Any.new(["low", "medium", "high", "critical"].map { |s| JSON::Any.new(s) }),
              "description" => JSON::Any.new("Minimum severity filter"),
            }),
            "fail_above" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "enum"        => JSON::Any.new(["low", "medium", "high", "critical"].map { |s| JSON::Any.new(s) }),
              "description" => JSON::Any.new("Exit non-zero if vulnerabilities at or above this severity are found"),
            }),
            "ignore" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "description" => JSON::Any.new("Comma-separated advisory IDs to suppress"),
            }),
            "offline" => JSON::Any.new({
              "type"        => JSON::Any.new("boolean"),
              "description" => JSON::Any.new("Use cached vulnerability data only"),
            }),
          }),
        ),
      ),
      MCProtocol::Tool.new(
        name: "licenses",
        description: "List all dependency licenses with SPDX identifier validation. Optionally check compliance against a license policy.",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "check" => JSON::Any.new({
              "type"        => JSON::Any.new("boolean"),
              "description" => JSON::Any.new("Exit non-zero if policy violations found"),
            }),
            "detect" => JSON::Any.new({
              "type"        => JSON::Any.new("boolean"),
              "description" => JSON::Any.new("Use heuristic detection from LICENSE files"),
            }),
            "include_dev" => JSON::Any.new({
              "type"        => JSON::Any.new("boolean"),
              "description" => JSON::Any.new("Include development dependencies"),
            }),
          }),
        ),
      ),
      MCProtocol::Tool.new(
        name: "policy_check",
        description: "Check dependencies against policy rules defined in .shards-policy.yml. Validates allowed licenses, version constraints, and source requirements.",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "strict" => JSON::Any.new({
              "type"        => JSON::Any.new("boolean"),
              "description" => JSON::Any.new("Treat warnings as errors"),
            }),
          }),
        ),
      ),
      MCProtocol::Tool.new(
        name: "diff",
        description: "Show dependency changes between lockfile states. Compares added, removed, and upgraded dependencies.",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "from" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "description" => JSON::Any.new("Starting ref (git ref, file path, or 'current'). Default: HEAD"),
            }),
            "to" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "description" => JSON::Any.new("Ending ref. Default: current working tree"),
            }),
          }),
        ),
      ),
      MCProtocol::Tool.new(
        name: "compliance_report",
        description: "Generate a unified supply chain compliance report combining SBOM, audit, licenses, policy, integrity, and changelog sections.",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "sections" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "description" => JSON::Any.new("Comma-separated sections to include: sbom,audit,licenses,policy,integrity,changelog (default: all)"),
            }),
            "reviewer" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "description" => JSON::Any.new("Reviewer email for attestation"),
            }),
          }),
        ),
      ),
      MCProtocol::Tool.new(
        name: "sbom",
        description: "Generate a Software Bill of Materials (SBOM) listing all dependencies with versions, licenses, and relationships.",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "format" => JSON::Any.new({
              "type"        => JSON::Any.new("string"),
              "enum"        => JSON::Any.new(["spdx", "cyclonedx"].map { |s| JSON::Any.new(s) }),
              "description" => JSON::Any.new("SBOM format (default: spdx)"),
            }),
            "include_dev" => JSON::Any.new({
              "type"        => JSON::Any.new("boolean"),
              "description" => JSON::Any.new("Include development dependencies"),
            }),
          }),
        ),
      ),
    ]

    HELP_TEXT = <<-HELP
    shards-alpha mcp-server — MCP compliance server (JSON-RPC 2.0 over stdio)

    Usage:
        shards-alpha mcp-server [command] [options]

    Commands:
        init               Configure .mcp.json for MCP server
        (default)          Start the MCP server (stdio transport)

    Options:
        --interactive    Run in interactive mode for manual testing
        --help, -h       Show this help message

    Tools provided:
        audit              Scan dependencies for known vulnerabilities (OSV)
        licenses           List dependency licenses with SPDX validation
        policy_check       Check dependencies against policy rules
        diff               Show dependency changes between lockfile states
        compliance_report  Generate unified compliance report
        sbom               Generate Software Bill of Materials (SPDX/CycloneDX)

    Examples:
        shards-alpha mcp-server init          # Configure .mcp.json
        shards-alpha mcp-server               # Start server (for MCP clients)
        shards-alpha mcp-server --interactive  # Manual testing mode

    For Claude Code skills, agents, and settings, use:
        shards-alpha assistant init
    HELP

    MCP_SERVER_NAME = "shards-compliance"

    @path : String
    @executable : String
    @interactive : Bool
    @negotiated_version : String = LATEST_VERSION

    def initialize(@path : String, @interactive : Bool = false)
      @executable = find_executable
    end

    def self.run(path : String, args : Array(String) = [] of String)
      if args.includes?("--help") || args.includes?("-h")
        puts HELP_TEXT
        return
      end

      if args.includes?("init")
        init_mcp_config(path)
        puts ""
        puts "MCP server configured. Run 'shards-alpha assistant init' for skills, agents, and Claude Code config."
        return
      end

      interactive = args.includes?("--interactive")
      new(path, interactive).run
    end

    def self.init_mcp_config(path : String)
      mcp_path = File.join(path, ".mcp.json")
      executable = find_executable_for_config

      server_entry = {
        "command" => executable,
        "args"    => ["mcp-server"],
      }

      if File.exists?(mcp_path)
        begin
          existing = JSON.parse(File.read(mcp_path))
          servers = existing["mcpServers"]?.try(&.as_h?) || {} of String => JSON::Any

          if servers.has_key?(MCP_SERVER_NAME)
            puts "#{MCP_SERVER_NAME} is already configured in .mcp.json"
            return
          end

          # Merge into existing config
          servers[MCP_SERVER_NAME] = JSON.parse(server_entry.to_json)
          config = existing.as_h.dup
          config["mcpServers"] = JSON.parse(servers.to_json)

          File.write(mcp_path, config.to_pretty_json + "\n")
          puts "Added #{MCP_SERVER_NAME} to existing .mcp.json"
        rescue ex
          STDERR.puts "Error reading existing .mcp.json: #{ex.message}"
          STDERR.puts "Creating a new .mcp.json instead."
          write_new_mcp_config(mcp_path, server_entry)
        end
      else
        write_new_mcp_config(mcp_path, server_entry)
      end

      puts ""
      puts "MCP server configured."
      puts "Tools available: audit, licenses, policy_check, diff, compliance_report, sbom"
    end

    private def self.write_new_mcp_config(mcp_path : String, server_entry)
      config = {
        "mcpServers" => {
          MCP_SERVER_NAME => server_entry,
        },
      }
      File.write(mcp_path, config.to_pretty_json + "\n")
      puts "Created .mcp.json with #{MCP_SERVER_NAME} server"
    end

    def self.init_claude_config(path : String)
      installed = ClaudeConfig.install(path)

      if installed.empty?
        puts "Claude Code skills and agents already configured"
      else
        puts ""
        puts "Installed #{installed.size} Claude Code files:"
        skills = installed.select(&.includes?("/skills/"))
        agents = installed.select(&.includes?("/agents/"))
        other = installed.reject { |f| f.includes?("/skills/") || f.includes?("/agents/") }

        skills.each { |f| puts "  skill:    #{f}" }
        agents.each { |f| puts "  agent:    #{f}" }
        other.each { |f| puts "  config:   #{f}" }

        puts ""
        puts "Available skills: /audit, /licenses, /policy-check, /diff-deps, /compliance-report, /sbom"
        puts "Available agents: compliance-checker, security-reviewer"
      end
    end

    private def self.find_executable_for_config : String
      # Prefer shards-alpha on PATH for portability
      if Process.find_executable("shards-alpha")
        return "shards-alpha"
      end

      # Fall back to absolute path of current binary
      if path = Process.executable_path
        return path
      end

      "shards-alpha"
    end

    def run
      STDIN.sync = true
      STDOUT.sync = true
      STDERR.sync = true

      if @interactive
        run_interactive
      else
        run_stdio
      end
    end

    private def run_stdio
      STDERR.puts "shards-compliance MCP server v#{Shards::VERSION} (stdio)"
      STDERR.puts "Supported MCP versions: #{SUPPORTED_VERSIONS.join(", ")}"
      STDERR.puts "Waiting for JSON-RPC messages on stdin..."
      STDERR.flush

      loop do
        line = STDIN.gets
        break unless line
        next if line.strip.empty?

        handle_message(line)
      end
    end

    private def run_interactive
      STDERR.puts "shards-compliance MCP server v#{Shards::VERSION} (interactive)"
      STDERR.puts "Supported MCP versions: #{SUPPORTED_VERSIONS.join(", ")}"
      STDERR.puts "Type JSON-RPC messages, 'help' for examples, or 'quit' to exit."
      STDERR.puts ""
      STDERR.flush

      loop do
        STDERR.print "> "
        STDERR.flush
        line = STDIN.gets
        break unless line

        stripped = line.strip
        next if stripped.empty?
        break if stripped == "quit" || stripped == "exit"

        if stripped == "help"
          print_interactive_help
          next
        end

        handle_message(line, pretty: true)
      end

      STDERR.puts "Goodbye!"
    end

    private def print_interactive_help
      STDERR.puts <<-EXAMPLES

      Example messages:

        Initialize:
          {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}

        List tools:
          {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}

        Call audit:
          {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"audit","arguments":{}}}

        Call licenses:
          {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"licenses","arguments":{}}}

      EXAMPLES
    end

    private def handle_message(line : String, *, pretty : Bool = false)
      json = JSON.parse(line)
      method = json["method"]?.try(&.as_s)
      id = json["id"]?

      case method
      when "initialize"
        send_response(handle_initialize(id, json["params"]?), pretty: pretty)
      when "notifications/initialized"
        # No response needed for notifications
      when "ping"
        send_response(handle_ping(id), pretty: pretty)
      when "tools/list"
        send_response(handle_list_tools(id), pretty: pretty)
      when "tools/call"
        send_response(handle_call_tool(id, json["params"]?), pretty: pretty)
      else
        if id
          send_response(error_response(id, -32601_i64, "Method not found: #{method}"), pretty: pretty)
        end
      end
    rescue ex : JSON::ParseException
      # Return proper JSON-RPC -32700 parse error
      send_response(error_response(nil, -32700_i64, "Parse error: #{ex.message}"), pretty: pretty)
    rescue ex
      # Try to extract request id for the error response
      request_id = begin
        JSON.parse(line)["id"]?
      rescue
        nil
      end
      send_response(error_response(request_id, -32603_i64, "Internal error: #{ex.message}"), pretty: pretty)
    end

    private def handle_initialize(id, params = nil)
      # MCP version negotiation: server picks the highest version it supports
      # that is <= the client's requested version.
      client_version = params.try(&.["protocolVersion"]?.try(&.as_s))
      @negotiated_version = negotiate_version(client_version)

      {
        "jsonrpc" => "2.0",
        "id"      => id,
        "result"  => {
          "protocolVersion" => @negotiated_version,
          "capabilities"    => {"tools" => {} of String => String},
          "serverInfo"      => {
            "name"    => "shards-compliance",
            "version" => Shards::VERSION,
          },
        },
      }
    end

    # Negotiate the best protocol version.
    # If the client requests a version we support, use it.
    # If the client requests a version newer than our latest, use our latest.
    # If the client requests an older version we don't support, use our oldest.
    # If no version is provided, use the latest.
    def negotiate_version(client_version : String?) : String
      return LATEST_VERSION unless client_version

      # Exact match — client asks for something we support
      if SUPPORTED_VERSIONS.includes?(client_version)
        return client_version
      end

      # Client asks for something newer than us — offer our latest
      # Client asks for something between our versions — offer the closest older one
      # Sort by date comparison: versions are date-formatted strings, so string comparison works
      SUPPORTED_VERSIONS.each do |v|
        return v if v <= client_version
      end

      # Fallback: return our oldest supported version
      SUPPORTED_VERSIONS.last
    end

    private def handle_ping(id)
      {
        "jsonrpc" => "2.0",
        "id"      => id,
        "result"  => {} of String => String,
      }
    end

    private def handle_list_tools(id)
      tools_json = TOOLS.map { |tool| JSON.parse(tool.to_json) }
      {
        "jsonrpc" => "2.0",
        "id"      => id,
        "result"  => {
          "tools" => tools_json,
        },
      }
    end

    private def handle_call_tool(id, params)
      tool_name = params.try(&.["name"]?.try(&.as_s))
      arguments = params.try(&.["arguments"]?)

      unless tool_name
        return error_response(id, -32602_i64, "Missing tool name")
      end

      unless TOOLS.any? { |t| t.name == tool_name }
        return error_response(id, -32602_i64, "Unknown tool: #{tool_name}")
      end

      args = build_cli_args(tool_name, arguments)
      stdout, stderr, exit_code = run_shards_command(args)

      # Commands like audit use exit code 1 to signal "vulnerabilities found" (not an error).
      # We treat those as successful results with the exit code in metadata.
      is_error = exit_code != 0 && !expected_nonzero_exit?(tool_name, exit_code)

      output = stdout.empty? ? stderr : stdout

      # Try to parse as JSON for structured content
      structured = begin
        JSON.parse(output) unless output.strip.empty?
      rescue
        nil
      end

      content = [{"type" => "text", "text" => output}] of Hash(String, String)

      result = if structured
                 {
                   "content"           => content,
                   "isError"           => is_error,
                   "structuredContent" => structured,
                   "_meta"             => {"exit_code" => exit_code},
                 }
               else
                 {
                   "content" => content,
                   "isError" => is_error,
                   "_meta"   => {"exit_code" => exit_code},
                 }
               end

      {
        "jsonrpc" => "2.0",
        "id"      => id,
        "result"  => result,
      }
    end

    # Build CLI arguments from tool name and parameters
    def build_cli_args(tool_name : String, arguments : JSON::Any?) : Array(String)
      args = [] of String

      case tool_name
      when "audit"
        args << "audit" << "--format=json"
        if arguments
          if v = arguments["severity"]?.try(&.as_s)
            args << "--severity=#{v}"
          end
          if v = arguments["fail_above"]?.try(&.as_s)
            args << "--fail-above=#{v}"
          end
          if v = arguments["ignore"]?.try(&.as_s)
            args << "--ignore=#{v}"
          end
          if arguments["offline"]?.try(&.as_bool)
            args << "--offline"
          end
        end
      when "licenses"
        args << "licenses" << "--format=json"
        if arguments
          if arguments["check"]?.try(&.as_bool)
            args << "--check"
          end
          if arguments["detect"]?.try(&.as_bool)
            args << "--detect"
          end
          if arguments["include_dev"]?.try(&.as_bool)
            args << "--include-dev"
          end
        end
      when "policy_check"
        args << "policy" << "check" << "--format=json"
        if arguments
          if arguments["strict"]?.try(&.as_bool)
            args << "--strict"
          end
        end
      when "diff"
        args << "diff" << "--format=json"
        if arguments
          if v = arguments["from"]?.try(&.as_s)
            args << "--from=#{v}"
          end
          if v = arguments["to"]?.try(&.as_s)
            args << "--to=#{v}"
          end
        end
      when "compliance_report"
        args << "compliance-report" << "--format=json"
        if arguments
          if v = arguments["sections"]?.try(&.as_s)
            args << "--sections=#{v}"
          end
          if v = arguments["reviewer"]?.try(&.as_s)
            args << "--reviewer=#{v}"
          end
        end
      when "sbom"
        fmt = arguments.try(&.["format"]?.try(&.as_s)) || "spdx"
        args << "sbom" << "--format=#{fmt}" << "--output=/dev/stdout"
        if arguments
          if arguments["include_dev"]?.try(&.as_bool)
            args << "--include-dev"
          end
        end
      end

      args
    end

    private def run_shards_command(args : Array(String)) : {String, String, Int32}
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      status = Process.run(
        @executable, args,
        output: stdout, error: stderr, chdir: @path
      )

      {stdout.to_s, stderr.to_s, status.exit_code}
    rescue ex
      {"", "Failed to execute command: #{ex.message}", 1}
    end

    private def expected_nonzero_exit?(tool_name : String, exit_code : Int32) : Bool
      # audit exits 1 when vulnerabilities are found
      # licenses --check exits 1 when violations are found
      # policy check exits 1 when violations are found
      case tool_name
      when "audit", "licenses", "policy_check"
        exit_code == 1
      else
        false
      end
    end

    private def find_executable : String
      # Try to find ourselves first
      if path = Process.executable_path
        return path
      end

      # Fall back to finding shards-alpha on PATH
      if path = Process.find_executable("shards-alpha")
        return path
      end

      # Last resort: find shards on PATH
      if path = Process.find_executable("shards")
        return path
      end

      raise "Could not find shards-alpha executable"
    end

    private def send_response(response, *, pretty : Bool = false)
      json_str = response.to_json
      if pretty
        STDOUT.puts(JSON.parse(json_str).to_pretty_json)
      else
        STDOUT.puts(json_str)
      end
      STDOUT.flush
    end

    private def error_response(id : JSON::Any?, code : Int64, message : String)
      {
        "jsonrpc" => "2.0",
        "id"      => id,
        "error"   => {"code" => code, "message" => message},
      }
    end
  end
end
