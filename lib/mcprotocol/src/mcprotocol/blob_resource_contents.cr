module MCProtocol
  class BlobResourceContents
    include JSON::Serializable
    # A base64-encoded string representing the binary data of the item.
    getter blob : String
    # The MIME type of this resource, if known.
    getter mimeType : String?
    # The URI of this resource.
    @[JSON::Field(converter: MCProtocol::URIConverter)]
    getter uri : URI

    def initialize(@blob : String, @uri : URI, @mimeType : String? = nil)
    end
  end
end
