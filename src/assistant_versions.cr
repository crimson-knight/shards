module Shards
  module AssistantVersions
    # Embedded at compile time by walking src/assistant_versions/
    VERSIONS          = {{ run("./build_assistant_versions") }}
    REMOVED_FILES_KEY = "./removed-files.txt"

    # Build current file state by overlaying all versions oldest-to-newest.
    # A version's removed-files.txt lists paths that it no longer ships.
    def self.current_files : Hash(String, String)
      result = {} of String => String
      VERSIONS.keys.sort.each do |version|
        version_files = VERSIONS[version]
        apply_removals(result, version_files)
        version_files.each do |path, content|
          result[path] = content unless path == REMOVED_FILES_KEY
        end
      end
      result
    end

    # Get files changed since a given version. Removals are handled by
    # comparing current_files with the install tracker.
    def self.files_changed_since(since_version : String) : Hash(String, String)
      result = {} of String => String
      VERSIONS.keys.sort.each do |version|
        next if version <= since_version
        version_files = VERSIONS[version]
        apply_removals(result, version_files)
        version_files.each do |path, content|
          result[path] = content unless path == REMOVED_FILES_KEY
        end
      end
      result
    end

    private def self.apply_removals(files : Hash(String, String), version_files : Hash(String, String))
      return unless removed_paths = version_files[REMOVED_FILES_KEY]?

      removed_paths.each_line do |path|
        path = path.strip
        files.delete(path) unless path.empty? || path.starts_with?("#")
      end
    end

    def self.latest_version : String
      VERSIONS.keys.sort.last
    end

    def self.all_versions : Array(String)
      VERSIONS.keys.sort
    end
  end
end
