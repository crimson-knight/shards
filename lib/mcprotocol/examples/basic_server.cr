require "json"
require "../src/mcprotocol"

# A basic MCP server that demonstrates core functionality
class BasicMCPServer
  def initialize
    # Define available tools
    @tools = [
      MCProtocol::Tool.new(
        name: "calculator",
        description: "Perform basic arithmetic operations",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "operation" => JSON::Any.new({
              "type" => JSON::Any.new("string"),
              "enum" => JSON::Any.new(["add", "subtract", "multiply", "divide"].map { |s| JSON::Any.new(s) }),
              "description" => JSON::Any.new("The arithmetic operation to perform")
            }),
            "a" => JSON::Any.new({
              "type" => JSON::Any.new("number"),
              "description" => JSON::Any.new("First number")
            }),
            "b" => JSON::Any.new({
              "type" => JSON::Any.new("number"), 
              "description" => JSON::Any.new("Second number")
            })
          }),
          required: ["operation", "a", "b"],
          type: "object"
        )
      ),
      MCProtocol::Tool.new(
        name: "greet",
        description: "Generate a personalized greeting",
        inputSchema: MCProtocol::ToolInputSchema.new(
          properties: JSON::Any.new({
            "name" => JSON::Any.new({
              "type" => JSON::Any.new("string"),
              "description" => JSON::Any.new("Name of the person to greet")
            }),
            "language" => JSON::Any.new({
              "type" => JSON::Any.new("string"),
              "enum" => JSON::Any.new(["english", "spanish", "french"].map { |s| JSON::Any.new(s) }),
              "description" => JSON::Any.new("Language for the greeting"),
              "default" => JSON::Any.new("english")
            })
          }),
          required: ["name"],
          type: "object"
        )
      )
    ]

    # Define available resources
    @resources = [
      MCProtocol::Resource.new(
        uri: URI.parse("file:///server/config.json"),
        name: "Server Configuration",
        description: "Current server configuration settings",
        mimeType: "application/json"
      ),
      MCProtocol::Resource.new(
        uri: URI.parse("file:///server/readme.md"),
        name: "Server Documentation", 
        description: "Documentation for this MCP server",
        mimeType: "text/markdown"
      )
    ]

    # Server configuration
    @server_info = MCProtocol::Implementation.new(
      name: "basic-mcp-server",
      version: "1.0.0"
    )

    @capabilities = MCProtocol::ServerCapabilities.new(
      tools: MCProtocol::ServerCapabilitiesTools.new(listChanged: true),
      resources: MCProtocol::ServerCapabilitiesResources.new(
        subscribe: false,
        listChanged: true
      ),
      logging: JSON::Any.new({} of String => JSON::Any)
    )
  end

  def run
    puts "Starting Basic MCP Server"
    puts "Type 'help' for available commands, 'quit' to exit"
    
    loop do
      print "> "
      input = gets
      break unless input
      
      command = input.strip
      break if command == "quit"
      
      case command
      when "help"
        show_help
      when "status"
        show_status
      when "tools"
        list_tools
      when "resources"
        list_resources
      when /^test\s+(.+)/
        test_message($1)
      else
        puts "Unknown command: #{command}"
        puts "Type 'help' for available commands"
      end
    end
    
    puts "Server stopped."
  end

  def handle_message(json_data : String) : String
    begin
      request = MCProtocol.parse_message(json_data)
      response = process_request(request)
      response.to_json
    rescue ex : MCProtocol::ParseError
      create_error_response(-32700, "Parse error: #{ex.message}").to_json
    rescue ex
      create_error_response(-32603, "Internal error: #{ex.message}").to_json
    end
  end

  private def process_request(request : MCProtocol::ClientRequest)
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
    puts "Initialize request from: #{request.params.clientInfo.name} v#{request.params.clientInfo.version}"
    
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

  private def handle_list_tools_request(request : MCProtocol::ListToolsRequest)
    puts "Listing #{@tools.size} available tools"
    
    {
      "jsonrpc" => "2.0", 
      "id" => 1,
      "result" => {
        "tools" => @tools.map { |tool| JSON.parse(tool.to_json) }
      }
    }
  end

  private def handle_call_tool_request(request : MCProtocol::CallToolRequest)
    tool_name = request.params.name
    arguments = request.params.arguments
    
    puts "Calling tool: #{tool_name}"
    
    result = case tool_name
    when "calculator"
      handle_calculator_tool(arguments)
    when "greet"
      handle_greet_tool(arguments)
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

  private def handle_calculator_tool(arguments)
    operation = arguments.try(&.["operation"]?.try(&.as_s?))
    a = arguments.try(&.["a"]?.try(&.as_f?))
    b = arguments.try(&.["b"]?.try(&.as_f?))

    if !operation || !a || !b
      return {
        "content" => [{
          "type" => "text",
          "text" => "Missing required arguments: operation, a, b"
        }],
        "isError" => true
      }
    end

    result = case operation
    when "add"
      a + b
    when "subtract" 
      a - b
    when "multiply"
      a * b
    when "divide"
      if b == 0
        return {
          "content" => [{
            "type" => "text",
            "text" => "Error: Division by zero"
          }],
          "isError" => true
        }
      end
      a / b
    else
      return {
        "content" => [{
          "type" => "text",
          "text" => "Unknown operation: #{operation}"
        }],
        "isError" => true
      }
    end

    {
      "content" => [{
        "type" => "text",
        "text" => "#{a} #{operation} #{b} = #{result}"
      }],
      "isError" => false
    }
  end

  private def handle_greet_tool(arguments)
    name = arguments.try(&.["name"]?.try(&.as_s?))
    language = arguments.try(&.["language"]?.try(&.as_s?)) || "english"

    if !name
      return {
        "content" => [{
          "type" => "text",
          "text" => "Missing required argument: name"
        }],
        "isError" => true
      }
    end

    greeting = case language
    when "spanish"
      "¡Hola, #{name}!"
    when "french"
      "Bonjour, #{name}!"
    else
      "Hello, #{name}!"
    end

    {
      "content" => [{
        "type" => "text",
        "text" => greeting
      }],
      "isError" => false
    }
  end

  private def handle_list_resources_request(request : MCProtocol::ListResourcesRequest)
    puts "Listing #{@resources.size} available resources"
    
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "resources" => @resources.map { |resource| JSON.parse(resource.to_json) }
      }
    }
  end

  private def handle_read_resource_request(request : MCProtocol::ReadResourceRequest)
    uri = request.params.uri.to_s
    puts "Reading resource: #{uri}"

    content = case uri
    when "file:///server/config.json"
      {
        "server" => "basic-mcp-server",
        "version" => "1.0.0",
        "tools" => @tools.size,
        "resources" => @resources.size,
        "started_at" => Time.utc.to_rfc3339
      }.to_json
    when "file:///server/readme.md"
      <<-MD
      # Basic MCP Server

      This is a demonstration MCP server built with Crystal.

      ## Available Tools
      - **calculator**: Perform arithmetic operations
      - **greet**: Generate personalized greetings

      ## Available Resources
      - **config.json**: Server configuration
      - **readme.md**: This documentation

      ## Usage
      Send JSON-RPC 2.0 messages to interact with the server.
      MD
    else
      "Resource not found: #{uri}"
    end

    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {
        "contents" => [{
          "uri" => uri,
          "mimeType" => uri.ends_with?(".json") ? "application/json" : "text/markdown",
          "text" => content
        }]
      }
    }
  end

  private def handle_ping_request(request : MCProtocol::PingRequest)
    puts "Ping received"
    
    {
      "jsonrpc" => "2.0",
      "id" => 1,
      "result" => {} of String => JSON::Any
    }
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

  private def show_help
    puts <<-HELP
    Available commands:
      help       - Show this help message
      status     - Show server status  
      tools      - List available tools
      resources  - List available resources
      test <msg> - Test message parsing with JSON-RPC message
      quit       - Exit the server

    Example test messages:
      test '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
      test '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
      test '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"calculator","arguments":{"operation":"add","a":5,"b":3}}}'
    HELP
  end

  private def show_status
    puts <<-STATUS
    Server Status:
      Name: #{@server_info.name}
      Version: #{@server_info.version}
      Tools: #{@tools.size}
      Resources: #{@resources.size}
      Protocol Version: 2024-11-05
    STATUS
  end

  private def list_tools
    puts "\nAvailable Tools:"
    @tools.each_with_index do |tool, i|
      puts "  #{i + 1}. #{tool.name} - #{tool.description}"
    end
    puts ""
  end

  private def list_resources
    puts "\nAvailable Resources:"
    @resources.each_with_index do |resource, i|
      puts "  #{i + 1}. #{resource.name} (#{resource.uri}) - #{resource.description}"
    end
    puts ""
  end

  private def test_message(message : String)
    puts "\nTesting message: #{message}"
    puts "Response:"
    response = handle_message(message)
    
    # Pretty print the JSON response
    begin
      parsed = JSON.parse(response)
      puts parsed.to_pretty_json
    rescue
      puts response
    end
    puts ""
  end
end

# Run the server
if ARGV.includes?("--help") || ARGV.includes?("-h")
  puts "Basic MCP Server"
  puts ""
  puts "Usage: crystal run basic_server.cr [options]"
  puts ""
  puts "Options:"
  puts "  --help, -h     Show this help message"
  puts ""
  puts "This starts an interactive MCP server for testing."
  exit
end

server = BasicMCPServer.new
server.run 