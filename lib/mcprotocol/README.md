# MCProtocol

A Crystal implementation of Anthropic's [Model Context Protocol (MCP)](https://modelcontextprotocol.io/), providing type-safe bindings for building MCP servers and clients.

## What is the Model Context Protocol?

The Model Context Protocol (MCP) is an open standard that enables AI applications to securely connect to various data sources and tools. Think of MCP as a "USB-C port for AI" - it provides a standardized way to connect AI models to:

- **Resources**: Files, databases, APIs, and other data sources
- **Tools**: Functions that AI models can execute  
- **Prompts**: Templated interactions and workflows

## Features

- **Type-Safe**: Auto-generated Crystal classes from the official MCP JSON schema
- **Complete Protocol Support**: All MCP message types, capabilities, and features
- **Server & Client Support**: Build both MCP servers and clients
- **JSON-RPC 2.0**: Full compliance with the underlying JSON-RPC protocol
- **SSE Compatible**: Ready for Server-Sent Events implementations
- **Extensible**: Easy to extend with custom capabilities

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     mcprotocol:
       github: nobodywasishere/mcprotocol
   ```

2. Run `shards install`

## Quick Start

### Basic Usage

```crystal
require "mcprotocol"

# Parse an MCP message
message_data = %{{"method": "initialize", "params": {...}}}
request = MCProtocol.parse_message(message_data)

# Create MCP objects
capabilities = MCProtocol::ServerCapabilities.new(
  tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: true),
  resources: MCProtocol::ServerCapabilitiesResources.new(subscribe: true)
)

# Handle different message types
case request
when MCProtocol::InitializeRequest
  # Handle initialization
when MCProtocol::CallToolRequest  
  # Handle tool calls
end
```

### Building an MCP Server

```crystal
require "mcprotocol"
require "json"

class SimpleMCPServer
  def initialize
    @tools = [
      MCProtocol::Tool.new(
        name: "echo",
        description: "Echo back the input",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "message" => JSON::Any.new({
              "type" => JSON::Any.new("string"),
              "description" => JSON::Any.new("Message to echo")
            })
          })
        )
      )
    ]
  end

  def handle_initialize(request : MCProtocol::InitializeRequest)
    # Return server capabilities
    MCProtocol::InitializeResult.new(
      protocolVersion: "2024-11-05",
      capabilities: MCProtocol::ServerCapabilities.new(
        tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: true)
      ),
      serverInfo: MCProtocol::Implementation.new(
        name: "simple-server",
        version: "1.0.0"
      )
    )
  end

  def handle_list_tools(request : MCProtocol::ListToolsRequest)
    MCProtocol::ListToolsResult.new(tools: @tools)
  end

  def handle_call_tool(request : MCProtocol::CallToolRequest)
    case request.params.name
    when "echo"
      message = request.params.arguments.try(&.["message"]?)
      MCProtocol::CallToolResult.new(
        content: [
          MCProtocol::TextContent.new(
            type: "text",
            text: "Echo: #{message}"
          )
        ]
      )
    else
      raise "Unknown tool: #{request.params.name}"
    end
  end
end
```

### Server-Sent Events (SSE) Implementation

For SSE-based MCP servers, you can use Crystal's HTTP server:

```crystal
require "http/server"
require "mcprotocol"

class SSEMCPServer
  def initialize(@port : Int32 = 8080)
    @server = HTTP::Server.new do |context|
      if context.request.path == "/mcp"
        handle_mcp_connection(context)
      else
        context.response.status = HTTP::Status::NOT_FOUND
        context.response.print "Not Found"
      end
    end
  end

  def start
    puts "Starting MCP SSE server on port #{@port}"
    @server.bind_tcp(@port)
    @server.listen
  end

  private def handle_mcp_connection(context)
    # Set SSE headers
    context.response.headers["Content-Type"] = "text/event-stream"
    context.response.headers["Cache-Control"] = "no-cache"
    context.response.headers["Connection"] = "keep-alive"
    context.response.headers["Access-Control-Allow-Origin"] = "*"

    # Handle the MCP session
    loop do
      begin
        # Read JSON-RPC messages from the request body or WebSocket
        # Parse using MCProtocol.parse_message
        # Send responses as SSE events
        
        break if context.response.closed?
      rescue ex
        puts "Connection error: #{ex.message}"
        break
      end
    end
  end

  private def send_sse_message(context, data : String, event : String? = nil)
    if event
      context.response.print "event: #{event}\n"
    end
    context.response.print "data: #{data}\n\n"
    context.response.flush
  end
