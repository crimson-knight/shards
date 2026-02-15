require "json"
require "./assistant_versions"
require "./assistant_config_info"
require "./ai_docs_info"

module Shards
  module AssistantConfig
    MCP_SERVER_NAME = "shards-compliance"

    COMPONENT_NAMES = %w[mcp skills agents settings]

    # Classify a file path into its component group.
    # Paths may have ./ prefix from the build script.
    def self.component_for(path : String) : String
      normalized = path.lchop("./")
      if normalized.starts_with?(".claude/skills/")
        "skills"
      elsif normalized.starts_with?(".claude/agents/")
        "agents"
      elsif normalized == ".claude/settings.json" || normalized == ".claude/CLAUDE.md"
        "settings"
      else
        "settings"
      end
    end

    # Filter files by enabled components
    def self.filter_by_components(files : Hash(String, String), components : Hash(String, Bool)) : Hash(String, String)
      files.select do |path, _|
        component = component_for(path)
        components.fetch(component, true)
      end
    end

    # Install assistant configuration files
    def self.install(path : String, skip_components : Array(String) = [] of String, force : Bool = false)
      tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
      info = AssistantConfigInfo.new(tracking_path)

      if info.installed? && !force
        Log.info { "Assistant config already installed (version #{info.installed_version}). Use 'assistant update' to upgrade." }
        return
      end

      # Check for legacy mcp-server init files (no tracking YAML)
      if !info.installed? && legacy_install?(path)
        adopt_legacy(path, info, skip_components)
        return
      end

      components = {} of String => Bool
      COMPONENT_NAMES.each do |name|
        components[name] = !skip_components.includes?(name)
      end

      all_files = AssistantVersions.current_files
      files_to_write = filter_by_components(all_files, components)

      installed = [] of String

      files_to_write.each do |relative_path, content|
        full_path = File.join(path, relative_path)
        dir = File.dirname(full_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        if File.exists?(full_path) && !force
          next
        end

        File.write(full_path, content)
        installed << relative_path
      end

      # Handle MCP config if enabled
      if components.fetch("mcp", true)
        install_mcp_config(path)
      end

      # Build checksums for all written files
      file_checksums = {} of String => String
      files_to_write.each do |relative_path, content|
        full_path = File.join(path, relative_path)
        if File.exists?(full_path)
          file_checksums[relative_path] = AIDocsInfo.checksum(content)
        end
      end

      # Save tracking info
      info.installed_version = AssistantVersions.latest_version
      info.installed_at = Time.utc.to_rfc3339
      info.components = components
      info.files = file_checksums
      info.save

      print_install_summary(installed, components)
    end

    # Update assistant configuration files
    def self.update(path : String, force : Bool = false, dry_run : Bool = false)
      tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
      info = AssistantConfigInfo.new(tracking_path)

      unless info.installed?
        Log.error { "No assistant config installed. Run 'shards assistant init' first." }
        return
      end

      latest = AssistantVersions.latest_version
      if info.installed_version == latest && !force
        puts "Assistant config is up to date (version #{latest})."
        return
      end

      changed_files = if force
                        AssistantVersions.current_files
                      else
                        AssistantVersions.files_changed_since(info.installed_version)
                      end

      files_to_write = filter_by_components(changed_files, info.components)

      if files_to_write.empty?
        puts "No files to update."
        return
      end

      updated = [] of String
      skipped = [] of String
      upstream_saved = [] of String

      files_to_write.each do |relative_path, content|
        full_path = File.join(path, relative_path)

        if dry_run
          if File.exists?(full_path)
            tracked_checksum = info.files[relative_path]?
            disk_checksum = AIDocsInfo.checksum_file(full_path)
            if tracked_checksum && tracked_checksum != disk_checksum && !force
              puts "  skip (modified): #{relative_path}"
              skipped << relative_path
            else
              puts "  update: #{relative_path}"
              updated << relative_path
            end
          else
            puts "  create: #{relative_path}"
            updated << relative_path
          end
          next
        end

        dir = File.dirname(full_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        if File.exists?(full_path)
          tracked_checksum = info.files[relative_path]?
          disk_checksum = AIDocsInfo.checksum_file(full_path)

          if tracked_checksum && tracked_checksum != disk_checksum && !force
            # User modified this file — save upstream version alongside
            upstream_path = "#{full_path}.upstream"
            File.write(upstream_path, content)
            skipped << relative_path
            upstream_saved << relative_path
            next
          end
        end

        File.write(full_path, content)
        updated << relative_path
      end

      unless dry_run
        # Update MCP config if component is enabled
        if info.components.fetch("mcp", true)
          install_mcp_config(path)
        end

        # Rebuild all checksums from current state
        all_files = AssistantVersions.current_files
        file_checksums = {} of String => String
        filter_by_components(all_files, info.components).each do |relative_path, content|
          full_path = File.join(path, relative_path)
          if File.exists?(full_path)
            # Use the expected content checksum for files we wrote,
            # keep the tracked checksum for files we skipped
            if updated.includes?(relative_path)
              file_checksums[relative_path] = AIDocsInfo.checksum(content)
            elsif info.files.has_key?(relative_path)
              file_checksums[relative_path] = info.files[relative_path]
            else
              file_checksums[relative_path] = AIDocsInfo.checksum_file(full_path)
            end
          end
        end

        info.installed_version = latest
        info.installed_at = Time.utc.to_rfc3339
        info.files = file_checksums
        info.save
      end

      if dry_run
        puts ""
        puts "Dry run: #{updated.size} file(s) would be updated, #{skipped.size} skipped (modified locally)."
      else
        puts "Updated #{updated.size} file(s) to version #{latest}."
        unless skipped.empty?
          puts "Skipped #{skipped.size} locally modified file(s):"
          skipped.each { |f| puts "  #{f}" }
          unless upstream_saved.empty?
            puts "Upstream versions saved as .upstream files."
          end
        end
      end
    end

    # Show status of installed assistant config
    def self.status(path : String)
      tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
      info = AssistantConfigInfo.new(tracking_path)

      unless info.installed?
        puts "No assistant config installed."
        puts "Run 'shards assistant init' to set up Claude Code skills, agents, and settings."
        return
      end

      latest = AssistantVersions.latest_version
      puts "Assistant: #{info.assistant}"
      puts "Installed version: #{info.installed_version}"
      puts "Latest version:    #{latest}"
      puts "Installed at:      #{info.installed_at}"

      if info.installed_version != latest
        puts "Status:            Update available"
      else
        puts "Status:            Up to date"
      end

      puts ""
      puts "Components:"
      info.components.each do |name, enabled|
        puts "  #{name}: #{enabled ? "enabled" : "disabled"}"
      end

      # Check for locally modified files
      modified = [] of String
      info.files.each do |relative_path, tracked_checksum|
        full_path = File.join(path, relative_path)
        if File.exists?(full_path)
          disk_checksum = AIDocsInfo.checksum_file(full_path)
          if disk_checksum != tracked_checksum
            modified << relative_path
          end
        end
      end

      unless modified.empty?
        puts ""
        puts "Modified locally (#{modified.size}):"
        modified.each { |f| puts "  #{f}" }
      end
    end

    # Remove all tracked assistant config files
    def self.remove(path : String)
      tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
      info = AssistantConfigInfo.new(tracking_path)

      unless info.installed?
        puts "No assistant config installed."
        return
      end

      removed = [] of String
      info.files.each_key do |relative_path|
        full_path = File.join(path, relative_path)
        if File.exists?(full_path)
          File.delete(full_path)
          removed << relative_path

          # Clean up .upstream files too
          upstream_path = "#{full_path}.upstream"
          File.delete(upstream_path) if File.exists?(upstream_path)
        end
      end

      # Remove empty directories
      cleanup_empty_dirs(File.join(path, ".claude", "skills"))
      cleanup_empty_dirs(File.join(path, ".claude", "agents"))

      # Remove tracking file
      File.delete(tracking_path) if File.exists?(tracking_path)

      puts "Removed #{removed.size} assistant config file(s)."
      puts "Note: .mcp.json was not modified. Remove the '#{MCP_SERVER_NAME}' entry manually if desired."
    end

    # Called from install pipeline — auto-install or update as needed
    def self.auto_install(path : String)
      tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
      info = AssistantConfigInfo.new(tracking_path)

      if info.installed?
        latest = AssistantVersions.latest_version
        if info.installed_version < latest
          Log.info { "Updating assistant config to #{latest}" }
          update(path)
        end
      else
        Log.info { "Auto-installing assistant config" }
        install(path)
      end
    end

    # Detect legacy mcp-server init installs (files exist but no tracking YAML)
    def self.legacy_install?(path : String) : Bool
      tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
      return false if File.exists?(tracking_path)

      # Check if some of the expected files exist
      File.exists?(File.join(path, ".claude", "CLAUDE.md")) ||
        File.exists?(File.join(path, ".claude", "settings.json"))
    end

    # Adopt legacy files into the tracking system
    private def self.adopt_legacy(path : String, info : AssistantConfigInfo, skip_components : Array(String))
      components = {} of String => Bool
      COMPONENT_NAMES.each do |name|
        components[name] = !skip_components.includes?(name)
      end

      all_files = AssistantVersions.current_files
      files_to_track = filter_by_components(all_files, components)

      installed = [] of String
      file_checksums = {} of String => String

      files_to_track.each do |relative_path, content|
        full_path = File.join(path, relative_path)
        dir = File.dirname(full_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        if File.exists?(full_path)
          # Existing file — track it with its current disk checksum
          file_checksums[relative_path] = AIDocsInfo.checksum_file(full_path)
        else
          # Missing file — write it
          File.write(full_path, content)
          file_checksums[relative_path] = AIDocsInfo.checksum(content)
          installed << relative_path
        end
      end

      if components.fetch("mcp", true)
        install_mcp_config(path)
      end

      info.installed_version = AssistantVersions.latest_version
      info.installed_at = Time.utc.to_rfc3339
      info.components = components
      info.files = file_checksums
      info.save

      puts "Adopted existing assistant config (legacy mcp-server init detected)."
      unless installed.empty?
        puts "Created #{installed.size} missing file(s):"
        installed.each { |f| puts "  #{f}" }
      end
    end

    # Install/merge MCP server entry into .mcp.json
    def self.install_mcp_config(path : String)
      mcp_path = File.join(path, ".mcp.json")
      executable = find_executable

      server_entry = {
        "command" => executable,
        "args"    => ["mcp-server"],
      }

      if File.exists?(mcp_path)
        begin
          existing = JSON.parse(File.read(mcp_path))
          servers = existing["mcpServers"]?.try(&.as_h?) || {} of String => JSON::Any

          if servers.has_key?(MCP_SERVER_NAME)
            return # Already configured
          end

          servers[MCP_SERVER_NAME] = JSON.parse(server_entry.to_json)
          config = existing.as_h.dup
          config["mcpServers"] = JSON.parse(servers.to_json)

          File.write(mcp_path, config.to_pretty_json + "\n")
        rescue ex
          write_new_mcp_config(mcp_path, server_entry)
        end
      else
        write_new_mcp_config(mcp_path, server_entry)
      end
    end

    private def self.write_new_mcp_config(mcp_path : String, server_entry)
      config = {
        "mcpServers" => {
          MCP_SERVER_NAME => server_entry,
        },
      }
      File.write(mcp_path, config.to_pretty_json + "\n")
    end

    private def self.find_executable : String
      if Process.find_executable("shards-alpha")
        return "shards-alpha"
      end
      if path = Process.executable_path
        return path
      end
      "shards-alpha"
    end

    private def self.cleanup_empty_dirs(dir : String)
      return unless Dir.exists?(dir)
      Dir.glob(File.join(dir, "**", "*")).sort.reverse_each do |entry|
        if Dir.exists?(entry) && Dir.empty?(entry)
          Dir.delete(entry)
        end
      end
      Dir.delete(dir) if Dir.exists?(dir) && Dir.empty?(dir)
    end

    private def self.print_install_summary(installed : Array(String), components : Hash(String, Bool))
      if installed.empty?
        puts "Assistant config files already exist (no files written)."
        return
      end

      puts "Installed #{installed.size} assistant config file(s):"

      skills = installed.select(&.includes?("/skills/"))
      agents = installed.select(&.includes?("/agents/"))
      other = installed.reject { |f| f.includes?("/skills/") || f.includes?("/agents/") }

      skills.each { |f| puts "  skill:    #{f}" }
      agents.each { |f| puts "  agent:    #{f}" }
      other.each { |f| puts "  config:   #{f}" }

      disabled = components.select { |_, v| !v }.keys
      unless disabled.empty?
        puts ""
        puts "Skipped components: #{disabled.join(", ")}"
      end

      puts ""
      puts "Available skills: /audit, /licenses, /policy-check, /diff-deps, /compliance-report, /sbom"
      puts "Available agents: compliance-checker, security-reviewer"
    end
  end
end
