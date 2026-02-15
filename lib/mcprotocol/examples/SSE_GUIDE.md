# SSE MCP Server Implementation Guide

This guide focuses specifically on implementing MCP servers using Server-Sent Events (SSE), which is perfect for real-time communication with AI applications.

## Why SSE for MCP?

Server-Sent Events provide several advantages for MCP servers:

- **Real-time Communication**: Continuous connection for instant responses
- **HTTP-based**: Works with existing web infrastructure  
- **Built-in Reconnection**: Automatic reconnection handling
- **Simple Protocol**: Easier than WebSockets for server-to-client communication
- **Cross-Origin Support**: Works with CORS for web applications

## Basic SSE MCP Server

Here's a complete implementation of an SSE-based MCP server:

```crystal
require "http/server"
require "json"
require "mcprotocol"

class SSEMCPServer
  def initialize(@port : Int32 = 8080)
    @tools = [] of MCProtocol::Tool
    @resources = [] of MCProtocol::Resource
    @capabilities = MCProtocol::ServerCapabilities.new
    @server_info = MCProtocol::Implementation.new(
      name: "sse-mcp-server",
      version: "1.0.0"
    )
    
    setup_tools_and_resources
    setup_http_server
  end

  def start
    puts "🚀 Starting SSE MCP Server on port #{@port}"
    puts "📡 MCP Endpoint: http://localhost:#{@port}/mcp"
    puts "🏥 Health Check: http://localhost:#{@port}/health"
    puts "📚 Documentation: http://localhost:#{@port}/docs"
    
    @server.bind_tcp(@port)
    @server.listen
  end

  private def setup_tools_and_resources
    # Add your tools and resources here
    @tools << MCProtocol::Tool.new(
      name: "current_time",
      description: "Get the current server time",
      inputSchema: MCProtocol::ToolInputSchema.new(
        properties: JSON::Any.new({
          "timezone" => JSON::Any.new({
            "type" => JSON::Any.new("string"),
            "description" => JSON::Any.new("Timezone (optional)")
          })
        }),
        type: "object"
      )
    )

    @capabilities = MCProtocol::ServerCapabilities.new(
      tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: true),
      resources: MCProtocol::ServerCapabilitiesResources.new(subscribe: false)
    )
  end

  private def setup_http_server
    @server = HTTP::Server.new do |context|
      case context.request.path
      when "/mcp"
        handle_mcp_endpoint(context)
      when "/health"
        handle_health_check(context)
      when "/docs"
        handle_documentation(context)
      else
        context.response.status = HTTP::Status::NOT_FOUND
        context.response.print "Not Found"
      end
    end
  end

  private def handle_mcp_endpoint(context)
    case context.request.method
    when "GET"
      handle_sse_connection(context)
    when "POST"
      handle_mcp_message(context)
    when "OPTIONS"
      handle_preflight(context)
    else
      context.response.status = HTTP::Status::METHOD_NOT_ALLOWED
    end
  end

  private def handle_sse_connection(context)
    # Set SSE headers
    set_sse_headers(context)
    
    # Send welcome message
    send_sse_event(context, "welcome", {
      "message" => "Connected to SSE MCP Server",
      "server" => @server_info.name,
      "version" => @server_info.version,
      "timestamp" => Time.utc.to_rfc3339
    })

    # Keep connection alive with periodic heartbeats
    spawn do
      loop do
        sleep 30
        begin
          send_sse_event(context, "heartbeat", {
            "timestamp" => Time.utc.to_rfc3339
          })
        rescue
          break # Connection closed
        end
      end
    end

    # Wait for client to close connection
    context.request.body.try(&.read(Bytes.new(0)))
  end

  private def handle_mcp_message(context)
    set_cors_headers(context)
    
    body = context.request.body.try(&.gets_to_end)
    unless body
      context.response.status = HTTP::Status::BAD_REQUEST
      context.response.print %{{"error": "No request body"}}
      return
    end

    begin
      # Parse and handle the MCP message
      request = MCProtocol.parse_message(body)
      response = process_mcp_request(request)
      
      # Send response
      context.response.content_type = "application/json"
      context.response.print response.to_json
      
    rescue ex : MCProtocol::ParseError
      send_error_response(context, -32700, "Parse error: #{ex.message}")
    rescue ex
      send_error_response(context, -32603, "Internal error: #{ex.message}")
    end
  end

  private def process_mcp_request(request : MCProtocol::ClientRequest)
    case request
    when MCProtocol::InitializeRequest
      process_initialize(request)
    when MCProtocol::ListToolsRequest
      process_list_tools(request)
    when MCProtocol::CallToolRequest
      process_call_tool(request)
    when MCProtocol::ListResourcesRequest
      process_list_resources(request)
    when MCProtocol::ReadResourceRequest
      process_read_resource(request)
    when MCProtocol::PingRequest
      process_ping(request)
    else
      create_error_response(-32601, "Method not found")
    end
  end

  private def process_initialize(request : MCProtocol::InitializeRequest)
    puts "📞 Initialize request from: #{request.params.clientInfo.name}"
    
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "protocolVersion" => request.params.protocolVersion,
        "capabilities" => JSON.parse(@capabilities.to_json),
        "serverInfo" => JSON.parse(@server_info.to_json)
      }
    }
  end

  private def process_list_tools(request : MCProtocol::ListToolsRequest)
    puts "🔧 Listing #{@tools.size} tools"
    
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "tools" => @tools.map { |tool| JSON.parse(tool.to_json) }
      }
    }
  end

  private def process_call_tool(request : MCProtocol::CallToolRequest)
    tool_name = request.params.name
    arguments = request.params.arguments
    
    puts "⚡ Calling tool: #{tool_name}"

    result = case tool_name
    when "current_time"
      handle_current_time_tool(arguments)
    else
      {
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

  private def handle_current_time_tool(arguments)
    timezone = arguments.try(&.["timezone"]?.try(&.as_s?))
    
    time_str = if timezone
      # Basic timezone handling - you'd want proper timezone support
      Time.utc.to_s + " (requested: #{timezone})"
    else
      Time.utc.to_rfc3339
    end

    {
      "content" => [{
        "type" => "text",
        "text" => "Current time: #{time_str}"
      }],
      "isError" => false
    }
  end

  private def process_list_resources(request : MCProtocol::ListResourcesRequest)
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "resources" => @resources.map { |resource| JSON.parse(resource.to_json) }
      }
    }
  end

  private def process_read_resource(request : MCProtocol::ReadResourceRequest)
    uri = request.params.uri.to_s
    
    # Implement resource reading logic here
    content = "Resource content for: #{uri}"
    
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "contents" => [{
          "uri" => uri,
          "mimeType" => "text/plain",
          "text" => content
        }]
      }
    }
  end

  private def process_ping(request : MCProtocol::PingRequest)
    puts "🏓 Ping received"
    
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {} of String => JSON::Any
    }
  end

  private def set_sse_headers(context)
    context.response.headers["Content-Type"] = "text/event-stream"
    context.response.headers["Cache-Control"] = "no-cache"
    context.response.headers["Connection"] = "keep-alive"
    set_cors_headers(context)
  end

  private def set_cors_headers(context)
    context.response.headers["Access-Control-Allow-Origin"] = "*"
    context.response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    context.response.headers["Access-Control-Allow-Headers"] = "Content-Type, Accept"
  end

  private def handle_preflight(context)
    set_cors_headers(context)
    context.response.status = HTTP::Status::OK
  end

  private def send_sse_event(context, event : String, data)
    context.response.print "event: #{event}\n"
    context.response.print "data: #{data.to_json}\n\n"
    context.response.flush
  rescue
    # Connection closed
  end

  private def send_error_response(context, code : Int32, message : String)
    context.response.content_type = "application/json"
    context.response.status = HTTP::Status::BAD_REQUEST
    
    error = {
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => {
        "code" => code,
        "message" => message
      }
    }
    
    context.response.print error.to_json
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

  private def handle_health_check(context)
    context.response.content_type = "application/json"
    status = {
      "status" => "healthy",
      "timestamp" => Time.utc.to_rfc3339,
      "server" => @server_info.name,
      "version" => @server_info.version,
      "mcp_version" => "2024-11-05"
    }
    context.response.print status.to_json
  end

  private def handle_documentation(context)
    context.response.content_type = "text/html"
    context.response.print generate_documentation_html
  end

  private def generate_documentation_html
    <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
        <title>SSE MCP Server</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .endpoint { background: #f5f5f5; padding: 10px; margin: 10px 0; border-radius: 5px; }
            code { background: #e0e0e0; padding: 2px 4px; border-radius: 3px; }
        </style>
    </head>
    <body>
        <h1>🚀 SSE MCP Server</h1>
        
        <h2>Endpoints</h2>
        <div class="endpoint">
            <strong>GET /mcp</strong> - SSE connection for real-time events
        </div>
        <div class="endpoint">
            <strong>POST /mcp</strong> - Send MCP JSON-RPC messages
        </div>
        <div class="endpoint">
            <strong>GET /health</strong> - Health check
        </div>
        
        <h2>Available Tools</h2>
        <ul>
            #{@tools.map { |tool| "<li><code>#{tool.name}</code> - #{tool.description}</li>" }.join}
        </ul>
        
        <h2>Usage Examples</h2>
        
        <h3>Connect via SSE (JavaScript)</h3>
        <pre><code>const eventSource = new EventSource('/mcp');
eventSource.onmessage = (event) => {
    console.log('Received:', JSON.parse(event.data));
};</code></pre>
        
        <h3>Send MCP Message (curl)</h3>
        <pre><code>curl -X POST http://localhost:#{@port}/mcp \\
  -H "Content-Type: application/json" \\
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "current_time",
      "arguments": {}
    }
  }'</code></pre>
    </body>
    </html>
    HTML
  end
end

# Start the server
server = SSEMCPServer.new(ARGV.includes?("--port") ? ARGV[ARGV.index("--port").not_nil! + 1].to_i32 : 8080)
server.start
```

