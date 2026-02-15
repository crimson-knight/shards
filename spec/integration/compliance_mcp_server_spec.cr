require "./spec_helper"
require "json"

private SHARDS_BIN = File.expand_path("../../bin/shards-alpha", __DIR__)

private def send_mcp_messages(messages : Array(String), *, chdir : String = application_path) : Array(JSON::Any)
  input = IO::Memory.new
  messages.each { |msg| input << msg << "\n" }
  input.rewind

  output = IO::Memory.new
  error = IO::Memory.new

  Process.run(
    SHARDS_BIN, ["mcp-server"],
    input: input, output: output, error: error,
    chdir: chdir
  )

  output.to_s.each_line.compact_map do |line|
    next if line.strip.empty?
    JSON.parse(line) rescue nil
  end.to_a
end

private def run_mcp_server(args : Array(String), input_text : String = "", *, chdir : String = application_path) : {String, String, Int32}
  input = IO::Memory.new(input_text)
  output = IO::Memory.new
  error = IO::Memory.new

  status = Process.run(
    SHARDS_BIN, ["mcp-server"] + args,
    input: input, output: output, error: error,
    chdir: chdir
  )

  {output.to_s, error.to_s, status.exit_code}
end

private def init_message(id = 1, version = "2025-11-25")
  {
    jsonrpc: "2.0",
    id:      id,
    method:  "initialize",
    params:  {
      protocolVersion: version,
      capabilities:    {} of String => String,
      clientInfo:      {name: "test", version: "1.0"},
    },
  }.to_json
end

private def tools_list_message(id = 2)
  {jsonrpc: "2.0", id: id, method: "tools/list", params: {} of String => String}.to_json
end

private def tool_call_message(name : String, arguments = {} of String => String, id = 3)
  {jsonrpc: "2.0", id: id, method: "tools/call", params: {name: name, arguments: arguments}}.to_json
end

