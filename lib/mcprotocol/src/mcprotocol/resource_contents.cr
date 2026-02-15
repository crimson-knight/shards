module MCProtocol
  # The contents of a specific resource or sub-resource.
  class ResourceContents
    include JSON::Serializable
    # The MIME type of this resource, if known.
    getter mimeType : String?
    # The URI of this resource.
    @[JSON::Field(converter: MCProtocol::URIConverter)]
    getter uri : URI

    def initialize(@uri : URI, @mimeType : String? = nil)
    end
  end
end
