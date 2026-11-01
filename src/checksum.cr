require "digest/sha256"
require "./config"

module Shards
  # Directory digests recorded as `shard.lock` checksums.
  #
  # `sha256-v2:` (written now) hashes a shard's source tree entry by entry:
  # each entry's type (file or symlink), its path, and its bytes. A symlink's
  # bytes are its link text; links are never followed, the way Git records
  # them. A real top-level `lib/` directory is hashed like any other; only VCS
  # metadata and the exact `lib` link Minecart writes into an installed copy
  # are left out.
  #
  # `sha256:` (legacy v1) is the digest Minecart 2025.11.25.8 and earlier wrote.
  # It skipped a top-level `lib/` and symlinked directories, and followed live
  # file links. Existing entries are still verified with exactly those rules so
  # current lock files keep installing; `minecart lock --update-checksums` and
  # `minecart update` verify them and record `sha256-v2:` instead.
  module Checksum
    PREFIX               = "sha256-v2:"
    LEGACY_SHA256_PREFIX = "sha256:"
    EXCLUDED_DIRS        = {".git", ".hg", ".fossil", ".fslckout", "_FOSSIL_"}
    # Target of the `lib` link `Package#install` writes from a shard to the
    # project install path (one `..` per part of INSTALL_DIR).
    INSTALLED_LIB_LINK_TARGET = File.join(Path.new(INSTALL_DIR).parts.map { ".." })

    private FILE_ENTRY    = "file"
    private SYMLINK_ENTRY = "symlink"

    # The current (`sha256-v2:`) digest of the source tree at *path*.
    def self.compute(path : String) : String
      digest = Digest::SHA256.new
      list_of_entries = collect_entries(path)
      list_of_entries.sort_by!(&.[0])

      list_of_entries.each do |relative_path, full_path|
        if File.symlink?(full_path)
          entry_type = SYMLINK_ENTRY
          content = File.readlink(full_path)
        else
          entry_type = FILE_ENTRY
          content = File.read(full_path)
        end
        # Hash: type + NUL + relative_path + NUL + byte size + NUL + content
        digest.update(entry_type)
        digest.update("\0")
        digest.update(relative_path)
        digest.update("\0")
        digest.update(content.bytesize.to_s)
        digest.update("\0")
        digest.update(content)
      end

      "#{PREFIX}#{digest.final.hexstring}"
    end

    # The legacy (`sha256:`) digest, computed with its original rules, so a
    # lock entry written by an earlier Minecart can still be verified.
    def self.compute_legacy_sha256(path : String) : String
      digest = Digest::SHA256.new
      files = collect_legacy_files(path)
      files.sort!

      files.each do |relative_path|
        content = legacy_file_content(File.join(path, relative_path))
        digest.update(relative_path)
        digest.update("\0")
        digest.update(content.bytesize.to_s)
        digest.update("\0")
        digest.update(content)
      end

      "#{LEGACY_SHA256_PREFIX}#{digest.final.hexstring}"
    end

    # Computes the digest of *path* with the algorithm that produced *expected*.
    def self.compute_like(expected : String, path : String) : String
      legacy_sha256?(expected) ? compute_legacy_sha256(path) : compute(path)
    end

    def self.verify(path : String, expected : String) : Bool
      compute_like(expected, path) == expected
    end

    def self.current?(checksum : String) : Bool
      checksum.starts_with?(PREFIX)
    end

    def self.legacy_sha256?(checksum : String) : Bool
      checksum.starts_with?(LEGACY_SHA256_PREFIX)
    end

    # Returns {relative path, full path} for every file and symlink under
    # *base_path*. Symlinked directories are entries, never descended into.
    private def self.collect_entries(base_path : String, prefix : String = "") : Array({String, String})
      list_of_entries = [] of {String, String}

      Dir.each_child(base_path) do |entry|
        relative = prefix.empty? ? entry : File.join(prefix, entry)
        full = File.join(base_path, entry)

        if File.symlink?(full)
          next if prefix.empty? && entry == INSTALL_DIR && File.readlink(full) == INSTALLED_LIB_LINK_TARGET
          list_of_entries << {relative, full}
        elsif File.directory?(full)
          next if EXCLUDED_DIRS.includes?(entry)
          list_of_entries.concat(collect_entries(full, relative))
        elsif File.file?(full)
          list_of_entries << {relative, full}
        end
      end

      list_of_entries
    end

    # Legacy v1 rule: a broken symlink is hashed by its link text; a live one
    # by its target's content.
    private def self.legacy_file_content(full_path : String) : String
      if File.symlink?(full_path) && !File.exists?(full_path)
        "symlink:#{File.readlink(full_path)}"
      else
        File.read(full_path)
      end
    end

    # Legacy v1 rule: symlinked directories and a top-level `lib` directory are
    # skipped entirely.
    private def self.collect_legacy_files(base_path : String, prefix : String = "") : Array(String)
      files = [] of String

      Dir.each_child(base_path) do |entry|
        relative = prefix.empty? ? entry : File.join(prefix, entry)
        full = File.join(base_path, entry)

        if File.directory?(full)
          next if File.symlink?(full)
          next if EXCLUDED_DIRS.includes?(entry)
          next if entry == INSTALL_DIR && prefix.empty?
          files.concat(collect_legacy_files(full, relative))
        elsif File.file?(full) || File.symlink?(full)
          files << relative
        end
      end

      files
    end
  end
end
