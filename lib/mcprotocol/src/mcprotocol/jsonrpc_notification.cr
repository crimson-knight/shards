module MCProtocol
  # A notification which does not expect a response.
  class JSONRPCNotification
    include JSON::Serializable
    getter jsonrpc : String = "2.0"
    getter method : String
    getter params : JSON::Any?

    def initialize(@method : String, @jsonrpc : String = "2.0", @params : JSON::Any? = nil)
    end
  end
end
