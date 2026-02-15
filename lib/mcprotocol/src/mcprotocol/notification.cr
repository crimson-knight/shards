module MCProtocol
  class Notification
    include JSON::Serializable
    getter method : String
    getter params : JSON::Any?

    def initialize(@method : String, @params : JSON::Any? = nil)
    end
  end
end
