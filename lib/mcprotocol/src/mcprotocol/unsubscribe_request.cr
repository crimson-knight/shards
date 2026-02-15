module MCProtocol
  class UnsubscribeRequestParams
    include JSON::Serializable
    # The URI of the resource to unsubscribe from.
    @[JSON::Field(converter: MCProtocol::URIConverter)]
    getter uri : URI

    def initialize(@uri : URI)
    end
  end

  # Sent from the client to request cancellation of resources/updated notifications from the server. This should follow a previous resources/subscribe request.
  class UnsubscribeRequest
    include JSON::Serializable
    getter method : String = "resources/unsubscribe"
    getter params : UnsubscribeRequestParams

    def initialize(@params : UnsubscribeRequestParams)
    end
  end
end
