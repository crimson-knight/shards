require "yaml"
require "digest/sha256"

module Shards
  # Tracks postinstall script execution state across installs.
  #
  # Persisted at `lib/.shards.postinstall`, this tracker stores a hash of
  # each shard's postinstall command and whether it has been executed.
  #
  # This enables version-aware postinstall behavior:
  # - First install: run the script, record its hash
  # - Subsequent installs with same script: skip silently
  # - Script changed: warn the user, require explicit `shards run-script`
  class PostinstallInfo
    CURRENT_VERSION = "1.0"

    # Tracks the state of a single shard's postinstall script.
    class Entry
      # SHA-256 hash of the postinstall command string.
      property script_hash : String

      # Whether the script has been executed.
      property has_run : Bool

      def initialize(@script_hash, @has_run = false)
      end
    end

    # Map of shard name to its postinstall entry.
    getter shards : Hash(String, Entry)

    # Absolute path to the `.shards.postinstall` file.
    getter path : String

    def initialize(@path)
      @shards = Hash(String, Entry).new
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
            when "version" then pull.read_scalar
            when "shards"
              pull.each_in_mapping do
                shard_name = pull.read_scalar
                script_hash = ""
                has_run = false

                pull.each_in_mapping do
                  case pull.read_scalar
                  when "script_hash" then script_hash = pull.read_scalar
                  when "has_run"     then has_run = pull.read_scalar == "true"
                  else                    pull.skip
                  end
                end

                @shards[shard_name] = Entry.new(script_hash, has_run)
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
                  yaml.scalar "script_hash"
                  yaml.scalar entry.script_hash
                  yaml.scalar "has_run"
                  yaml.scalar entry.has_run.to_s
                end
              end
            end
          end
        end
      end
    end

    # Computes a SHA-256 hash of a postinstall command string.
    def self.hash_script(command : String) : String
      "sha256:#{Digest::SHA256.hexdigest(command)}"
    end
  end
end
