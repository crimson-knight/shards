require "digest/sha256"
require "./config"

module Shards
  # Directory digests recorded as `shard.lock` checksums.
  #
  # `sha256-v2:` (written now) hashes a shard's source tree entry by entry:
  # each entry's Git-style mode (regular file, executable file, or symlink), its
  # path, and its bytes. A symlink's bytes are its link text; links are never
  # followed, the way Git records them, so a link to an absolute path or outside
  # the shard is pinned by where it points, not by what it points at. A real
  # top-level `lib/` directory, and a top-level `lib` link to any other target,
  # is hashed like any other entry. Left out are VCS metadata and a top-level
  # `lib` link to INSTALLED_LIB_LINK_TARGET: the link `Package#install` writes
  # into every installed copy that has no `lib` of its own. A source that ships
  # that exact link installs to the same files as one that does not, so the
  # two hash alike; installed copies and fresh checkouts then compare equal.
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

    private REGULAR_FILE_MODE    = "100644"
    private EXECUTABLE_FILE_MODE = "100755"
    private SYMLINK_MODE         = "120000"

    # The current (`sha256-v2:`) digest of the source tree at *path*.
    def self.compute(path : String) : String
      digest_entries(collect_entries(path))
    end

    # The relative paths `compute` hashes under *path*.
    def self.entry_paths(path : String) : Array(String)
      collect_entries(path).map(&.[0])
    end

    # The `sha256-v2:` digest of just *list_of_relative_paths* under *path*,
    # or nil when one of them is missing. Comparing it with the digest of a
    # fresh checkout tells whether every source file is unchanged in an
    # installed copy that also holds postinstall output.
    def self.compute_entries(path : String, list_of_relative_paths : Array(String)) : String?
      list_of_entries = list_of_relative_paths.map { |relative_path| {relative_path, File.join(path, relative_path)} }
      return nil unless list_of_entries.all? { |_, full_path| hashable_entry?(full_path) }

      digest_entries(list_of_entries)
    end

    # The legacy (`sha256:`) digest, computed with its original rules, so a
    # lock entry written by an earlier Minecart can still be verified.
    def self.compute_legacy_sha256(path : String) : String
      legacy_digest(path, collect_legacy_files(path))
    end

    private def self.hashable_entry?(full_path : String) : Bool
      info = File.info?(full_path, follow_symlinks: false)
      !info.nil? && (info.symlink? || info.file?)
    end

    private def self.digest_entries(list_of_entries : Array({String, String})) : String
      digest = Digest::SHA256.new
      list_of_entries.sort_by(&.[0]).each do |relative_path, full_path|
        info = File.info(full_path, follow_symlinks: false)
        if info.symlink?
          entry_mode = SYMLINK_MODE
          content = File.readlink(full_path)
        else
          entry_mode = info.permissions.owner_execute? ? EXECUTABLE_FILE_MODE : REGULAR_FILE_MODE
          content = File.read(full_path)
        end
        # Hash: mode + NUL + relative_path + NUL + byte size + NUL + content
        digest.update(entry_mode)
        digest.update("\0")
        digest.update(relative_path)
        digest.update("\0")
        digest.update(content.bytesize.to_s)
        digest.update("\0")
        digest.update(content)
      end

      "#{PREFIX}#{digest.final.hexstring}"
    end

    private def self.legacy_digest(path : String, list_of_files : Array(String)) : String
      digest = Digest::SHA256.new
      list_of_files.sort.each do |relative_path|
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

    # True for an entry an earlier Minecart wrote (`git-tree:` or v1 `sha256:`).
    def self.legacy?(checksum : String) : Bool
      legacy_sha256?(checksum) || checksum.starts_with?(LEGACY_GIT_TREE_PREFIX)
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
