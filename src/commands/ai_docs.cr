require "./command"
require "../ai_docs"
require "../ai_docs_info"

module Shards
  module Commands
    # Manages AI documentation installed from shard dependencies.
    #
    # Subcommands:
    # - `status` (default): show installed AI docs and their state
    # - `diff <shard>`: compare local modifications against upstream
    # - `reset <shard> [file]`: discard local changes, restore upstream
    # - `update [shard]`: force re-install, overwriting local changes
    # - `merge-mcp`: merge `.mcp-shards.json` entries into `.mcp.json`
    class AIDocs < Command
      # Dispatches to the appropriate subcommand based on *args*.
      def run(args : Array(String))
        subcommand = args[0]? || "status"
        remaining = args.size > 1 ? args[1..] : [] of String

        case subcommand
        when "status"
          status
        when "diff"
          raise Error.new("Usage: shards ai-docs diff <shard>") if remaining.empty?
          diff(remaining[0])
        when "reset"
          raise Error.new("Usage: shards ai-docs reset <shard> [file]") if remaining.empty?
          reset(remaining[0], remaining[1]?)
        when "update"
          update(remaining[0]?)
        when "merge-mcp"
          merge_mcp
        else
          raise Error.new("Unknown ai-docs subcommand: #{subcommand}. Use: status, diff, reset, update, merge-mcp")
        end
      end

      private def status
        info = Shards.ai_docs_info

        if info.shards.empty?
          Log.info { "No AI documentation installed from dependencies." }
          return
        end

        puts "AI Documentation Status:"
        info.shards.each do |shard_name, entry|
          puts "  #{shard_name} (#{entry.version}):"
          entry.files.each do |file_path, file_entry|
            status_label = if !File.exists?(File.join(path, file_path))
                             "missing"
                           elsif file_entry.user_modified?
                             "modified locally"
                           else
                             "up to date"
                           end
            puts "    #{file_path}  [#{status_label}]"
          end
        end

        # Show MCP servers
        mcp_shards_path = File.join(path, ".mcp-shards.json")
        if File.exists?(mcp_shards_path)
          begin
            config = JSON.parse(File.read(mcp_shards_path))
            if servers = config["mcpServers"]?.try(&.as_h?)
              servers.each do |name, _|
                shard = name.split("/").first
                puts "  .mcp-shards.json: #{name}  [available]" if info.shards.has_key?(shard)
              end
            end
          rescue
          end
        end
      end

      private def diff(shard_name : String)
        info = Shards.ai_docs_info
        entry = info.shards[shard_name]?
        raise Error.new("No AI docs found for shard #{shard_name.inspect}") unless entry

        entry.files.each do |file_path, file_entry|
          full_path = File.join(path, file_path)
          upstream_path = "#{full_path}.upstream"

          if File.exists?(upstream_path) && File.exists?(full_path)
            puts "--- #{file_path} (upstream)"
            puts "+++ #{file_path} (local)"
            # Simple line-by-line diff
            upstream_lines = File.read(upstream_path).lines
            local_lines = File.read(full_path).lines

            max = {upstream_lines.size, local_lines.size}.max
            max.times do |i|
              upstream_line = upstream_lines[i]?
              local_line = local_lines[i]?

              if upstream_line != local_line
                puts "-#{upstream_line}" if upstream_line
                puts "+#{local_line}" if local_line
              end
            end
            puts
          elsif file_entry.user_modified?
            puts "#{file_path}: modified locally (no .upstream file for comparison)"
          else
            puts "#{file_path}: up to date"
          end
        end
      end

      private def reset(shard_name : String, file_filter : String?)
        info = Shards.ai_docs_info
        entry = info.shards[shard_name]?
        raise Error.new("No AI docs found for shard #{shard_name.inspect}") unless entry

        # Re-install from source
        installed = Shards.info.installed[shard_name]?
        raise Error.new("Shard #{shard_name.inspect} is not installed") unless installed

        if file_filter
          # Reset specific file
          upstream_path = File.join(path, "#{file_filter}.upstream")
          dest_path = File.join(path, file_filter)

          if File.exists?(upstream_path)
            FileUtils.cp(upstream_path, dest_path)
            File.delete(upstream_path)
            checksum = AIDocsInfo.checksum_file(dest_path)
            if fe = entry.files[file_filter]?
              entry.files[file_filter] = AIDocsInfo::FileEntry.new(fe.upstream_checksum, fe.upstream_checksum)
            end
            info.save
            Log.info { "Reset #{file_filter} to upstream version" }
          else
            raise Error.new("No upstream version available for #{file_filter}")
          end
        else
          # Force reinstall all AI docs for this shard
          installer = AIDocsInstaller.new(path)

          # Remove existing entries to force fresh install
          claude_dir = File.join(path, ".claude")
          installer.prune([shard_name])

          entry.files.clear
          info.shards[shard_name] = entry

          installer.install([installed])
          Log.info { "Reset all AI docs for #{shard_name}" }
        end
      end

      private def update(shard_name : String?)
        installer = AIDocsInstaller.new(path)

        if shard_name
          installed = Shards.info.installed[shard_name]?
          raise Error.new("Shard #{shard_name.inspect} is not installed") unless installed

          # Clear checksums to force overwrite
          info = Shards.ai_docs_info
          if entry = info.shards[shard_name]?
            entry.files.clear
          end
          info.save

          installer.install([installed])
        else
          # Update all
          info = Shards.ai_docs_info
          info.shards.each do |name, entry|
            entry.files.clear
          end
          info.save

          packages = Shards.info.installed.values
          installer.install(packages)
        end
      end

      private def merge_mcp
        mcp_shards_path = File.join(path, ".mcp-shards.json")
        mcp_path = File.join(path, ".mcp.json")

        unless File.exists?(mcp_shards_path)
          Log.info { "No .mcp-shards.json found. No MCP servers to merge." }
          return
        end

        shard_config = JSON.parse(File.read(mcp_shards_path))
        shard_servers = shard_config["mcpServers"]?.try(&.as_h?) || return

        user_config = if File.exists?(mcp_path)
                        JSON.parse(File.read(mcp_path)).as_h.dup
                      else
                        {} of String => JSON::Any
                      end

        user_servers = (user_config["mcpServers"]?.try(&.as_h?) || {} of String => JSON::Any).dup

        added = 0
        shard_servers.each do |name, config|
          unless user_servers.has_key?(name)
            user_servers[name] = config
            added += 1
          end
        end

        user_config["mcpServers"] = JSON::Any.new(user_servers)
        File.write(mcp_path, user_config.to_pretty_json + "\n")
        Log.info { "Merged #{added} MCP server(s) into .mcp.json" }
      end
    end
  end
end
