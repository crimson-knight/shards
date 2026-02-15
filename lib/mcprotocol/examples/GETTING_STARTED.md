# Getting Started with MCProtocol

This guide will help you get up and running with the MCProtocol Crystal library to build MCP (Model Context Protocol) servers and clients.

## Prerequisites

- Crystal language (>= 1.15.1)
- Basic understanding of JSON-RPC 2.0
- Familiarity with AI/LLM concepts

### Install Crystal

If you don't have Crystal installed:

**macOS:**
```bash
brew install crystal
```

**Ubuntu/Debian:**
```bash
curl -fsSL https://crystal-lang.org/install.sh | bash
```

**Other platforms:** See [Crystal installation guide](https://crystal-lang.org/install/)

## Installation

1. **Create a new Crystal project:**
```bash
crystal init app my_mcp_server
cd my_mcp_server
```

2. **Add MCProtocol to your `shard.yml`:**
```yaml
dependencies:
  mcprotocol:
    github: nobodywasishere/mcprotocol
```

3. **Install dependencies:**
```bash
shards install
```

## Your First MCP Server

Let's create a simple MCP server that provides a greeting tool:

### Step 1: Create the Server

Create `src/greeting_server.cr`:

```crystal
require "mcprotocol"
require "json"

class GreetingServer
  def initialize
    # Define a greeting tool
    @greeting_tool = MCProtocol::Tool.new(
      name: "greet",
      description: "Generate a personalized greeting",
      inputSchema: MCProtocol::ToolInputSchema.new(
        properties: JSON::Any.new({
          "name" => JSON::Any.new({
            "type" => JSON::Any.new("string"),
            "description" => JSON::Any.new("Person's name")
          }),
          "style" => JSON::Any.new({
            "type" => JSON::Any.new("string"),
            "enum" => JSON::Any.new(["formal", "casual", "excited"]),
            "description" => JSON::Any.new("Greeting style")
          })
        }),
        required: ["name"],
        type: "object"
      )
    )
    
    # Define server capabilities
    @capabilities = MCProtocol::ServerCapabilities.new(
      tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: false)
    )
    
    @server_info = MCProtocol::Implementation.new(
      name: "greeting-server",
      version: "1.0.0"
    )
  end
  
  def handle_message(json_data : String) : String
    request = MCProtocol.parse_message(json_data)
    
    response = case request
    when MCProtocol::InitializeRequest
      handle_initialize(request)
    when MCProtocol::ListToolsRequest
      handle_list_tools(request)
    when MCProtocol::CallToolRequest
      handle_call_tool(request)
    else
      create_error(-32601, "Method not found")
    end
    
    response.to_json
  end
  
  private def handle_initialize(request)
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "protocolVersion" => "2024-11-05",
        "capabilities" => JSON.parse(@capabilities.to_json),
        "serverInfo" => JSON.parse(@server_info.to_json)
      }
    }
  end
  
  private def handle_list_tools(request)
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "tools" => [JSON.parse(@greeting_tool.to_json)]
      }
    }
  end
  
  private def handle_call_tool(request)
    return create_error(-32602, "Invalid tool") unless request.params.name == "greet"
    
    args = request.params.arguments
    name = args.try(&.["name"]?.try(&.as_s?)) || "World"
    style = args.try(&.["style"]?.try(&.as_s?)) || "casual"
    
    greeting = case style
    when "formal"
      "Good day, #{name}. It is a pleasure to meet you."
    when "excited"  
      "Hey there, #{name}! So awesome to meet you!!!"
    else
      "Hi #{name}! Nice to meet you."
    end
    
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "content" => [{
          "type" => "text",
          "text" => greeting
        }],
        "isError" => false
      }
    }
  end
  
  private def create_error(code, message)
    {
      "jsonrpc" => "2.0",
      "id" => nil,
      "error" => {
        "code" => code,
        "message" => message
      }
    }
  end
end

# Run the server
server = GreetingServer.new

while line = STDIN.gets
  response = server.handle_message(line.strip)
  puts response
  STDOUT.flush
end
```

### Step 2: Test the Server

Create `test_greeting.cr`:

```crystal
require "./src/greeting_server"

server = GreetingServer.new

# Test initialization
init_request = %{
  {
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
  }
}

puts "=== Testing Initialize ==="
response = server.handle_message(init_request)
puts JSON.pretty_generate(JSON.parse(response))

# Test tool listing
list_request = %{
  {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }
}

puts "\n=== Testing Tool List ==="
response = server.handle_message(list_request)
puts JSON.pretty_generate(JSON.parse(response))

# Test tool call
call_request = %{
  {
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "greet",
      "arguments": {
        "name": "Alice",
        "style": "excited"
      }
    }
  }
}

puts "\n=== Testing Tool Call ==="
response = server.handle_message(call_request)
puts JSON.pretty_generate(JSON.parse(response))
```

Run the test:
```bash
crystal run test_greeting.cr
```

## Building an SSE Server

For real-time applications, you might want to use Server-Sent Events:

```crystal
require "http/server"
require "mcprotocol"

class SSEGreetingServer
  def initialize(@port : Int32 = 8080)
    @greeting_server = GreetingServer.new
    @server = HTTP::Server.new do |context|
      handle_request(context)
    end
  end
  
  def start
    puts "Starting SSE server on http://localhost:#{@port}/mcp"
    @server.bind_tcp(@port)
    @server.listen
  end
  
  private def handle_request(context)
    if context.request.path == "/mcp"
      handle_mcp_connection(context)
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
    
    if body = context.request.body.try(&.gets_to_end)
      response = @greeting_server.handle_message(body)
      context.response.print "data: #{response}\n\n"
      context.response.flush
    end
  end
end

server = SSEGreetingServer.new
server.start
```

## Key Concepts

### 1. **Message Parsing**

All MCP communication uses JSON-RPC 2.0. Parse messages with:

```crystal
request = MCProtocol.parse_message(json_string)
```

### 2. **Protocol Methods**

The library supports all standard MCP methods:

- `initialize` - Start connection
- `tools/list` - List available tools  
- `tools/call` - Execute a tool
- `resources/list` - List available resources
- `resources/read` - Read resource content
- `prompts/list` - List available prompts
- `prompts/get` - Get prompt content

### 3. **Capabilities**

Define what your server supports:

```crystal
capabilities = MCProtocol::ServerCapabilities.new(
  tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: true),
  resources: MCProtocol::ServerCapabilitiesResources.new(subscribe: false),
  logging: JSON::Any.new({} of String => JSON::Any)
)
```

### 4. **Tools**

Tools are functions that AI models can execute:

```crystal
tool = MCProtocol::Tool.new(
  name: "my_tool",
  description: "What this tool does",
  inputSchema: MCProtocol::ToolInputSchema.new(
    properties: JSON::Any.new({
      "param1" => JSON::Any.new({
        "type" => JSON::Any.new("string"),
        "description" => JSON::Any.new("Parameter description")
      })
    }),
    required: ["param1"],
    type: "object"
  )
)
```

### 5. **Resources**

Resources provide context to AI models:

```crystal
resource = MCProtocol::Resource.new(
  uri: URI.parse("file:///path/to/resource"),
  name: "Resource Name",
  description: "What this resource contains",
  mimeType: "text/plain"
)
```

## Error Handling

Always handle errors gracefully:

```crystal
begin
  request = MCProtocol.parse_message(json_data)
  # Process request...
rescue MCProtocol::ParseError => ex
  # Handle parse errors
  create_error_response(-32700, "Parse error: #{ex.message}")
rescue ex
  # Handle other errors  
  create_error_response(-32603, "Internal error: #{ex.message}")
end
```

## Common Patterns

### Request ID Handling

Extract request IDs for proper response correlation:

```crystal
def get_request_id(original_json : String)
  parsed = JSON.parse(original_json)
  parsed["id"]?.try(&.as_i64?) || 1
end
```

### Structured Responses

Use consistent response structures:

```crystal
def create_success_response(id, result)
  {
    "jsonrpc" => "2.0",
    "id" => id,
    "result" => result
  }
end

def create_error_response(id, code, message)
  {
    "jsonrpc" => "2.0", 
    "id" => id,
    "error" => {
      "code" => code,
      "message" => message
    }
  }
end
```

## Testing Your Server

### Unit Testing

```crystal
require "spec"
require "./src/my_server"

describe MyMCPServer do
  it "handles initialization" do
    server = MyMCPServer.new
    request = %{{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}}
    
    response = JSON.parse(server.handle_message(request))
    response["result"]["protocolVersion"].should eq("2024-11-05")
  end
end
```

### Integration Testing

Test with MCP clients:

1. **Claude Desktop** - Add your server to Claude's configuration
2. **Custom Client** - Build a test client using this library
3. **curl** - For HTTP-based servers

## Next Steps

1. **Explore Examples** - Check out the `examples/` directory
2. **Add Resources** - Implement resource listing and reading
3. **Add Prompts** - Create prompt templates for users  
4. **Deploy Remotely** - Use SSE or WebSocket for remote access
5. **Add Authentication** - Implement OAuth 2.0 for secure access

## Debugging Tips

1. **Enable Logging** - Use `puts` to stderr for debugging without interfering with JSON-RPC
2. **Validate JSON** - Always validate JSON structure before processing
3. **Test Message Flow** - Trace the complete request/response cycle
4. **Check IDs** - Ensure request/response IDs match properly

## Common Issues

### Parse Errors
- Check JSON syntax
- Verify required fields are present
- Validate method names

### Type Errors  
- Ensure proper Crystal type annotations
- Handle nil values gracefully
- Use `try` for optional fields

### Protocol Errors
- Follow JSON-RPC 2.0 specification exactly
- Include proper error codes
- Maintain state correctly

## Getting Help

- **Documentation**: [MCP Specification](https://spec.modelcontextprotocol.io/)
- **Examples**: Check the `examples/` directory in this repository
- **Issues**: Report bugs on the GitHub repository
- **Community**: Join the MCP developer community discussions

Happy building! 🚀 