module Shards
  module AssistantVersions
    # Embedded at compile time by walking src/assistant_versions/
    VERSIONS = {{ run("./build_assistant_versions") }}

    # Build current file state by overlaying all versions oldest-to-newest
    def self.current_files : Hash(String, String)
      result = {} of String => String
      VERSIONS.keys.sort.each do |version|
        VERSIONS[version].each { |path, content| result[path] = content }
      end
      result
    end

    # Get only files that changed since a given version
    def self.files_changed_since(since_version : String) : Hash(String, String)
      result = {} of String => String
      VERSIONS.keys.sort.each do |version|
        next if version <= since_version
        VERSIONS[version].each { |path, content| result[path] = content }
      end
      result
    end

    def self.latest_version : String
      VERSIONS.keys.sort.last
    end

    def self.all_versions : Array(String)
      VERSIONS.keys.sort
    end
  end
end
