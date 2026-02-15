# Minimal MCP stdio server for end-to-end testing.
#
# Implements just enough of the MCP protocol (JSON-RPC 2.0 over stdio)
# to expose a single tool: `get_shards_build_info`.
#
# The tool returns a known phrase ("SHARDS_MCP_VERIFIED_2026") that the
# E2E test script can grep for in Claude Code's output to confirm the
# tool was actually invoked.
#
# Protocol: newline-delimited JSON-RPC 2.0 (MCP stdio transport)

require "json"

STDOUT.sync = true
STDERR.sync = true

STDERR.puts "[shards-test-mcp] Server starting..."

loop do
  line = STDIN.gets
  break unless line
  next if line.blank?

  begin
    msg = JSON.parse(line)
  rescue ex
    STDERR.puts "[shards-test-mcp] Parse error: #{ex.message}"
    next
  end

  method = msg["method"]?.try(&.as_s?)
  id = msg["id"]?

  case method
  when "initialize"
    response = JSON.build do |json|
      json.object do
        json.field "jsonrpc", "2.0"
        json.field "id", id
        json.field "result" do
          json.object do
            json.field "protocolVersion", "2024-11-05"
            json.field "capabilities" do
              json.object do
                json.field "tools" do
                  json.object { }
                end
              end
            end
            json.field "serverInfo" do
              json.object do
                json.field "name", "shards-test-mcp"
                json.field "version", "1.0.0"
              end
            end
          end
        end
      end
    end
    puts response
    STDERR.puts "[shards-test-mcp] Initialized"
  when "notifications/initialized"
    # Notification — no response needed
    STDERR.puts "[shards-test-mcp] Client initialized"
  when "tools/list"
    response = JSON.build do |json|
      json.object do
        json.field "jsonrpc", "2.0"
        json.field "id", id
        json.field "result" do
          json.object do
            json.field "tools" do
              json.array do
                json.object do
                  json.field "name", "get_shards_build_info"
                  json.field "description", "Returns build verification info for the shards MCP lifecycle test. Call this tool to get the magic verification phrase."
                  json.field "inputSchema" do
                    json.object do
                      json.field "type", "object"
                      json.field "properties" do
                        json.object { }
                      end
                      json.field "required" do
                        json.array { }
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    puts response
    STDERR.puts "[shards-test-mcp] Listed tools"
  when "tools/call"
    tool_name = msg.dig?("params", "name").try(&.as_s?) || "unknown"
    STDERR.puts "[shards-test-mcp] Tool call: #{tool_name}"

    response = JSON.build do |json|
      json.object do
        json.field "jsonrpc", "2.0"
        json.field "id", id
        json.field "result" do
          json.object do
            json.field "content" do
              json.array do
                json.object do
                  json.field "type", "text"
                  json.field "text", "SHARDS_MCP_VERIFIED_2026"
                end
              end
            end
          end
        end
      end
    end
    puts response
    STDERR.puts "[shards-test-mcp] Responded with verification phrase"
  when "ping"
    response = JSON.build do |json|
      json.object do
        json.field "jsonrpc", "2.0"
        json.field "id", id
        json.field "result" do
          json.object { }
        end
      end
    end
    puts response
  else
    if id
      # Unknown method with an id — return method not found
      response = JSON.build do |json|
        json.object do
          json.field "jsonrpc", "2.0"
          json.field "id", id
          json.field "error" do
            json.object do
              json.field "code", -32601
              json.field "message", "Method not found: #{method}"
            end
          end
        end
      end
      puts response
      STDERR.puts "[shards-test-mcp] Unknown method: #{method}"
    end
  end
end

STDERR.puts "[shards-test-mcp] Server shutting down"
