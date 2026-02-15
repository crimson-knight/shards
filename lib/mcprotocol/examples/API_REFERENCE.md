# MCProtocol API Reference

This document provides a comprehensive reference for all classes and methods in the MCProtocol Crystal library.

## Module: MCProtocol

The main module containing all MCP protocol classes and utilities.

### Constants

#### `VERSION`
```crystal
MCProtocol::VERSION : String
```
The current version of the library (e.g., "0.1.0").

#### `METHOD_TYPES`
```crystal
MCProtocol::METHOD_TYPES : Hash(String, Tuple)
```
Maps MCP method names to their corresponding request, result, and parameter types.

### Methods

#### `parse_message`
```crystal
MCProtocol.parse_message(data : String, method : String? = nil, *, as obj_type = nil) : ClientRequest
```
Parses a JSON-RPC message string into an MCP request object.

**Parameters:**
- `data`: JSON-RPC message string
- `method`: Optional method name (extracted from JSON if nil)
- `obj_type`: Optional target type for parsing

**Returns:** `ClientRequest` union type containing the parsed request

**Raises:** `ParseError` if the message cannot be parsed

## Core Request Types

### ClientRequest
```crystal
alias ClientRequest = InitializeRequest | PingRequest | ListToolsRequest | CallToolRequest | ...
```
Union type representing all possible client requests.

### InitializeRequest
```crystal
class InitializeRequest
  getter method : String         # Always "initialize"
  getter params : InitializeRequestParams
end

class InitializeRequestParams
  getter capabilities : ClientCapabilities
  getter clientInfo : Implementation
  getter protocolVersion : String
end
```
Initial request to establish MCP connection and negotiate capabilities.

### CallToolRequest
```crystal
class CallToolRequest
  getter method : String         # Always "tools/call"
  getter params : CallToolRequestParams
end

class CallToolRequestParams
  getter name : String           # Tool name to execute
  getter arguments : JSON::Any?  # Tool arguments
end
```
Request to execute a specific tool.

### ListToolsRequest
```crystal
class ListToolsRequest
  getter method : String         # Always "tools/list"
  getter params : ListToolsRequestParams
end

class ListToolsRequestParams
  getter cursor : String?        # Pagination cursor
end
```
Request to list available tools.

## Core Response Types

### InitializeResult
```crystal
class InitializeResult
  getter protocolVersion : String
  getter capabilities : ServerCapabilities
  getter serverInfo : Implementation
end
```
Response to initialization request containing server capabilities.

### CallToolResult
```crystal
class CallToolResult
  getter content : Array(TextContent | ImageContent | EmbeddedResource)
  getter isError : Bool?         # Whether the tool call failed
  getter _meta : JSON::Any?      # Optional metadata
end
```
Result of tool execution.

### ListToolsResult
```crystal
class ListToolsResult
  getter tools : Array(Tool)
  getter nextCursor : String?    # Pagination cursor for next page
end
```
List of available tools.

## Capability Classes

### ServerCapabilities
```crystal
class ServerCapabilities
  getter experimental : JSON::Any?
  getter logging : JSON::Any?
  getter prompts : ServerCapabilitiesPrompts?
  getter resources : ServerCapabilitiesResources?
  getter tools : ServerCapabilitiesTools?
end
```
Defines what features the server supports.

### ClientCapabilities
```crystal
class ClientCapabilities
  getter experimental : JSON::Any?
  getter roots : ClientCapabilitiesRoots?
  getter sampling : JSON::Any?
end
```
Defines what features the client supports.

### ServerCapabilitiesTools
```crystal
class ServerCapabilitiesTools
  getter listChanged : Bool?     # Whether server sends list change notifications
end
```

### ServerCapabilitiesResources  
```crystal
class ServerCapabilitiesResources
  getter listChanged : Bool?     # Whether server sends list change notifications
  getter subscribe : Bool?       # Whether server supports resource subscriptions
end
```

