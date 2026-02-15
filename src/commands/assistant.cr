require "../assistant_config"

module Shards
  module Commands
    class Assistant
      HELP_TEXT = <<-HELP
      shards-alpha assistant — Manage Claude Code assistant configuration

      Usage:
          shards-alpha assistant [command] [options]

      Commands:
          init     Install skills, agents, settings, and MCP config
          update   Update to latest version (preserves local modifications)
          status   Show installed version and state (default)
          remove   Remove all tracked assistant files

      Options:
          --no-mcp        Skip MCP server configuration (.mcp.json)
          --no-skills     Skip Claude Code skills
          --no-agents     Skip Claude Code agents
          --no-settings   Skip settings.json and CLAUDE.md
          --force         Overwrite existing/modified files
          --dry-run       Preview changes without writing (update only)
      HELP

      def self.run(path : String, args : Array(String))
        subcommand = "status"
        skip_components = [] of String
        force = false
        dry_run = false

        args.each do |arg|
          case arg
          when "init", "update", "status", "remove"
            subcommand = arg
          when "--no-mcp"
            skip_components << "mcp"
          when "--no-skills"
            skip_components << "skills"
          when "--no-agents"
            skip_components << "agents"
          when "--no-settings"
            skip_components << "settings"
          when "--force"
            force = true
          when "--dry-run"
            dry_run = true
          when "--help", "-h"
            puts HELP_TEXT
            return
          end
        end

        case subcommand
        when "init"
          AssistantConfig.install(path, skip_components, force)
        when "update"
          AssistantConfig.update(path, force, dry_run)
        when "status"
          AssistantConfig.status(path)
        when "remove"
          AssistantConfig.remove(path)
        end
      end
    end
  end
end