## Key SSE Implementation Points

### 1. **Proper Headers**

SSE requires specific HTTP headers:

```crystal
private def set_sse_headers(context)
  context.response.headers["Content-Type"] = "text/event-stream"
  context.response.headers["Cache-Control"] = "no-cache" 
  context.response.headers["Connection"] = "keep-alive"
  context.response.headers["Access-Control-Allow-Origin"] = "*"
end
```

### 2. **Event Format**

SSE events follow a specific format:

```crystal
private def send_sse_event(context, event : String, data)
  context.response.print "event: #{event}\n"
  context.response.print "data: #{data.to_json}\n\n"
  context.response.flush
end
```

### 3. **Connection Management**

Handle connection lifecycle properly:

```crystal
# Send heartbeats to keep connection alive
spawn do
  loop do
    sleep 30
    send_sse_event(context, "heartbeat", {"timestamp" => Time.utc.to_rfc3339})
  end
end
```

### 4. **Dual Endpoints**

Support both SSE (GET) and regular HTTP (POST):

```crystal
case context.request.method
when "GET"
  handle_sse_connection(context)  # Long-lived connection
when "POST" 
  handle_mcp_message(context)     # Regular request/response
end
```

## Client-Side SSE Usage

### JavaScript Example

```javascript
// Connect to SSE endpoint
const eventSource = new EventSource('http://localhost:8080/mcp');

// Handle different event types
eventSource.addEventListener('welcome', (event) => {
    const data = JSON.parse(event.data);
    console.log('Connected:', data.message);
});

eventSource.addEventListener('response', (event) => {
    const response = JSON.parse(event.data);
    console.log('MCP Response:', response);
});

eventSource.addEventListener('error', (event) => {
    console.error('SSE Error:', event);
});

// Send MCP request
function sendMCPRequest(request) {
    fetch('http://localhost:8080/mcp', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(request)
    })
    .then(response => response.json())
    .then(data => console.log('Response:', data))
    .catch(error => console.error('Error:', error));
}

// Example: Initialize connection
sendMCPRequest({
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2024-11-05",
        "capabilities": {},
        "clientInfo": {
            "name": "web-client",
            "version": "1.0.0"
        }
    }
});
```

