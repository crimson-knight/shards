require "http/server"
require "json"
require "../src/mcprotocol"

class SSEMCPServer
  def initialize(@port : Int32 = 8080)
    @tools = [
      MCProtocol::Tool.new(
        name: "get_timestamp",
        description: "Get the current timestamp",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({} of String => JSON::Any),
          type: "object"
        )
      ),
      MCProtocol::Tool.new(
        name: "echo_message",
        description: "Echo back a message with formatting",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "message" => JSON::Any.new({
              "type" => JSON::Any.new("string"),
              "description" => JSON::Any.new("Message to echo back")
            })
          }),
          required: ["message"],
          type: "object"
        )
      )
    ]

    @resources = [
      MCProtocol::Resource.new(
        uri: URI.parse("sse://localhost:#{@port}/status"),
        name: "Server Status",
        description: "Current server status and metrics",
        mimeType: "application/json"
      ),
      MCProtocol::Resource.new(
        uri: URI.parse("sse://localhost:#{@port}/logs"),
        name: "Server Logs",
        description: "Recent server log entries",
        mimeType: "text/plain"
      )
    ]

    @server = HTTP::Server.new do |context|
      handle_request(context)
    end
  end

  def start
    puts "Starting MCP SSE server on http://localhost:#{@port}"
    puts "Available endpoints:"
    puts "  GET /mcp - MCP protocol endpoint (SSE)"
    puts "  GET /health - Health check"
    puts "  GET /docs - API documentation"
    @server.bind_tcp(@port)
    @server.listen
  end

  private def handle_request(context)
    case context.request.path
    when "/mcp"
      handle_mcp_connection(context)
    when "/health"
      handle_health_check(context)
    when "/docs"
      handle_documentation(context)
    else
      context.response.status = HTTP::Status::NOT_FOUND
      context.response.print "Not Found"
    end
  end

  private def handle_mcp_connection(context)
    # Set SSE headers
    context.response.headers["Content-Type"] = "text/event-stream"
    context.response.headers["Cache-Control"] = "no-cache"
    context.response.headers["Connection"] = "keep-alive"
    context.response.headers["Access-Control-Allow-Origin"] = "*"
    context.response.headers["Access-Control-Allow-Headers"] = "Content-Type"

    puts "New MCP connection from #{context.request.remote_address}"

    # Send welcome message
    send_sse_message(context, %{{"type":"welcome","message":"MCP SSE Server Ready"}}, "welcome")

    # Handle incoming messages via POST body or query parameters
    if context.request.method == "POST"
      handle_post_messages(context)
    else
      handle_get_connection(context)
    end
  rescue ex
    puts "Connection error: #{ex.message}"
    send_sse_message(context, %{{"type":"error","message":"#{ex.message}"}}, "error")
  end

  private def handle_get_connection(context)
    # For GET requests, send periodic status updates
    loop do
      begin
        status = {
          "timestamp" => Time.utc.to_rfc3339,
          "connections" => 1,
          "uptime" => Time.utc.to_unix - @start_time.to_unix
        }
        
        send_sse_message(context, status.to_json, "status")
        sleep 5.seconds
        
        break if context.response.closed?
      rescue ex
        puts "SSE loop error: #{ex.message}"
        break
      end
    end
  end

  private def handle_post_messages(context)
    body = context.request.body.try(&.gets_to_end)
    return unless body

    begin
      # Parse JSON-RPC message
      request = MCProtocol.parse_message(body)
      response = handle_mcp_request(request)
      
      if response
        send_sse_message(context, response.to_json, "response")
      end
    rescue ex : MCProtocol::ParseError
      error_response = create_error_response(-32700, "Parse error: #{ex.message}")
      send_sse_message(context, error_response.to_json, "error")
    rescue ex
      error_response = create_error_response(-32603, "Internal error: #{ex.message}")
      send_sse_message(context, error_response.to_json, "error")
    end
  end

  private def handle_mcp_request(request : MCProtocol::ClientRequest)
    case request
    when MCProtocol::InitializeRequest
      handle_initialize_request(request)
    when MCProtocol::ListToolsRequest
      handle_list_tools_request(request)
    when MCProtocol::CallToolRequest
      handle_call_tool_request(request)
    when MCProtocol::ListResourcesRequest
      handle_list_resources_request(request)
    when MCProtocol::ReadResourceRequest
      handle_read_resource_request(request)
    when MCProtocol::PingRequest
      handle_ping_request(request)
    else
      create_error_response(-32601, "Method not found")
    end
  end

  private def handle_initialize_request(request : MCProtocol::InitializeRequest)
    puts "Handling initialize request from client: #{request.params.clientInfo.name}"
    
    {
      "jsonrpc" => "2.0",
      "id" => 1, # Should match request ID
      "result" => {
        "protocolVersion" => "2024-11-05",
        "capabilities" => {
          "tools" => {
            "listChanged" => true
          },
          "resources" => {
            "subscribe" => false,
            "listChanged" => true
          },
          "logging" => {} of String => JSON::Any
        },
        "serverInfo" => {
          "name" => "sse-mcp-server",
          "version" => "1.0.0"
        }
      }
    }
  end

  private def handle_list_tools_request(request : MCProtocol::ListToolsRequest)
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "tools" => @tools.map(&.to_json).map { |t| JSON.parse(t) }
      }
    }
  end

  private def handle_call_tool_request(request : MCProtocol::CallToolRequest)
    tool_name = request.params.name
    arguments = request.params.arguments

    case tool_name
    when "get_timestamp"
      result = {
        "content" => [{
          "type" => "text",
          "text" => "Current timestamp: #{Time.utc.to_rfc3339}"
        }],
        "isError" => false
      }
    when "echo_message"
      message = arguments.try(&.["message"]?.try(&.as_s?)) || "No message provided"
      result = {
        "content" => [{
          "type" => "text", 
          "text" => "Echo from SSE server: #{message}"
        }],
        "isError" => false
      }
    else
      result = {
        "content" => [{
          "type" => "text",
          "text" => "Unknown tool: #{tool_name}"
        }],
        "isError" => true
      }
    end

    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => result
    }
  end

  private def handle_list_resources_request(request : MCProtocol::ListResourcesRequest)
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "resources" => @resources.map(&.to_json).map { |r| JSON.parse(r) }
      }
    }
  end

  private def handle_read_resource_request(request : MCProtocol::ReadResourceRequest)
    uri = request.params.uri.to_s

    content = case uri
    when "sse://localhost:#{@port}/status"
      {
        "timestamp" => Time.utc.to_rfc3339,
        "server" => "SSE MCP Server",
        "version" => "1.0.0",
        "tools_count" => @tools.size,
        "resources_count" => @resources.size
      }.to_json
    when "sse://localhost:#{@port}/logs"
      "#{Time.utc.to_rfc3339} - Server started\n#{Time.utc.to_rfc3339} - Resource accessed: #{uri}"
    else
      "Resource not found: #{uri}"
    end

    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "contents" => [{
          "uri" => uri,
          "mimeType" => uri.ends_with?("/status") ? "application/json" : "text/plain",
          "text" => content
        }]
      }
    }
  end

  private def handle_ping_request(request : MCProtocol::PingRequest)
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {} of String => JSON::Any
    }
  end

  private def handle_health_check(context)
    context.response.content_type = "application/json"
    status = {
      "status" => "healthy",
      "timestamp" => Time.utc.to_rfc3339,
      "mcp_version" => "2024-11-05",
      "endpoints" => ["/mcp", "/health", "/docs"]
    }
    context.response.print status.to_json
  end

  private def handle_documentation(context)
    context.response.content_type = "text/html"
    context.response.print <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>SSE MCP Server Documentation</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            code { background: #f4f4f4; padding: 2px 4px; border-radius: 3px; }
            pre { background: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }
        </style>
    </head>
    <body>
        <h1>SSE MCP Server Documentation</h1>
        
        <h2>Endpoints</h2>
        <ul>
            <li><code>GET /mcp</code> - MCP protocol endpoint using Server-Sent Events</li>
            <li><code>POST /mcp</code> - Send MCP JSON-RPC messages</li>
            <li><code>GET /health</code> - Health check endpoint</li>
            <li><code>GET /docs</code> - This documentation</li>
        </ul>
        
        <h2>Available Tools</h2>
        <ul>
            <li><code>get_timestamp</code> - Returns current timestamp</li>
            <li><code>echo_message</code> - Echoes back a message</li>
        </ul>
        
        <h2>Available Resources</h2>
        <ul>
            <li><code>sse://localhost:#{@port}/status</code> - Server status (JSON)</li>
            <li><code>sse://localhost:#{@port}/logs</code> - Server logs (text)</li>
        </ul>
        
        <h2>Example Usage</h2>
        <h3>Initialize Connection</h3>
        <pre><code>curl -X POST http://localhost:#{@port}/mcp \\
        -H "Content-Type: application/json" \\
        -d '{
          "jsonrpc": "2.0",
          "id": 1,
          "method": "initialize",
          "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {
              "name": "test-client",
              "version": "1.0.0"
            }
          }
        }'</code></pre>
        
        <h3>Call Tool</h3>
        <pre><code>curl -X POST http://localhost:#{@port}/mcp \\
        -H "Content-Type: application/json" \\
        -d '{
          "jsonrpc": "2.0",
          "id": 2,
          "method": "tools/call",
          "params": {
            "name": "echo_message",
            "arguments": {
              "message": "Hello from SSE!"
            }
          }
        }'</code></pre>
    </body>
    </html>
    HTML
  end

  private def send_sse_message(context, data : String, event : String? = nil)
    if event
      context.response.print "event: #{event}\n"
    end
    context.response.print "data: #{data}\n\n"
    context.response.flush
  end

  private def create_error_response(code : Int32, message : String)
    {
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => {
        "code" => code,
        "message" => message
      }
    }
  end

  @start_time = Time.utc
end

# Start the server
if ARGV.includes?("--help") || ARGV.includes?("-h")
  puts "SSE MCP Server"
  puts ""
  puts "Usage: crystal run sse_server.cr [options]"
  puts ""
  puts "Options:"
  puts "  --port PORT    Set server port (default: 8080)"
  puts "  --help, -h     Show this help message"
  puts ""
  puts "Examples:"
  puts "  crystal run sse_server.cr"
  puts "  crystal run sse_server.cr --port 3000"
  exit
end

port = 8080
if port_index = ARGV.index("--port")
  if port_value = ARGV[port_index + 1]?
    port = port_value.to_i32
  end
end

server = SSEMCPServer.new(port)
server.start 