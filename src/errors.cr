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
    def initialize(list_of_unchecksummed_names : Array(String), list_of_legacy_checksum_names : Array(String))
      message = String.build do |io|
        unless list_of_unchecksummed_names.empty?
          io << LOCK_FILENAME << " has no checksum for: " << list_of_unchecksummed_names.join(", ") << ".\n"
          io << "Run `minecart update " << list_of_unchecksummed_names.join(" ") << "` to re-resolve these dependencies and record sha256 checksums.\n"
        end
        unless list_of_legacy_checksum_names.empty?
          io << LOCK_FILENAME << " has only a legacy git-tree (SHA-1) checksum for: " << list_of_legacy_checksum_names.join(", ") << "; --frozen requires sha256.\n"
          io << "Run `minecart lock --update-checksums` to verify each git-tree id and record sha256 checksums.\n"
        end
        io << "Review the change and commit " << LOCK_FILENAME << ". "
        io << "To install this once without sha256 checksums, pass --allow-missing-checksums."
      end
      super message
    end
  end

  # A shard ships a symlink to a directory outside itself. Its target is not
  # part of the shard's source, so no checksum could cover it.
  class UnsafeSymlink < Error
    def initialize(relative_path : String, target : String)
      super "#{relative_path} links to #{target}, a directory outside the shard. " \
            "Its contents cannot be covered by the lock checksum, so the shard is refused."
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
