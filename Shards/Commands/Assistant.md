# class Shards::Commands::Assistant

## Constants

- `HELP_TEXT` = `"shards-alpha assistant — Manage Claude Code assistant configuration\n\nUsage:\n    shards-alpha assistant [command] [options]\n\nCommands:\n    init     Install skills, agents, settings, and MCP config\n    update   Update to latest version (preserves local modifications)\n    status   Show installed version and state (default)\n    remove   Remove all tracked assistant files\n\nOptions:\n    --no-mcp        Skip MCP server configuration (.mcp.json)\n    --no-skills     Skip Claude Code skills\n    --no-agents     Skip Claude Code agents\n    --no-settings   Skip settings.json and CLAUDE.md\n    --force         Overwrite existing/modified files\n    --dry-run       Preview changes without writing (update only)"`

## Class Methods

### `run(path : String, args : Array(String))`

