# class Shards::AIDocsInstaller

Detects, installs, and manages AI documentation from shard dependencies.

When dependencies are installed or updated, `AIDocsInstaller` scans each
package for AI-relevant files (skills, agents, commands, CLAUDE.md, etc.)
and copies them into the project's `.claude/` directory with shard-namespaced
paths to avoid conflicts.

It also handles MCP server configuration merging from `.mcp.json` files
shipped by dependencies into a project-level `.mcp-shards.json`.

## Auto-detected locations

The following paths are scanned in each dependency:
- `.claude/skills/` -- Claude Code skill directories
- `.claude/agents/` -- agent definition files
- `.claude/commands/` -- slash command files
- `CLAUDE.md` -- general AI context (converted to passive skill)
- `AGENTS.md` -- agent specifications
- `.mcp.json` -- MCP server configurations

## Namespacing

Files are namespaced by shard name to prevent conflicts:
- Skills: `<shard>--<name>`
- Agents: `<shard>--<name>.md`
- Commands: `<shard>:<name>.md`
- MCP servers: `<shard>/<server_name>`

## Conflict detection

Uses `AIDocsInfo` to track dual checksums per file. User-modified files
are preserved during updates, with an `.upstream` copy saved for comparison.

## Constants

- `SECURITY_SKIP_FILES` = `[".claude/settings.json", ".claude/settings.local.json"]` -- Settings files that are never distributed for security reasons.

## Constructors

### `new(project_path : String)`

## Instance Methods

### `has_ai_docs?(package : Package) : Bool`

Returns `true` if the package contains any auto-detectable AI docs
or has explicit `ai_docs.include` entries in its spec.

### `install(packages : Array(Package))`

Installs AI documentation from the given packages into the project's
`.claude/` directory. Skips packages without AI docs and respects
the `--skip-ai-docs` flag.

### `install_mcp_config(package : Package, mcp_json_path : String)`

Installs MCP server configuration from a shard's `.mcp.json` into the
project's `.mcp-shards.json`. Server names are namespaced as
`<shard>/<server_name>` and relative command/args paths are rewritten
to point into `lib/<shard>/`.

### `project_path`

Root path of the project receiving AI docs.

### `prune(removed_shard_names : Array(String))`

Removes all AI documentation files for the given shard names.
Cleans up skills, agents, commands, .upstream files, and MCP server entries.

