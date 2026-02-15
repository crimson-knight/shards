require "yaml"
require "./ai_docs_info"

module Shards
  # Tracks the installed assistant configuration state.
  #
  # Persisted at `.claude/.assistant-config.yml`, this tracker stores
  # which version is installed, which components are enabled, and
  # per-file checksums for detecting user modifications during upgrades.
  class AssistantConfigInfo
    CURRENT_VERSION = "1.0"
    FILENAME        = ".assistant-config.yml"

    getter path : String
    property installed_version : String
    property assistant : String
    property installed_at : String
    property components : Hash(String, Bool)
    property files : Hash(String, String)

    def initialize(@path : String)
      @installed_version = ""
      @assistant = "claude-code"
      @installed_at = ""
      @components = {} of String => Bool
      @files = {} of String => String
      load if File.exists?(@path)
    end

    def load
      content = File.read(@path)
      pull = YAML::PullParser.new(content)
      pull.read_stream do
        pull.read_document do
          pull.each_in_mapping do
            case pull.read_scalar
            when "version"           then pull.read_scalar # schema version, skip
            when "installed_version" then @installed_version = pull.read_scalar
            when "assistant"         then @assistant = pull.read_scalar
            when "installed_at"      then @installed_at = pull.read_scalar
            when "components"
              pull.each_in_mapping do
                name = pull.read_scalar
                @components[name] = pull.read_scalar == "true"
              end
            when "files"
              pull.each_in_mapping do
                file_path = pull.read_scalar
                checksum = ""
                pull.each_in_mapping do
                  case pull.read_scalar
                  when "checksum" then checksum = pull.read_scalar
                  else                 pull.skip
                  end
                end
                @files[file_path] = checksum
              end
            else pull.skip
            end
          end
        end
      end
    ensure
      pull.try &.close
    end

    def save
      Dir.mkdir_p(File.dirname(@path))

      File.open(@path, "w") do |file|
        YAML.build(file) do |yaml|
          yaml.mapping do
            yaml.scalar "version"
            yaml.scalar CURRENT_VERSION

            yaml.scalar "installed_version"
            yaml.scalar @installed_version

            yaml.scalar "assistant"
            yaml.scalar @assistant

            yaml.scalar "installed_at"
            yaml.scalar @installed_at

            yaml.scalar "components"
            yaml.mapping do
              @components.each do |name, enabled|
                yaml.scalar name
                yaml.scalar enabled.to_s
              end
            end

            yaml.scalar "files"
            yaml.mapping do
              @files.each do |path, checksum|
                yaml.scalar path
                yaml.mapping do
                  yaml.scalar "checksum"
                  yaml.scalar checksum
                end
              end
            end
          end
        end
      end
    end

    def installed? : Bool
      !@installed_version.empty?
    end
  end
end
