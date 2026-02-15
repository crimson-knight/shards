module MCProtocol
  # A reference to a resource or resource template definition.
  class ResourceReference
    include JSON::Serializable
    getter type : String = "ref/resource"
    # The URI or URI template of the resource.
    @[JSON::Field(converter: MCProtocol::URIConverter)]
    getter uri : URI

    def initialize(@uri : URI, @type : String = "ref/resource")
    end
  end
end
