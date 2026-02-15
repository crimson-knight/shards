require "digest/sha256"

module Shards
  module Checksum
    ALGORITHM_PREFIX = "sha256"
    EXCLUDED_DIRS    = {".git", ".hg", ".fossil", ".fslckout", "_FOSSIL_"}

    # Compute a deterministic SHA-256 checksum for a directory of source files.
    # Returns a string like "sha256:abcdef1234..."
    def self.compute(path : String) : String
      digest = Digest::SHA256.new
      files = collect_files(path)
      files.sort! # lexicographic sort for determinism

      files.each do |relative_path|
        full_path = File.join(path, relative_path)
        content = File.read(full_path)
        # Hash: relative_path + NUL + file_size + NUL + content
        digest.update(relative_path)
        digest.update("\0")
        digest.update(content.bytesize.to_s)
        digest.update("\0")
        digest.update(content)
      end

      "#{ALGORITHM_PREFIX}:#{digest.final.hexstring}"
    end

    # Verify a checksum against a directory.
    # Returns true if match, false if mismatch.
    def self.verify(path : String, expected : String) : Bool
      compute(path) == expected
    end

    # Collect all files recursively, returning relative paths.
    # Excludes VCS metadata directories.
    private def self.collect_files(base_path : String, prefix : String = "") : Array(String)
      files = [] of String

      Dir.each_child(base_path) do |entry|
        relative = prefix.empty? ? entry : File.join(prefix, entry)
        full = File.join(base_path, entry)

        if File.directory?(full)
          # Skip symlinked directories entirely (avoids infinite loops from lib symlink)
          next if File.symlink?(full)
          next if EXCLUDED_DIRS.includes?(entry)
          next if entry == "lib" && prefix.empty?
          files.concat(collect_files(full, relative))
        elsif File.file?(full) || File.symlink?(full)
          files << relative
        end
      end

      files
    end
  end
end
