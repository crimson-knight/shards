# module Shards::Docs::AIDocumentation

## AI Documentation Distribution

Shards can distribute AI coding agent documentation alongside library
code. When you run `shards install`, AI docs from dependencies are
automatically installed into the project's `.claude/` directory.

### How It Works

The `AIDocsInstaller` scans each installed dependency for AI-relevant
files and copies them into the project with shard-namespaced paths.

### Auto-detected locations

These paths are scanned in each dependency:

| Source in shard | What it is |
|---|---|
| `.claude/skills/<name>/` | Claude Code skills |
| `.claude/agents/<name>.md` | Agent definitions |
| `.claude/commands/<name>.md` | Slash commands |
| `CLAUDE.md` | General AI context |
| `AGENTS.md` | Agent specifications |
| `.mcp.json` | MCP server configs |

### Installation mapping

Files are namespaced by shard name to prevent conflicts:

| Source | Destination |
|---|---|
| `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
| `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
| `.claude/commands/<name>.md` | `.claude/commands/<shard>:<name>.md` |
| `CLAUDE.md` (no skills) | `.claude/skills/<shard>--docs/SKILL.md` |
| `CLAUDE.md` (with skills) | `.claude/skills/<shard>--docs/reference/CLAUDE.md` |
| `AGENTS.md` | `.claude/skills/<shard>--docs/reference/AGENTS.md` |
| `.mcp.json` | merged into `.mcp-shards.json` |

When a shard ships `CLAUDE.md` but no explicit skills, the content is
wrapped as a passive skill with frontmatter (`user-invocable: false`).

### Conflict detection

`AIDocsInfo` tracks two checksums per file (upstream and installed).
User-modified files are preserved during updates, with a `.upstream`
copy saved for comparison. See `AIDocsInfo::FileEntry#user_modified?`.

### Security

`.claude/settings.json` and `.claude/settings.local.json` are never
distributed, even if present in a dependency.

### shard.yml configuration

The `ai_docs` section is optional. Auto-detection handles standard
locations. Use it only for customization:

```yaml
ai_docs:
  include:
    - docs/claude/custom_guide.md
  exclude:
    - .claude/skills/internal_dev_tool/
```

See `Spec::AIDocs`, `AIDocsInstaller`, `AIDocsInfo`.

