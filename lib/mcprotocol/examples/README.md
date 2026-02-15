# MCProtocol Examples

This directory contains complete working examples of MCP servers and clients built with the MCProtocol Crystal library.

## Examples

### 1. Basic Server (`basic_server.cr`)
A simple MCP server that demonstrates:
- Tool registration and execution
- Resource listing and reading
- Basic JSON-RPC message handling

**Run:**
```bash
crystal run examples/basic_server.cr
```

### 2. SSE Server (`sse_server.cr`)
A Server-Sent Events (SSE) based MCP server that:
- Handles HTTP connections
- Implements SSE for real-time communication
- Manages MCP protocol over HTTP

**Run:**
```bash
crystal run examples/sse_server.cr
```

**Test:**
```bash
curl -N -H "Accept: text/event-stream" http://localhost:8080/mcp
```

### 3. File System Server (`filesystem_server.cr`)
An MCP server that provides file system access:
- Lists files and directories as resources
- Provides file reading tools
- Demonstrates secure path handling

**Run:**
```bash
crystal run examples/filesystem_server.cr
```

### 4. Echo Server (`echo_server.cr`)
A minimal MCP server for testing:
- Single echo tool
- Simple message parsing
- Basic error handling

**Run:**
```bash
crystal run examples/echo_server.cr
```

### 5. Client Example (`mcp_client.cr`)
An MCP client that demonstrates:
- Connecting to MCP servers
- Sending requests and handling responses
- Tool invocation and resource reading

**Run:**
```bash
crystal run examples/mcp_client.cr
```

## Prerequisites

Make sure you have Crystal installed and the mcprotocol dependency available:

```bash
crystal version
shards install
```

## Testing Examples

You can test the servers using:

1. **Manual Testing**: Use curl or a WebSocket client
2. **MCP Client**: Use the provided client example
3. **Claude Desktop**: Configure the server for use with Claude

## Security Notes

These examples are for demonstration purposes. For production use:

- Implement proper authentication
- Validate all inputs
- Add rate limiting
- Use HTTPS for remote servers
- Follow security best practices 