## Tool Definition Classes

### Tool
```crystal
class Tool
  getter description : String?   # Human-readable description
  getter inputSchema : ToolInputSchema
  getter name : String          # Unique tool identifier
end
```
Defines a tool that can be executed by the AI model.

### ToolInputSchema
```crystal
class ToolInputSchema
  getter properties : JSON::Any? # JSON Schema properties
  getter required : Array(String)?
  getter type : String          # Always "object"
end
```
JSON Schema defining the tool's input parameters.

## Resource Classes

### Resource
```crystal
class Resource
  getter uri : URI              # Unique resource identifier
  getter name : String?         # Human-readable name
  getter description : String?  # Resource description
  getter mimeType : String?     # Content MIME type
end
```
Defines a resource that provides context to AI models.

### ResourceContents
```crystal
alias ResourceContents = TextResourceContents | BlobResourceContents
```
Union type for different resource content types.

### TextResourceContents
```crystal
class TextResourceContents
  getter uri : URI
  getter mimeType : String?
  getter text : String          # Resource text content
end
```

### BlobResourceContents
```crystal
class BlobResourceContents
  getter uri : URI
  getter mimeType : String?
  getter blob : String          # Base64-encoded binary content
end
```

## Content Classes

### TextContent
```crystal
class TextContent
  getter type : String          # Always "text"
  getter text : String          # Text content
end
```
Represents text content in responses.

### ImageContent
```crystal
class ImageContent
  getter type : String          # Always "image"
  getter data : String          # Base64-encoded image data
  getter mimeType : String      # Image MIME type
end
```
Represents image content in responses.

## Notification Classes

### ClientNotification
```crystal
alias ClientNotification = CancelledNotification | InitializedNotification | ...
```
Union type for all client notifications.

### InitializedNotification
```crystal
class InitializedNotification
  getter method : String        # Always "notifications/initialized"
  getter params : JSON::Any?
end
```
Sent by client after successful initialization.

### ProgressNotification
```crystal
class ProgressNotification
  getter method : String        # Always "notifications/progress"
  getter params : ProgressNotificationParams
end

class ProgressNotificationParams
  getter progressToken : ProgressToken
  getter progress : Float64     # Progress value (0.0 to 1.0)
  getter total : Float64?       # Total progress units
end
```
Reports progress on long-running operations.

## Error Handling

### ParseError
```crystal
class ParseError < Exception
end
```
Raised when JSON-RPC message parsing fails.

### JSONRPCError
```crystal
class JSONRPCError
  getter code : Int64           # Error code
  getter message : String       # Error message
  getter data : JSON::Any?      # Additional error data
end
```
Represents JSON-RPC error responses.

## Utility Classes

### Implementation
```crystal
class Implementation
  getter name : String          # Implementation name
  getter version : String       # Implementation version
end
```
Information about client or server implementation.

### Role
```crystal
enum Role
  User
  Assistant
end
```
Represents different roles in conversations.

### RequestId
```crystal
alias RequestId = String | Int64
```
JSON-RPC request identifier type.

## Usage Examples

### Basic Message Parsing
```crystal
require "mcprotocol"

# Parse an initialize request
json_data = %{
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

request = MCProtocol.parse_message(json_data)
if request.is_a?(MCProtocol::InitializeRequest)
  puts "Client: #{request.params.clientInfo.name}"
  puts "Version: #{request.params.protocolVersion}"
end
```

### Creating Responses
```crystal
# Create server capabilities
capabilities = MCProtocol::ServerCapabilities.new(
  tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: true),
  resources: MCProtocol::ServerCapabilitiesResources.new(subscribe: false)
)

# Create server info
server_info = MCProtocol::Implementation.new(
  name: "my-server",
  version: "1.0.0"
)

# Create initialize result
result = MCProtocol::InitializeResult.new(
  protocolVersion: "2024-11-05",
  capabilities: capabilities,
  serverInfo: server_info
)
```

