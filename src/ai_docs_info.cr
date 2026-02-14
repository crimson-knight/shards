require "yaml"
require "digest/sha256"

module Shards
  # Tracks installed AI documentation files and their checksums.
  #
  # Persisted at `.claude/.ai-docs-info.yml`, this tracker enables
  # conflict detection during updates by storing two checksums per file:
  #
  # - `upstream_checksum`: the checksum of the file as shipped by the shard
  # - `installed_checksum`: the checksum of the file as it exists on disk
  #
  # When both match, the file is unmodified and safe to auto-update.
  # When they differ, the user has customized the file and it should
  # not be overwritten.
  class AIDocsInfo
    CURRENT_VERSION = "1.0"

    # Represents a single tracked file with dual checksums.
    class FileEntry
      property upstream_checksum : String
      property installed_checksum : String

      def initialize(@upstream_checksum, @installed_checksum)
      end

      # Returns `true` if the installed file differs from the upstream version,
      # indicating the user has made local modifications.
      def user_modified?
        upstream_checksum != installed_checksum
      end
    end

    # Tracks all AI doc files installed from a single shard.
    class ShardEntry
      property version : String
      property files : Hash(String, FileEntry)

      def initialize(@version, @files = Hash(String, FileEntry).new)
      end
    end

    # Map of shard name to its tracked entry.
    getter shards : Hash(String, ShardEntry)

    # Absolute path to the `.ai-docs-info.yml` file.
    getter path : String

    def initialize(@path)
      @shards = Hash(String, ShardEntry).new
      load if File.exists?(@path)
    end

    # Loads tracker state from the YAML file at `#path`.
    def load
      content = File.read(@path)
      pull = YAML::PullParser.new(content)
      pull.read_stream do
        pull.read_document do
          pull.each_in_mapping do
            case pull.read_scalar
            when "version" then pull.read_scalar # skip, already known
            when "shards"
              pull.each_in_mapping do
                shard_name = pull.read_scalar
                version = ""
                files = Hash(String, FileEntry).new

                pull.each_in_mapping do
                  case pull.read_scalar
                  when "version" then version = pull.read_scalar
                  when "files"
                    pull.each_in_mapping do
                      file_path = pull.read_scalar
                      upstream = ""
                      installed = ""
                      pull.each_in_mapping do
                        case pull.read_scalar
                        when "upstream_checksum"  then upstream = pull.read_scalar
                        when "installed_checksum" then installed = pull.read_scalar
                        else                           pull.skip
                        end
                      end
                      files[file_path] = FileEntry.new(upstream, installed)
                    end
                  else pull.skip
                  end
                end

                @shards[shard_name] = ShardEntry.new(version, files)
              end
            else pull.skip
            end
          end
        end
      end
    ensure
      pull.try &.close
    end

    # Persists the current tracker state to the YAML file at `#path`.
    def save
      Dir.mkdir_p(File.dirname(@path))

      File.open(@path, "w") do |file|
        YAML.build(file) do |yaml|
          yaml.mapping do
            yaml.scalar "version"
            yaml.scalar CURRENT_VERSION

            yaml.scalar "shards"
            yaml.mapping do
              @shards.each do |name, entry|
                yaml.scalar name
                yaml.mapping do
                  yaml.scalar "version"
                  yaml.scalar entry.version

                  yaml.scalar "files"
                  yaml.mapping do
                    entry.files.each do |path, file_entry|
                      yaml.scalar path
                      yaml.mapping do
                        yaml.scalar "upstream_checksum"
                        yaml.scalar file_entry.upstream_checksum
                        yaml.scalar "installed_checksum"
                        yaml.scalar file_entry.installed_checksum
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    # Computes a SHA-256 checksum for the given string content.
    def self.checksum(content : String) : String
      "sha256:#{Digest::SHA256.hexdigest(content)}"
    end

    # Computes a SHA-256 checksum for the file at the given path.
    def self.checksum_file(path : String) : String
      checksum(File.read(path))
    end
  end
end
