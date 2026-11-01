module Shards
  class Error < ::Exception
  end

  class Conflict < Error
    getter package

    def initialize(@package : Package)
      super "Error resolving #{package.name} (#{package.requirements.join(", ")})"
    end
  end

  class LockConflict < Error
    def initialize(message)
      super "Outdated #{LOCK_FILENAME} (#{message}). Please run shards update instead."
    end
  end

  class InvalidLock < Error
    def initialize
      super "Unsupported #{LOCK_FILENAME}. It was likely generated from a newer version of Shards."
    end
  end

  class ParseError < Error
    getter input : String
    getter filename : String
    getter line_number : Int32
    getter column_number : Int32
    property resolver : Resolver?

    def initialize(message, @input, @filename, line_number, column_number)
      @line_number = line_number.to_i
      @column_number = column_number.to_i
      super message
    end

    def to_s(io)
      io << "Error in "
      if resolver = self.resolver
        resolver.name.inspect_unquoted(io)
        io << ':'
      end

      filename = self.filename
      filename = Path[filename].relative_to Dir.current

      io.puts "#{filename}: #{message}"
      io.puts

      lines = input.lines
      from = line_number - 3
      from = 0 if from < 0

      lines[from...line_number].each_with_index do |line, i|
        io.puts "  #{from + i + 1}. #{line}"
      end

      arrow = String.build do |s|
        s << "     "
        (column_number - 1).times { s << ' ' }
        s << '^'
      end
      io.puts arrow.colorize(:green).bold
      io.puts

      io.flush
    end
  end

  class MissingLockChecksum < Error
    def initialize(list_of_unchecksummed_names : Array(String))
      super "#{LOCK_FILENAME} has no checksum for: #{list_of_unchecksummed_names.join(", ")}.\n" \
            "Run `minecart update #{list_of_unchecksummed_names.join(" ")}` to re-resolve these dependencies and record checksums.\n" \
            "Review the change and commit #{LOCK_FILENAME}. " \
            "To install this once without checksums, pass --allow-missing-checksums."
    end
  end

  class InstalledCopyModified < Error
    def initialize(package_name : String, install_path : String)
      super "Checksum verification failed for #{package_name}: the installed copy in #{install_path} no longer matches its locked source.\n" \
            "No dependency scripts were run. Remove #{install_path} and run `minecart install` to reinstall it from the verified source."
    end
  end

  class ChecksumMismatch < Error
    def initialize(package_name : String, expected : String, actual : String)
      super "Checksum verification failed for #{package_name}.\n" \
            "  Expected: #{expected}\n" \
            "  Got:      #{actual}\n" \
            "This may indicate the source has been tampered with or force-pushed.\n" \
            "Run `minecart update #{package_name}` to re-resolve the dependency."
    end
  end

  class PinningError < Error
  end
end