### Defining Tools
```crystal
# Create a tool definition
tool = MCProtocol::Tool.new(
  name: "calculator",
  description: "Perform arithmetic calculations",
  inputSchema: MCProtocol::ToolInputSchema.new(
    properties: JSON::Any.new({
      "operation" => JSON::Any.new({
        "type" => JSON::Any.new("string"),
        "enum" => JSON::Any.new(["add", "subtract", "multiply", "divide"])
      }),
      "a" => JSON::Any.new({
        "type" => JSON::Any.new("number")
      }),
      "b" => JSON::Any.new({
        "type" => JSON::Any.new("number")
      })
    }),
    required: ["operation", "a", "b"],
    type: "object"
  )
)
```

### Creating Tool Results
```crystal
# Successful tool result
success_result = MCProtocol::CallToolResult.new(
  content: [
    MCProtocol::TextContent.new(
      type: "text",
      text: "Calculation result: 42"
    )
  ],
  isError: false
)

# Error tool result
error_result = MCProtocol::CallToolResult.new(
  content: [
    MCProtocol::TextContent.new(
      type: "text", 
      text: "Division by zero error"
    )
  ],
  isError: true
)
```

### Defining Resources
```crystal
# Create a resource
resource = MCProtocol::Resource.new(
  uri: URI.parse("file:///path/to/document.txt"),
  name: "Important Document",
  description: "Contains important information for the AI",
  mimeType: "text/plain"
)

# Create resource contents
contents = MCProtocol::TextResourceContents.new(
  uri: resource.uri,
  mimeType: "text/plain",
  text: "This is the actual content of the resource..."
)
```

## JSON Schema Integration

The library includes JSON Schema support for tool input validation:

```crystal
# Tool schema with validation
schema = {
  "type" => "object",
  "properties" => {
    "message" => {
      "type" => "string",
      "minLength" => 1,
      "maxLength" => 1000
    },
    "priority" => {
      "type" => "integer",
      "minimum" => 1,
      "maximum" => 5
    }
  },
  "required" => ["message"]
}

tool_schema = MCProtocol::ToolInputSchema.new(
  properties: JSON::Any.new(schema["properties"]),
  required: schema["required"].as(Array(String)),
  type: "object"
)
```

## Best Practices

### Error Handling
Always wrap message parsing in exception handling:

```crystal
begin
  request = MCProtocol.parse_message(json_data)
  # Process request...
rescue MCProtocol::ParseError => ex
  # Handle parse errors
  puts "Parse error: #{ex.message}"
rescue ex
  # Handle other errors
  puts "Unexpected error: #{ex.message}"
end
```

### Type Safety
Use type checking when handling union types:

```crystal
case request
when MCProtocol::InitializeRequest
  # Handle initialization
when MCProtocol::CallToolRequest
  # Handle tool calls
when MCProtocol::ListToolsRequest
  # Handle tool listing
else
  # Handle unknown request types
end
```

### JSON Serialization
All classes support JSON serialization:

```crystal
tool = MCProtocol::Tool.new(...)
json_string = tool.to_json

# Parse back
parsed_tool = MCProtocol::Tool.from_json(json_string)
```

## Schema Validation

The library is automatically generated from the official MCP JSON schema, ensuring:

- **Type Safety**: All fields are properly typed
- **Completeness**: All protocol features are supported  
- **Accuracy**: Matches the official specification exactly
- **Future Compatibility**: Easy updates when the schema changes

## Thread Safety

The library classes are immutable by default, making them thread-safe for reading. However, shared mutable state (like connection tracking) should be protected with mutexes:

```crystal
@connections = Set(Connection).new
@mutex = Mutex.new

def add_connection(connection)
  @mutex.synchronize do
    @connections << connection
  end
end
```

This API reference provides comprehensive coverage of the MCProtocol library. For practical examples, see the `examples/` directory and the getting started guide. 