### Crystal Client Example

```crystal
require "http/client"
require "json"

class SSEMCPClient
  def initialize(@base_url : String)
    @client = HTTP::Client.new(URI.parse(@base_url))
  end

  def connect_sse
    response = @client.get("/mcp")
    
    response.body_io.each_line do |line|
      next unless line.starts_with?("data: ")
      
      data = line[6..]  # Remove "data: " prefix
      event_data = JSON.parse(data)
      handle_sse_event(event_data)
    end
  end

  def send_request(request)
    response = @client.post("/mcp", 
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: request.to_json
    )
    
    JSON.parse(response.body)
  end

  private def handle_sse_event(data)
    case data["type"]?.try(&.as_s?)
    when "welcome"
      puts "Connected: #{data["message"]}"
    when "heartbeat"
      puts "Heartbeat at #{data["timestamp"]}"
    else
      puts "Event: #{data}"
    end
  end
end

# Usage
client = SSEMCPClient.new("http://localhost:8080")

# Start SSE connection in background
spawn { client.connect_sse }

# Send requests
response = client.send_request({
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "initialize",
  "params" => {
    "protocolVersion" => "2024-11-05",
    "capabilities" => {} of String => JSON::Any,
    "clientInfo" => {
      "name" => "crystal-client",
      "version" => "1.0.0"
    }
  }
})

puts response
```

## Advanced SSE Features

### 1. **Event Filtering**

Support different event types:

