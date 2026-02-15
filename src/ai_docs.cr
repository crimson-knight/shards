require "file_utils"
require "json"
require "./ai_docs_info"
require "./helpers"

module Shards
  # Detects, installs, and manages AI documentation from shard dependencies.
  #
  # When dependencies are installed or updated, `AIDocsInstaller` scans each
  # package for AI-relevant files (skills, agents, commands, CLAUDE.md, etc.)
  # and copies them into the project's `.claude/` directory with shard-namespaced
  # paths to avoid conflicts.
  #
  # It also handles MCP server configuration merging from `.mcp.json` files
  # shipped by dependencies into a project-level `.mcp-shards.json`.
  #
  # ## Auto-detected locations
  #
  # The following paths are scanned in each dependency:
  # - `.claude/skills/` -- Claude Code skill directories
  # - `.claude/agents/` -- agent definition files
  # - `.claude/commands/` -- slash command files
  # - `CLAUDE.md` -- general AI context (converted to passive skill)
  # - `AGENTS.md` -- agent specifications
  # - `.mcp.json` -- MCP server configurations
  #
  # ## Namespacing
  #
  # Files are namespaced by shard name to prevent conflicts:
  # - Skills: `<shard>--<name>`
  # - Agents: `<shard>--<name>.md`
  # - Commands: `<shard>:<name>.md`
  # - MCP servers: `<shard>/<server_name>`
  #
  # ## Conflict detection
  #
  # Uses `AIDocsInfo` to track dual checksums per file. User-modified files
  # are preserved during updates, with an `.upstream` copy saved for comparison.
  class AIDocsInstaller
    # Settings files that are never distributed for security reasons.
    SECURITY_SKIP_FILES = [".claude/settings.json", ".claude/settings.local.json"]

    # Root path of the project receiving AI docs.
    getter project_path : String

    def initialize(@project_path)
    end

    # Installs AI documentation from the given packages into the project's
    # `.claude/` directory. Skips packages without AI docs and respects
    # the `--skip-ai-docs` flag.
    def install(packages : Array(Package))
      return if Shards.skip_ai_docs?

      packages_with_docs = packages.select { |pkg| has_ai_docs?(pkg) }
      return if packages_with_docs.empty?

      info = Shards.ai_docs_info

      packages_with_docs.each do |package|
        install_package_ai_docs(package, info)
      end

      info.save
    end

    # Removes all AI documentation files for the given shard names.
    # Cleans up skills, agents, commands, .upstream files, and MCP server entries.
    def prune(removed_shard_names : Array(String))
      return if removed_shard_names.empty?

      info = Shards.ai_docs_info
      claude_dir = File.join(@project_path, ".claude")

      removed_shard_names.each do |shard_name|
        prune_shard(shard_name, claude_dir)
        info.shards.delete(shard_name)
      end

      info.save

      # Clean up .mcp-shards.json entries
      mcp_shards_path = File.join(@project_path, ".mcp-shards.json")
      if File.exists?(mcp_shards_path)
        prune_mcp_servers(removed_shard_names, mcp_shards_path)
      end
    end

    # Returns `true` if the package contains any auto-detectable AI docs
    # or has explicit `ai_docs.include` entries in its spec.
    def has_ai_docs?(package : Package) : Bool
      shard_path = package.install_path
      return false unless Dir.exists?(shard_path)

      ai_docs = package.spec.ai_docs

      # Check auto-detected locations
      return true if Dir.exists?(File.join(shard_path, ".claude", "skills"))
      return true if Dir.exists?(File.join(shard_path, ".claude", "agents"))
      return true if Dir.exists?(File.join(shard_path, ".claude", "commands"))
      return true if File.exists?(File.join(shard_path, "CLAUDE.md"))
      return true if File.exists?(File.join(shard_path, "AGENTS.md"))
      return true if File.exists?(File.join(shard_path, ".mcp.json"))

      # Check explicit include paths
      if ai_docs
        return true unless ai_docs.include.empty?
      end

      false
    end

    private def install_package_ai_docs(package : Package, info : AIDocsInfo)
      shard_name = package.name
      shard_path = package.install_path
      ai_docs = package.spec.ai_docs
      exclude_patterns = ai_docs.try(&.exclude) || [] of String

      shard_entry = info.shards[shard_name]? || AIDocsInfo::ShardEntry.new(package.version.to_s)
      shard_entry.version = package.version.to_s

      # Track which files we install this round (to detect removed files)
      installed_files = Set(String).new

      # Auto-detect and install skills
      skills_dir = File.join(shard_path, ".claude", "skills")
      if Dir.exists?(skills_dir)
        Dir.each_child(skills_dir) do |skill_name|
          skill_src = File.join(skills_dir, skill_name)
          next unless File.directory?(skill_src)
          next if excluded?(File.join(".claude", "skills", skill_name), exclude_patterns)

          dest_name = "#{shard_name}--#{skill_name}"
          dest_dir = File.join(@project_path, ".claude", "skills", dest_name)
          install_directory(skill_src, dest_dir, shard_entry, installed_files)
        end
      end

      # Auto-detect and install agents
      agents_dir = File.join(shard_path, ".claude", "agents")
      if Dir.exists?(agents_dir)
        Dir.each_child(agents_dir) do |agent_file|
          next unless agent_file.ends_with?(".md")
          next if excluded?(File.join(".claude", "agents", agent_file), exclude_patterns)

          src = File.join(agents_dir, agent_file)
          agent_name = agent_file.chomp(".md")
          dest = File.join(@project_path, ".claude", "agents", "#{shard_name}--#{agent_name}.md")
          install_file(src, dest, shard_entry, installed_files)
        end
      end

      # Auto-detect and install commands
      commands_dir = File.join(shard_path, ".claude", "commands")
      if Dir.exists?(commands_dir)
        Dir.each_child(commands_dir) do |cmd_file|
          next unless cmd_file.ends_with?(".md")
          next if excluded?(File.join(".claude", "commands", cmd_file), exclude_patterns)

          src = File.join(commands_dir, cmd_file)
          cmd_name = cmd_file.chomp(".md")
          dest = File.join(@project_path, ".claude", "commands", "#{shard_name}:#{cmd_name}.md")
          install_file(src, dest, shard_entry, installed_files)
        end
      end

      # Handle CLAUDE.md
      claude_md = File.join(shard_path, "CLAUDE.md")
      if File.exists?(claude_md) && !excluded?("CLAUDE.md", exclude_patterns)
        has_skills = Dir.exists?(skills_dir) && Dir.children(skills_dir).any? { |c| File.directory?(File.join(skills_dir, c)) }

        if has_skills
          # Place as reference doc within docs skill
          dest_dir = File.join(@project_path, ".claude", "skills", "#{shard_name}--docs", "reference")
          dest = File.join(dest_dir, "CLAUDE.md")
          install_file(claude_md, dest, shard_entry, installed_files)
        else
          # Convert to passive skill
          dest = File.join(@project_path, ".claude", "skills", "#{shard_name}--docs", "SKILL.md")
          content = generate_passive_skill(shard_name, File.read(claude_md))
          install_generated_file(content, dest, shard_entry, installed_files)
        end
      end

      # Handle AGENTS.md
      agents_md = File.join(shard_path, "AGENTS.md")
      if File.exists?(agents_md) && !excluded?("AGENTS.md", exclude_patterns)
        dest_dir = File.join(@project_path, ".claude", "skills", "#{shard_name}--docs", "reference")
        dest = File.join(dest_dir, "AGENTS.md")
        install_file(agents_md, dest, shard_entry, installed_files)
      end

      # Handle explicit include paths
      if ai_docs
        ai_docs.include.each do |include_path|
          src = File.join(shard_path, include_path)
          next unless File.exists?(src)
          dest = File.join(@project_path, ".claude", "skills", "#{shard_name}--docs", "reference", File.basename(include_path))
          install_file(src, dest, shard_entry, installed_files)
        end
      end

      # Handle .mcp.json (Phase 4)
      mcp_json = File.join(shard_path, ".mcp.json")
      if File.exists?(mcp_json) && !excluded?(".mcp.json", exclude_patterns)
        install_mcp_config(package, mcp_json)
      end

      # Security: warn about settings files
      SECURITY_SKIP_FILES.each do |skip_file|
        if File.exists?(File.join(shard_path, skip_file))
          Log.warn { "Skipping #{skip_file} from #{shard_name} (security: settings files are not distributed)" }
        end
      end

      info.shards[shard_name] = shard_entry

      unless installed_files.empty?
        Log.info { "Installed AI docs for #{shard_name} (#{installed_files.size} files)" }
      end
    end

    private def install_directory(src_dir : String, dest_dir : String, entry : AIDocsInfo::ShardEntry, installed_files : Set(String))
      Dir.glob(File.join(src_dir, "**", "*")).each do |src_file|
        next if File.directory?(src_file)
        relative = src_file.sub(src_dir, "").lstrip('/')
        dest = File.join(dest_dir, relative)
        install_file(src_file, dest, entry, installed_files)
      end
    end

    private def install_file(src : String, dest : String, entry : AIDocsInfo::ShardEntry, installed_files : Set(String))
      content = File.read(src)
      install_generated_file(content, dest, entry, installed_files)
    end

    private def install_generated_file(content : String, dest : String, entry : AIDocsInfo::ShardEntry, installed_files : Set(String))
      upstream_checksum = AIDocsInfo.checksum(content)
      relative_dest = dest.sub(@project_path, "").lstrip('/')
      installed_files << relative_dest

      if File.exists?(dest)
        if file_entry = entry.files[relative_dest]?
          installed_checksum = AIDocsInfo.checksum_file(dest)

          if installed_checksum != file_entry.installed_checksum && installed_checksum != upstream_checksum
            # User has modified the file
            Log.warn { "#{relative_dest} has local modifications, keeping user version" }
            # Save upstream copy for comparison
            File.write("#{dest}.upstream", content)
            entry.files[relative_dest] = AIDocsInfo::FileEntry.new(upstream_checksum, installed_checksum)
            return
          end
        end
      end

      # Safe to install/overwrite
      Dir.mkdir_p(File.dirname(dest))
      File.write(dest, content)
      entry.files[relative_dest] = AIDocsInfo::FileEntry.new(upstream_checksum, upstream_checksum)
    end

    private def generate_passive_skill(shard_name : String, claude_md_content : String) : String
      String.build do |str|
        str << "---\n"
        str << "name: #{shard_name}--docs\n"
        str << "description: Documentation and usage context for the #{shard_name} Crystal library. Provides conventions, API patterns, and coding guidelines.\n"
        str << "user-invocable: false\n"
        str << "---\n"
        str << claude_md_content
      end
    end

    private def excluded?(path : String, exclude_patterns : Array(String)) : Bool
      exclude_patterns.any? do |pattern|
        path.starts_with?(pattern.rstrip('/'))
      end
    end

    private def prune_shard(shard_name : String, claude_dir : String)
      # Clean skills: .claude/skills/<shard>--*/
      skills_dir = File.join(claude_dir, "skills")
      if Dir.exists?(skills_dir)
        Dir.each_child(skills_dir) do |name|
          if name.starts_with?("#{shard_name}--")
            path = File.join(skills_dir, name)
            Log.info { "Pruned AI docs: #{path}" }
            Shards::Helpers.rm_rf(path)
          end
        end
      end

      # Clean agents: .claude/agents/<shard>--*.md
      agents_dir = File.join(claude_dir, "agents")
      if Dir.exists?(agents_dir)
        Dir.each_child(agents_dir) do |name|
          if name.starts_with?("#{shard_name}--") && name.ends_with?(".md")
            path = File.join(agents_dir, name)
            Log.info { "Pruned AI docs: #{path}" }
            File.delete(path)
          end
        end
      end

      # Clean commands: .claude/commands/<shard>:*.md
      commands_dir = File.join(claude_dir, "commands")
      if Dir.exists?(commands_dir)
        Dir.each_child(commands_dir) do |name|
          if name.starts_with?("#{shard_name}:") && name.ends_with?(".md")
            path = File.join(commands_dir, name)
            Log.info { "Pruned AI docs: #{path}" }
            File.delete(path)
          end
        end
      end

      # Clean .upstream files
      if Dir.exists?(skills_dir)
        Dir.glob(File.join(skills_dir, "#{shard_name}--*", "**", "*.upstream")).each do |path|
          File.delete(path)
        end
      end
    end

    # Installs MCP server configuration from a shard's `.mcp.json` into the
    # project's `.mcp-shards.json`. Server names are namespaced as
    # `<shard>/<server_name>` and relative command/args paths are rewritten
    # to point into `lib/<shard>/`.
    def install_mcp_config(package : Package, mcp_json_path : String)
      shard_name = package.name
      mcp_shards_path = File.join(@project_path, ".mcp-shards.json")

      begin
        source_config = JSON.parse(File.read(mcp_json_path))
      rescue ex
        Log.warn { "Failed to parse .mcp.json from #{shard_name}: #{ex.message}" }
        return
      end

      servers = source_config["mcpServers"]?
      return unless servers && servers.as_h?

      # Load existing .mcp-shards.json or create new
      existing = if File.exists?(mcp_shards_path)
                   begin
                     JSON.parse(File.read(mcp_shards_path))
                   rescue
                     JSON.parse(%({"mcpServers": {}}))
                   end
                 else
                   JSON.parse(%({"mcpServers": {}}))
                 end

      merged = JSON.parse(existing.to_json).as_h
      merged_servers = (merged["mcpServers"]?.try(&.as_h?) || {} of String => JSON::Any).dup

      servers.as_h.each do |server_name, config|
        namespaced_name = "#{shard_name}/#{server_name}"
        config_hash = config.as_h.dup

        # Rewrite relative command paths
        if command = config_hash["command"]?.try(&.as_s?)
          if command.starts_with?("./") || command.starts_with?("../")
            config_hash["command"] = JSON::Any.new(Path["lib", shard_name, command].normalize.to_s)
          end
        end

        # Rewrite relative args paths
        if args = config_hash["args"]?.try(&.as_a?)
          rewritten_args = args.map do |arg|
            str = arg.as_s?
            if str && (str.starts_with?("./") || str.starts_with?("../"))
              JSON::Any.new(Path["lib", shard_name, str].normalize.to_s)
            else
              arg
            end
          end
          config_hash["args"] = JSON::Any.new(rewritten_args)
        end

        merged_servers[namespaced_name] = JSON::Any.new(config_hash)
      end

      merged["mcpServers"] = JSON::Any.new(merged_servers)

      File.write(mcp_shards_path, merged.to_pretty_json + "\n")
      Log.info { "MCP servers from #{shard_name} available in .mcp-shards.json" }
    end

    private def prune_mcp_servers(shard_names : Array(String), mcp_shards_path : String)
      begin
        config = JSON.parse(File.read(mcp_shards_path))
      rescue
        return
      end

      servers = config["mcpServers"]?.try(&.as_h?) || return
      updated_servers = servers.reject do |key, _|
        shard_names.any? { |name| key.starts_with?("#{name}/") }
      end

      if updated_servers.empty?
        File.delete(mcp_shards_path)
      else
        result = {"mcpServers" => JSON::Any.new(updated_servers)}
        File.write(mcp_shards_path, result.to_pretty_json + "\n")
      end
    end
  end
end
