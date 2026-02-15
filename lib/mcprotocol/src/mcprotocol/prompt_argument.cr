module MCProtocol
  # Describes an argument that a prompt can accept.
  class PromptArgument
    include JSON::Serializable
    # A human-readable description of the argument.
    getter description : String?
    # The name of the argument.
    getter name : String
    # Whether this argument must be provided.
    getter required : Bool?

    def initialize(@name : String, @description : String? = nil, @required : Bool? = nil)
    end
  end
end
