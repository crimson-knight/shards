require "json"
require "./demo_analytics"

# Minimal MCP server over stdio (JSON-RPC 2.0).
# Exposes a single `query_analytics` tool that returns demo metric data.

STDIN.sync = true
STDOUT.sync = true
STDERR.sync = true

MCP_PROTOCOL_VERSION = "2024-11-05"

def send_response(response)
  STDOUT.puts(response.to_json)
  STDOUT.flush
end

def handle_initialize(id)
  {
    "jsonrpc" => "2.0",
    "id"      => id,
    "result"  => {
      "protocolVersion" => MCP_PROTOCOL_VERSION,
      "capabilities"    => {"tools" => {} of String => String},
      "serverInfo"      => {
        "name"    => "demo_analytics",
        "version" => DemoAnalytics::VERSION,
      },
    },
  }
end

def handle_tools_list(id)
  {
    "jsonrpc" => "2.0",
    "id"      => id,
    "result"  => {
      "tools" => [
        {
          "name"        => "query_analytics",
          "description" => "Query demo analytics data. Returns sample metrics for page_views, users, or events.",
          "inputSchema" => {
            "type"       => "object",
            "properties" => {
              "metric" => {
                "type"        => "string",
                "description" => "The metric to query: page_views, users, or events",
              },
            },
            "required" => ["metric"],
          },
        },
      ],
    },
  }
end

def handle_tools_call(id, params)
  tool_name = params.try(&.["name"]?.try(&.as_s))
  arguments = params.try(&.["arguments"]?)

  case tool_name
  when "query_analytics"
    metric = arguments.try(&.["metric"]?.try(&.as_s)) || "unknown"
    result = DemoAnalytics.query(metric)
    {
      "jsonrpc" => "2.0",
      "id"      => id,
      "result"  => {
        "content" => [{"type" => "text", "text" => result}],
      },
    }
  else
    error_response(id, -32602, "Unknown tool: #{tool_name}")
  end
end

def error_response(id, code, message)
  {
    "jsonrpc" => "2.0",
    "id"      => id,
    "error"   => {"code" => code, "message" => message},
  }
end

loop do
  line = STDIN.gets
  break unless line
  next if line.strip.empty?

  begin
    request = JSON.parse(line)
  rescue
    next
  end

  method = request["method"]?.try(&.as_s)
  id = request["id"]?

  response = case method
             when "initialize"
               handle_initialize(id)
             when "notifications/initialized"
               nil
             when "tools/list"
               handle_tools_list(id)
             when "tools/call"
               handle_tools_call(id, request["params"]?)
             else
               error_response(id, -32601, "Method not found: #{method}") if id
             end

  send_response(response) if response
end
