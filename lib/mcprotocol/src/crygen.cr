module CGE
  enum PropVisibility
    Getter
  end
end

module CGT
  abstract class Node
    property comment : String?

    def add_comment(comment : String)
      @comment = comment
    end

    protected def render_comment(io : IO, indent : Int32)
      return unless comment = @comment

      comment.each_line do |line|
        io << "  " * indent
        io << "#"
        stripped = line.rstrip
        unless stripped.empty?
          io << " "
          io << stripped
        end
        io << '\n'
      end
    end

    abstract def render(io : IO, indent : Int32)
  end

  class Module
    def initialize(@name : String)
      @objects = [] of Node
    end

    def add_object(object : Node)
      @objects << object
    end

    def generate : String
      String.build do |io|
        io << "module "
        io << @name
        io << '\n'

        @objects.each_with_index do |object, index|
          object.render(io, 1)
          io << '\n' unless index == @objects.size - 1
        end

        io << "end\n"
      end
    end
  end

  class Alias < Node
    def initialize(@name : String, @types : Array(String))
    end

    def render(io : IO, indent : Int32)
      render_comment(io, indent)
      io << "  " * indent
      io << "alias "
      io << @name
      io << " = "
      io << @types.join(" | ")
      io << '\n'
    end
  end

  class Enum < Node
    def initialize(@name : String)
      @constants = [] of String
    end

    def add_constant(name : String)
      @constants << name
    end

    def render(io : IO, indent : Int32)
      render_comment(io, indent)
      io << "  " * indent
      io << "enum "
      io << @name
      io << '\n'

      @constants.each do |constant|
        io << "  " * (indent + 1)
        io << constant
        io << '\n'
      end

      io << "  " * indent
      io << "end\n"
    end
  end

  class Method
    getter args

    def initialize(@name : String, @return_type : String)
      @args = [] of NamedTuple(name: String, type: String, default: String?)
    end

    def add_arg(name : String, type : String, default : String? = nil)
      @args << {name: name, type: type, default: default}
    end

    def render(io : IO, indent : Int32)
      io << "  " * indent
      io << "def "
      io << @name
      io << "("
      io << @args.map { |arg|
        value = "#{arg[:name]} : #{arg[:type]}"
        default = arg[:default]
        default ? "#{value} = #{default}" : value
      }.join(", ")
      io << ")\n"
      io << "  " * indent
      io << "end\n"
    end
  end

  class Class < Node
    getter properties

    def initialize(@name : String)
      @includes = [] of String
      @properties = [] of NamedTuple(
        visibility: CGE::PropVisibility,
        name: String,
        type: String?,
        value: String?,
        comment: String?
      )
      @methods = [] of Method
    end

    def add_include(name : String)
      @includes << name
    end

    def add_property(visibility : CGE::PropVisibility, *, name : String, type : String?, value : String?, comment : String?)
      @properties << {
        visibility: visibility,
        name: name,
        type: type,
        value: value,
        comment: comment,
      }
    end

    def add_method(method : Method)
      @methods << method
    end

    def render(io : IO, indent : Int32)
      render_comment(io, indent)
      io << "  " * indent
      io << "class "
      io << @name
      io << '\n'

      @includes.each do |include_name|
        io << "  " * (indent + 1)
        io << "include "
        io << include_name
        io << '\n'
      end

      @properties.each do |property|
        render_property(io, property, indent + 1)
      end

      io << '\n' if @properties.any? && @methods.any?

      @methods.each_with_index do |method, index|
        method.render(io, indent + 1)
        io << '\n' unless index == @methods.size - 1
      end

      io << "  " * indent
      io << "end\n"
    end

    private def render_property(io : IO, property, indent : Int32)
      if comment = property[:comment]
        comment.each_line do |line|
          io << "  " * indent
          io << "#"
          stripped = line.rstrip
          unless stripped.empty?
            io << " "
            io << stripped
          end
          io << '\n'
        end
      end

      if uri_property?(property[:type])
        io << "  " * indent
        io << "@[JSON::Field(converter: MCProtocol::URIConverter)]\n"
      end

      io << "  " * indent
      case property[:visibility]
      in .getter?
        io << "getter "
      end
      io << property[:name]

      if type = property[:type]
        io << " : "
        io << type
      end

      if value = property[:value]
        io << " = "
        io << value
      end

      io << '\n'
    end

    private def uri_property?(type : String?) : Bool
      return false unless type
      normalized = type.ends_with?('?') ? type[0...-1] : type
      normalized == "URI"
    end
  end
end