describe "MCP compliance server" do
  it "responds to initialize with correct protocol version" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([init_message])
      responses.size.should eq(1)
      result = responses[0]["result"]
      result["protocolVersion"].as_s.should eq("2025-11-25")
      result["serverInfo"]["name"].as_s.should eq("shards-compliance")
      result["capabilities"]["tools"].should_not be_nil
    end
  end

  it "negotiates to client-requested version when supported" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([init_message(version: "2024-11-05")])
      responses.size.should eq(1)
      result = responses[0]["result"]
      result["protocolVersion"].as_s.should eq("2024-11-05")
    end
  end

  it "negotiates to latest when client requests unknown newer version" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([init_message(version: "2099-01-01")])
      responses.size.should eq(1)
      result = responses[0]["result"]
      result["protocolVersion"].as_s.should eq("2025-11-25")
    end
  end

  it "returns all 6 tools from tools/list" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([init_message, tools_list_message])
      responses.size.should eq(2)

      tools = responses[1]["result"]["tools"].as_a
      tools.size.should eq(6)
      tool_names = tools.map { |t| t["name"].as_s }
      tool_names.should contain("audit")
      tool_names.should contain("licenses")
      tool_names.should contain("policy_check")
      tool_names.should contain("diff")
      tool_names.should contain("compliance_report")
      tool_names.should contain("sbom")
    end
  end

  it "returns tool schemas with correct structure" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([init_message, tools_list_message])
      tools = responses[1]["result"]["tools"].as_a

      tools.each do |tool|
        tool["name"].as_s.should_not be_empty
        tool["description"].as_s.should_not be_empty
        tool["inputSchema"]["type"].as_s.should eq("object")
      end
    end
  end

  it "executes licenses tool and returns JSON content" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([
        init_message,
        tool_call_message("licenses"),
      ])
      responses.size.should eq(2)

      result = responses[1]["result"]
      result["isError"].as_bool.should be_false
      content = result["content"].as_a
      content.size.should eq(1)
      content[0]["type"].as_s.should eq("text")

      # Output should be valid JSON
      text = content[0]["text"].as_s
      parsed = JSON.parse(text)
      parsed["project"].as_s.should eq("test")
      parsed["dependencies"].as_a.size.should be > 0
    end
  end

  it "executes sbom tool and returns SPDX output" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([
        init_message,
        tool_call_message("sbom"),
      ])
      responses.size.should eq(2)

      result = responses[1]["result"]
      result["isError"].as_bool.should be_false
      text = result["content"].as_a[0]["text"].as_s
      # SBOM output should contain SPDX markers
      text.should contain("spdxVersion")
    end
  end

  it "returns error for unknown tool" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([
        init_message,
        tool_call_message("nonexistent_tool"),
      ])
      responses.size.should eq(2)

      error = responses[1]["error"]
      error["code"].as_i.should eq(-32602)
      error["message"].as_s.should contain("Unknown tool")
    end
  end

  it "returns error for unknown method" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      msg = {jsonrpc: "2.0", id: 1, method: "resources/list", params: {} of String => String}.to_json
      responses = send_mcp_messages([msg])
      responses.size.should eq(1)

      error = responses[0]["error"]
      error["code"].as_i.should eq(-32601)
      error["message"].as_s.should contain("Method not found")
    end
  end

  it "responds to ping" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      msg = {jsonrpc: "2.0", id: 1, method: "ping", params: nil}.to_json
      responses = send_mcp_messages([msg])
      responses.size.should eq(1)
      responses[0]["result"].should_not be_nil
    end
  end

  it "includes structuredContent for JSON tool output" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([
        init_message,
        tool_call_message("licenses"),
      ])
      result = responses[1]["result"]
      structured = result["structuredContent"]?
      unless structured.nil?
        structured["project"].as_s.should eq("test")
      end
    end
  end

  it "includes exit_code in _meta" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages([
        init_message,
        tool_call_message("licenses"),
      ])
      result = responses[1]["result"]
      result["_meta"]["exit_code"].as_i.should eq(0)
    end
  end

  it "shows help with --help flag" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      stdout, _stderr, exit_code = run_mcp_server(["--help"])
      exit_code.should eq(0)
      stdout.should contain("shards-alpha mcp-server")
      stdout.should contain("--interactive")
      stdout.should contain("init")
      stdout.should contain("audit")
      stdout.should contain("licenses")
    end
  end

  it "prints startup banner to stderr in stdio mode" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      _stdout, stderr, _exit_code = run_mcp_server([] of String)
      stderr.should contain("shards-compliance MCP server")
      stderr.should contain("Supported MCP versions:")
      stderr.should contain("2025-11-25")
      stderr.should contain("Waiting for JSON-RPC messages")
    end
  end

  it "returns JSON-RPC parse error for invalid input" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages(["not valid json"])
      responses.size.should eq(1)

      error = responses[0]["error"]
      error["code"].as_i.should eq(-32700)
      error["message"].as_s.should contain("Parse error")
    end
  end

  it "returns parse error with null id for malformed JSON" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      responses = send_mcp_messages(["{ broken"])
      responses.size.should eq(1)
      responses[0]["id"].raw.should be_nil
    end
  end

  it "init creates .mcp.json when none exists" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      File.delete(".mcp.json") if File.exists?(".mcp.json")

      stdout, _stderr, exit_code = run_mcp_server(["init"])
      exit_code.should eq(0)
      stdout.should contain("Created .mcp.json")

      File.exists?(".mcp.json").should be_true
      config = JSON.parse(File.read(".mcp.json"))
      config["mcpServers"]["shards-compliance"]["args"].as_a[0].as_s.should eq("mcp-server")
    end
  end

  it "init merges into existing .mcp.json" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      File.write(".mcp.json", %({"mcpServers":{"other":{"command":"node","args":["x"]}}}))

      stdout, _stderr, exit_code = run_mcp_server(["init"])
      exit_code.should eq(0)
      stdout.should contain("Added shards-compliance")

      config = JSON.parse(File.read(".mcp.json"))
      config["mcpServers"]["other"].should_not be_nil
      config["mcpServers"]["shards-compliance"].should_not be_nil
    end
  end

  it "init is idempotent" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      File.delete(".mcp.json") if File.exists?(".mcp.json")

      run_mcp_server(["init"])
      stdout, _stderr, _exit_code = run_mcp_server(["init"])
      stdout.should contain("already configured")
    end
  end
end
