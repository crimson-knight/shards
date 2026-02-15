require "json"
require "./lockfile_differ"

module Shards
  class DiffReport
    getter changes : Array(LockfileDiffer::Change)
    getter from_label : String
    getter to_label : String

    def initialize(@changes, @from_label = "HEAD", @to_label = "working tree")
    end

    def any_changes? : Bool
      changes.any? { |c| c.status != LockfileDiffer::Status::Unchanged }
    end

    def to_terminal(io : IO = STDOUT) : Nil
      actual = changes.reject { |c| c.status == LockfileDiffer::Status::Unchanged }
      return if actual.empty?

      io.puts "Dependency Changes (from #{from_label} to #{to_label}):"
      io.puts

      added = 0
      updated = 0
      removed = 0

      actual.each do |change|
        case change.status
        when .added?
          added += 1
          icon = "+"
          version_str = "-> #{change.to_version}"
          source_str = change.to_source ? "  #{change.to_resolver_key}:#{change.to_source}" : ""
          io.puts "  #{icon} #{change.name.ljust(20)} #{version_str}#{source_str}"
        when .updated?
          updated += 1
          icon = "^"
          version_str = "#{change.from_version} -> #{change.to_version}"
          commit_str = ""
          if change.from_commit && change.to_commit && change.from_commit != change.to_commit
            commit_str = "  (commit #{change.from_commit.not_nil![0..6]}..#{change.to_commit.not_nil![0..6]})"
          end
          source_change = ""
          if change.from_source != change.to_source
            source_change = "  SOURCE CHANGED"
          end
          io.puts "  #{icon} #{change.name.ljust(20)} #{version_str}#{commit_str}#{source_change}"
        when .removed?
          removed += 1
          icon = "x"
          version_str = "#{change.from_version} -> removed"
          io.puts "  #{icon} #{change.name.ljust(20)} #{version_str}"
        end
      end

      io.puts
      io.puts "Summary: #{added} added, #{updated} updated, #{removed} removed"
    end

    def to_json(io : IO = STDOUT) : Nil
      actual = changes.reject { |c| c.status == LockfileDiffer::Status::Unchanged }

      added_arr = actual.select(&.status.added?)
      removed_arr = actual.select(&.status.removed?)
      updated_arr = actual.select(&.status.updated?)

      result = {
        from:    from_label,
        to:      to_label,
        changes: {
          added:   added_arr.map { |c| change_to_json_hash(c) },
          removed: removed_arr.map { |c| change_to_json_hash(c) },
          updated: updated_arr.map { |c| change_to_json_hash(c) },
        },
        summary: {
          added:   added_arr.size,
          removed: removed_arr.size,
          updated: updated_arr.size,
        },
      }

      io.puts result.to_json
    end

    def to_markdown(io : IO = STDOUT) : Nil
      actual = changes.reject { |c| c.status == LockfileDiffer::Status::Unchanged }

      io.puts "## Dependency Changes"
      io.puts
      io.puts "| Status | Dependency | Version | Source |"
      io.puts "|--------|-----------|---------|--------|"

      actual.each do |change|
        status_str = change.status.to_s
        version_str = case change.status
                      when .added?   then change.to_version.to_s
                      when .removed? then change.from_version.to_s
                      when .updated? then "#{change.from_version} -> #{change.to_version}"
                      else                ""
                      end
        source_str = change.to_source || change.from_source || ""
        io.puts "| #{status_str} | #{change.name} | #{version_str} | #{source_str} |"
      end

      added = actual.count(&.status.added?)
      updated = actual.count(&.status.updated?)
      removed = actual.count(&.status.removed?)

      io.puts
      io.puts "**Summary:** #{added} added, #{updated} updated, #{removed} removed"
    end

    private def change_to_json_hash(change : LockfileDiffer::Change)
      hash = {} of String => String | Nil
      hash["name"] = change.name
      hash["from_version"] = change.from_version
      hash["to_version"] = change.to_version
      hash["from_commit"] = change.from_commit if change.from_commit
      hash["to_commit"] = change.to_commit if change.to_commit
      hash["from_source"] = change.from_source
      hash["to_source"] = change.to_source
      hash
    end
  end
end
