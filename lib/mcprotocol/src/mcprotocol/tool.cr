module MCProtocol
  # A JSON Schema object defining the expected parameters for the tool.
  class ToolInputSchema
    include JSON::Serializable
    getter properties : JSON::Any?
    getter required : Array(String)?
    getter type : String = "object"

    def initialize(@properties : JSON::Any? = nil, @required : Array(String)? = nil, @type : String = "object")
    end
  end

  # Definition for a tool the client can call.
  class Tool
    include JSON::Serializable
    # A human-readable description of the tool.
    getter description : String?
    # A JSON Schema object defining the expected parameters for the tool.
    getter inputSchema : ToolInputSchema
    # The name of the tool.
    getter name : String

    def initialize(@inputSchema : ToolInputSchema, @name : String, @description : String? = nil)
    end
  end
end