```crystal
enum SSEEventType
  Welcome
  Response
  Notification
  Error
  Heartbeat
end

private def send_typed_event(context, type : SSEEventType, data)
  context.response.print "event: #{type.to_s.downcase}\n"
  context.response.print "data: #{data.to_json}\n\n"
  context.response.flush
end
```

### 2. **Connection Tracking**

Track active connections:

```crystal
class SSEMCPServer
  def initialize
    @connections = Set(HTTP::Server::Context).new
    @connection_mutex = Mutex.new
  end

  private def track_connection(context)
    @connection_mutex.synchronize do
      @connections << context
    end
    
    # Remove on disconnect
    spawn do
      context.request.body.try(&.read(Bytes.new(0)))
      @connection_mutex.synchronize do
        @connections.delete(context)
      end
    end
  end

  def broadcast_to_all(event : String, data)
    @connection_mutex.synchronize do
      @connections.each do |context|
        send_sse_event(context, event, data) rescue nil
      end
    end
  end
end
```

### 3. **Authentication**

Add authentication for SSE connections:

```crystal
private def handle_sse_connection(context)
  # Check authentication
  auth_header = context.request.headers["Authorization"]?
  unless valid_auth?(auth_header)
    context.response.status = HTTP::Status::UNAUTHORIZED
    return
  end
  
  # Continue with SSE setup...
end

private def valid_auth?(auth_header)
  # Implement your authentication logic
  auth_header == "Bearer your-secret-token"
end
```

## Performance Considerations

### 1. **Connection Limits**

Monitor and limit concurrent connections:

```crystal
MAX_CONNECTIONS = 100

private def handle_sse_connection(context)
  if @connections.size >= MAX_CONNECTIONS
    context.response.status = HTTP::Status::SERVICE_UNAVAILABLE
    context.response.print "Too many connections"
    return
  end
  
  # Continue...
end
```

### 2. **Memory Management**

Clean up closed connections:

```crystal
# Periodic cleanup
spawn do
  loop do
    sleep 60
    cleanup_dead_connections
  end
end

private def cleanup_dead_connections
  @connection_mutex.synchronize do
    @connections.reject! { |context| context.response.closed? }
  end
end
```

### 3. **Buffering**

Handle backpressure properly:

```crystal
private def send_sse_event(context, event, data)
  return if context.response.closed?
  
  begin
    context.response.print "event: #{event}\n"
    context.response.print "data: #{data.to_json}\n\n"
    context.response.flush
  rescue IO::Error
    # Connection closed, remove from tracking
    @connections.delete(context)
  end
end
```

## Testing SSE Servers

### Manual Testing with curl

```bash
# Test SSE connection
curl -N -H "Accept: text/event-stream" http://localhost:8080/mcp

# Test MCP message
curl -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

### Automated Testing

```crystal
require "spec"
require "http/client"

describe SSEMCPServer do
  it "handles SSE connections" do
    server_port = 8081
    server = SSEMCPServer.new(server_port)
    
    spawn { server.start }
    sleep 0.1  # Let server start
    
    client = HTTP::Client.new("localhost", server_port)
    response = client.get("/mcp")
    
    response.headers["Content-Type"].should eq("text/event-stream")
    response.status.should eq(HTTP::Status::OK)
  end
  
  it "handles MCP requests" do
    # Test regular MCP requests...
  end
end
```

## Deployment Tips

### 1. **Reverse Proxy Configuration**

For nginx:

```nginx
location /mcp {
    proxy_pass http://localhost:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;
    proxy_buffering off;
}
```

### 2. **SSL/TLS**

Use HTTPS for production:

```crystal
server = HTTP::Server.new do |context|
  # Your handlers...
end

context = OpenSSL::SSL::Context::Server.new
context.certificate_chain = "path/to/cert.pem"
context.private_key = "path/to/key.pem"

server.bind_tls("0.0.0.0", 8443, context)
server.listen
```

### 3. **Monitoring**

Add health checks and metrics:

```crystal
private def handle_metrics(context)
  metrics = {
    "active_connections" => @connections.size,
    "total_requests" => @request_count,
    "uptime" => Time.utc.to_unix - @start_time,
    "memory_usage" => GC.stats.heap_size
  }
  
  context.response.content_type = "application/json"
  context.response.print metrics.to_json
end
```

## Conclusion

SSE provides an excellent foundation for MCP servers, offering real-time communication while maintaining the simplicity of HTTP. The combination of SSE for events and POST endpoints for requests gives you the best of both worlds: real-time updates and reliable request/response patterns.

This approach is particularly well-suited for:
- AI applications requiring immediate responses
- Web-based MCP clients
- Applications needing connection state awareness
- Scenarios where WebSocket complexity isn't needed

Happy building! 🎉 