end

# Start the server
server = SSEMCPServer.new
server.start
```

## Protocol Messages

The library includes all MCP protocol message types:

### Requests (Client → Server)
- `InitializeRequest` - Begin connection and capability negotiation
- `ListToolsRequest` - Get available tools
- `CallToolRequest` - Execute a tool
- `ListResourcesRequest` - Get available resources  
- `ReadResourceRequest` - Read resource content
- `ListPromptsRequest` - Get available prompts
- `GetPromptRequest` - Get prompt content

### Responses (Server → Client)  
- `InitializeResult` - Server capabilities and info
- `ListToolsResult` - Available tools
- `CallToolResult` - Tool execution result
- `ListResourcesResult` - Available resources
- `ReadResourceResult` - Resource content
- `ListPromptsResult` - Available prompts
- `GetPromptResult` - Prompt content

### Notifications (Bidirectional)
- `InitializedNotification` - Client ready for requests
- `ProgressNotification` - Progress updates
- `LoggingMessageNotification` - Log messages
- `CancelledNotification` - Request cancellation

## Available Message Types

The library supports all MCP protocol methods through the `METHOD_TYPES` constant:

```crystal
MCProtocol::METHOD_TYPES.keys
# => ["initialize", "ping", "resources/list", "tools/call", ...]
```

## Architecture

```
┌─────────────────┐    JSON-RPC 2.0     ┌─────────────────┐
│   MCP Client    │ ◄─────────────────► │   MCP Server    │
│ (AI Application)│                     │ (Your Service)  │
└─────────────────┘                     └─────────────────┘
        │                                       │
        ▼                                       ▼
┌─────────────────┐                     ┌─────────────────┐
│ MCProtocol      │                     │ MCProtocol      │
│ Crystal Lib     │                     │ Crystal Lib     │
└─────────────────┘                     └─────────────────┘
```

## Key Classes

### Core Protocol
- `MCProtocol::ClientRequest` - Union type for all client requests
- `MCProtocol::ServerResult` - Union type for all server responses  
- `MCProtocol::ClientNotification` - Union type for client notifications
- `MCProtocol::ServerNotification` - Union type for server notifications

### Capabilities
- `MCProtocol::ClientCapabilities` - What the client supports
- `MCProtocol::ServerCapabilities` - What the server provides

### Data Types
- `MCProtocol::Tool` - Tool definitions
- `MCProtocol::Resource` - Resource definitions  
- `MCProtocol::Prompt` - Prompt templates
- `MCProtocol::TextContent` - Text content
- `MCProtocol::ImageContent` - Image content

## Error Handling

```crystal
begin
  request = MCProtocol.parse_message(invalid_json)
rescue MCProtocol::ParseError => ex
  puts "Failed to parse MCP message: #{ex.message}"
end
```

## Security Considerations

When implementing MCP servers:

1. **Validate all inputs** - Never trust client-provided data
2. **Implement proper authentication** - Use OAuth 2.0 for remote servers
3. **Limit resource access** - Only expose necessary data and tools
4. **Log security events** - Monitor for suspicious activity
5. **Handle errors gracefully** - Don't leak sensitive information

## Examples

See the `examples/` directory for complete working examples:

- **Basic Server**: Simple tool and resource server
- **SSE Server**: Server-Sent Events implementation  
- **File System Server**: Access local files and directories
- **Database Server**: Query databases through MCP

## Development

To regenerate the protocol classes from the schema:

```bash
make generate
```

This runs the code generator using the official MCP JSON schema.

## Testing

```bash
crystal spec
```

## Contributing

1. Fork it (<https://github.com/nobodywasishere/mcprotocol/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Related Projects

- [Official MCP Specification](https://spec.modelcontextprotocol.io/)
- [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk)  
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
- [Claude Desktop MCP Integration](https://docs.anthropic.com/en/docs/agents-and-tools/mcp)

## Contributors

- [Margret Riegert](https://github.com/nobodywasishere) - creator and maintainer
