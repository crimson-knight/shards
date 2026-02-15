require "json"
require "../src/mcprotocol"

# A minimal MCP server that echoes messages - perfect for testing
class EchoMCPServer
  def initialize
    @tool = MCProtocol::Tool.new(
      name: "echo",
      description: "Echo back any message with optional formatting",
      inputSchema: MCProtocol::ToolInputSchema.new(
        properties: JSON::Any.new({
          "message" => JSON::Any.new({
            "type" => JSON::Any.new("string"),
            "description" => JSON::Any.new("The message to echo back")
          }),
          "uppercase" => JSON::Any.new({
            "type" => JSON::Any.new("boolean"),
            "description" => JSON::Any.new("Whether to convert message to uppercase"),
            "default" => JSON::Any.new(false)
          }),
          "prefix" => JSON::Any.new({
            "type" => JSON::Any.new("string"),
            "description" => JSON::Any.new("Optional prefix to add to the message"),
            "default" => JSON::Any.new("Echo: ")
          })
        }),
        required: ["message"],
        type: "object"
      )
    )

    @server_info = MCProtocol::Implementation.new(
      name: "echo-mcp-server",
      version: "1.0.0"
    )

    @capabilities = MCProtocol::ServerCapabilities.new(
      tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: false)
    )
  end

  def run_stdio
    puts "Echo MCP Server started (stdio mode)"
    puts "Send JSON-RPC messages via stdin"
    
    while line = STDIN.gets
      line = line.strip
      next if line.empty?
      
      begin
        response = handle_message(line)
        puts response
        STDOUT.flush
      rescue ex
        error = create_error_response(-32603, ex.message || "Unknown error")
        puts error.to_json
        STDOUT.flush
      end
    end
  end

  def handle_message(json_data : String) : String
    begin
      # Parse the incoming JSON-RPC message
      request = MCProtocol.parse_message(json_data)
      
      # Process the request and generate response
      response = case request
      when MCProtocol::InitializeRequest
        handle_initialize(request)
      when MCProtocol::ListToolsRequest
        handle_list_tools(request)
      when MCProtocol::CallToolRequest
        handle_call_tool(request)
      when MCProtocol::PingRequest
        handle_ping(request)
      else
        create_error_response(-32601, "Method not found: #{request.class}")
      end
      
      response.to_json
    rescue ex : MCProtocol::ParseError
      create_error_response(-32700, "Parse error: #{ex.message || "Unknown parse error"}").to_json
    rescue ex : JSON::ParseException
      create_error_response(-32700, "Invalid JSON: #{ex.message || "Unknown JSON error"}").to_json
    rescue ex
      create_error_response(-32603, "Internal error: #{ex.message || "Unknown internal error"}").to_json
    end
  end

  private def handle_initialize(request : MCProtocol::InitializeRequest)
    client_info = request.params.clientInfo
    puts "STDERR: Initialize from #{client_info.name} v#{client_info.version}" if STDERR
    
    {
      "jsonrpc" => "2.0",
      "id" => get_request_id(request),
      "result" => {
        "protocolVersion" => request.params.protocolVersion,
        "capabilities" => JSON.parse(@capabilities.to_json),
        "serverInfo" => JSON.parse(@server_info.to_json)
      }
    }
  end

  private def handle_list_tools(request : MCProtocol::ListToolsRequest)
    puts "STDERR: Listing tools" if STDERR
    
    {
      "jsonrpc" => "2.0",
      "id" => get_request_id(request),
      "result" => {
        "tools" => [JSON.parse(@tool.to_json)]
      }
    }
  end

  private def handle_call_tool(request : MCProtocol::CallToolRequest)
    tool_name = request.params.name
    arguments = request.params.arguments
    
    puts "STDERR: Calling tool: #{tool_name}" if STDERR

    if tool_name != "echo"
      return {
        "jsonrpc" => "2.0",
        "id" => get_request_id(request),
        "result" => {
          "content" => [{
            "type" => "text",
            "text" => "Unknown tool: #{tool_name}"
          }],
          "isError" => true
        }
      }
    end

    # Extract arguments
    message = arguments.try(&.["message"]?.try(&.as_s?)) || ""
    uppercase = arguments.try(&.["uppercase"]?.try(&.as_bool?)) || false
    prefix = arguments.try(&.["prefix"]?.try(&.as_s?)) || "Echo: "

    # Process the message
    result_text = prefix + message
    if uppercase
      result_text = result_text.upcase
    end

    {
      "jsonrpc" => "2.0",
      "id" => get_request_id(request),
      "result" => {
        "content" => [{
          "type" => "text",
          "text" => result_text
        }],
        "isError" => false
      }
    }
  end

  private def handle_ping(request : MCProtocol::PingRequest)
    puts "STDERR: Ping received" if STDERR
    
    {
      "jsonrpc" => "2.0",
      "id" => get_request_id(request),
      "result" => {} of String => JSON::Any
    }
  end

  private def get_request_id(request)
    # Try to extract ID from the request if it's a JSON object
    1 # Default ID for now - in real implementation, extract from original JSON
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

  def test_interactively
    puts "Echo MCP Server - Interactive Mode"
    puts "Enter JSON-RPC messages (or 'quit' to exit):"
    puts ""
    puts "Example messages:"
    puts %{  {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}}
    puts %{  {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}}
    puts %{  {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"message":"Hello World!","uppercase":true}}}}
    puts ""

    loop do
      print "> "
      input = gets
      break unless input
      
      input = input.strip
      break if input == "quit"
      next if input.empty?

      begin
        response = handle_message(input)
        puts "Response:"
        
        # Pretty print the JSON response
        begin
          parsed = JSON.parse(response)
          puts parsed.to_pretty_json
        rescue
          puts response
        end
      rescue ex
        puts "Error: #{ex.message || "Unknown error"}"
      end
      
      puts ""
    end
    
    puts "Goodbye!"
  end
end

# Determine run mode based on arguments
if ARGV.includes?("--help") || ARGV.includes?("-h")
  puts "Echo MCP Server"
  puts ""
  puts "Usage:"
  puts "  crystal run echo_server.cr [options]"
  puts ""
  puts "Options:"
  puts "  --stdio        Run in stdio mode (default)"
  puts "  --interactive  Run in interactive test mode"
  puts "  --help, -h     Show this help"
  puts ""
  puts "Examples:"
  puts "  crystal run echo_server.cr --stdio"
  puts "  crystal run echo_server.cr --interactive"
  puts ""
  puts "For stdio mode, send JSON-RPC messages via stdin."
  puts "For interactive mode, enter messages interactively."
  exit
end

server = EchoMCPServer.new

if ARGV.includes?("--interactive")
  server.test_interactively
else
  # Default to stdio mode
  server.run_stdio
end 