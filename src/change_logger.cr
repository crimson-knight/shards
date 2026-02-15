require "json"
require "digest/sha256"
require "./lockfile_differ"

module Shards
  class ChangeLogger
    AUDIT_DIR = ".shards/audit"
    LOG_FILE  = "changelog.json"

    def self.record(
      project_path : String,
      action : String,
      old_packages : Array(Package),
      new_packages : Array(Package),
      lockfile_path : String,
    ) : Nil
      changes = LockfileDiffer.diff(old_packages, new_packages)
      # Only log if there are actual changes
      actual = changes.reject { |c| c.status == LockfileDiffer::Status::Unchanged }
      return if actual.empty?

      entry = build_entry(action, actual, lockfile_path)
      entries = load(project_path)
      entries << entry
      write_log(project_path, entries)
    rescue ex
      Log.warn { "Could not write audit log: #{ex.message}" }
    end

    def self.load(project_path : String) : Array(JSON::Any)
      log_path = File.join(project_path, AUDIT_DIR, LOG_FILE)
      return [] of JSON::Any unless File.exists?(log_path)

      parsed = JSON.parse(File.read(log_path))
      if entries = parsed["entries"]?
        entries.as_a
      else
        [] of JSON::Any
      end
    rescue
      [] of JSON::Any
    end

    private def self.build_entry(action : String, changes : Array(LockfileDiffer::Change), lockfile_path : String) : JSON::Any
      added = changes.select(&.status.added?).map { |c| change_detail(c) }
      removed = changes.select(&.status.removed?).map { |c| change_detail(c) }
      updated = changes.select(&.status.updated?).map { |c| change_detail(c) }

      checksum = if File.exists?(lockfile_path)
                   Digest::SHA256.hexdigest(File.read(lockfile_path))
                 else
                   "unknown"
                 end

      JSON.parse({
        timestamp:         Time.utc.to_rfc3339,
        action:            action,
        user:              detect_user,
        changes:           {added: added, removed: removed, updated: updated},
        lockfile_checksum: checksum,
      }.to_json)
    end

    private def self.change_detail(change : LockfileDiffer::Change)
      {
        name:           change.name,
        from_version:   change.from_version,
        to_version:     change.to_version,
        from_commit:    change.from_commit,
        to_commit:      change.to_commit,
        source_changed: change.from_source != change.to_source,
      }
    end

    private def self.detect_user : String
      output = IO::Memory.new
      status = Process.run("git", ["config", "user.email"], output: output)
      if status.success? && !output.to_s.strip.empty?
        return output.to_s.strip
      end
      ENV["USER"]? || ENV["USERNAME"]? || "unknown"
    rescue
      ENV["USER"]? || ENV["USERNAME"]? || "unknown"
    end

    private def self.write_log(project_path : String, entries : Array(JSON::Any)) : Nil
      dir = File.join(project_path, AUDIT_DIR)
      Dir.mkdir_p(dir)
      log_path = File.join(dir, LOG_FILE)
      tmp_path = "#{log_path}.tmp"
      File.write(tmp_path, {entries: entries}.to_json)
      File.rename(tmp_path, log_path)
    end
  end
end
