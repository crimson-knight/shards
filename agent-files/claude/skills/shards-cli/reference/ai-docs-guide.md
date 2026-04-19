# AI Documentation Distribution Guide

## Overview

Shards can distribute AI coding agent documentation alongside library code. When you run `shards install`, AI docs from dependencies are automatically installed into your project's `.claude/` directory.

This enables library publishers to ship skills, context docs, agents, and MCP configurations so that AI coding assistants can effectively help developers use their libraries.

## How It Works

### Auto-Detection

Shards automatically detects these locations in dependencies:

| Source in shard | What it is |
|-----------------|------------|
| `.claude/skills/<name>/` | Claude Code skills |
| `.claude/agents/<name>.md` | Agent definitions |
| `.claude/commands/<name>.md` | Slash commands |
| `CLAUDE.md` | General AI context |
| `AGENTS.md` | Agent specifications |
| `.mcp.json` | MCP server configs |

### Installation Mapping

Files are namespaced by shard name to avoid conflicts:

| Source | Destination |
|--------|-------------|
| `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
| `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
| `.claude/commands/<name>.md` | `.claude/commands/<shard>:<name>.md` |
| `CLAUDE.md` (no skills) | `.claude/skills/<shard>--docs/SKILL.md` (as passive skill) |
| `CLAUDE.md` (with skills) | `.claude/skills/<shard>--docs/reference/CLAUDE.md` |
| `AGENTS.md` | `.claude/skills/<shard>--docs/reference/AGENTS.md` |
| `.mcp.json` | Merged into `.mcp-shards.json` |

### CLAUDE.md Conversion

When a shard ships `CLAUDE.md` but no explicit skills, it's automatically wrapped as a passive skill with frontmatter:

```markdown
---
name: <shard>--docs
description: Documentation and usage context for the <shard> Crystal library.
user-invocable: false
---
<original CLAUDE.md contents>
```

## Publishing AI Docs

### Recommended: Ship Skills

Create `.claude/skills/` in your shard:

```
your_shard/
  .claude/
    skills/
      getting-started/
        SKILL.md
      api-reference/
        SKILL.md
        reference/
          endpoints.md
  src/
  shard.yml
```

Each `SKILL.md` needs frontmatter:

```markdown
---
name: getting-started
description: How to get started with your_shard
user-invocable: false
---
# Getting Started
...
```

### Simple: Ship CLAUDE.md

For basic documentation, just add a `CLAUDE.md` at your shard root. It will be auto-converted to a passive skill.

### Optional: shard.yml Configuration

The `ai_docs` section is optional and only needed for customization:

```yaml
ai_docs:
  include:
    - docs/claude/advanced_guide.md
  exclude:
    - .claude/skills/internal_dev_tool/
```

### Security

These files are always skipped:
- `.claude/settings.json`
- `.claude/settings.local.json`

## User Customization

Users can modify installed AI docs. The system tracks changes:

- **Unmodified files**: Auto-updated on `shards update`
- **Modified files**: Preserved on update, `.upstream` copy saved for comparison
- **View changes**: `shards ai-docs diff <shard>`
- **Reset to upstream**: `shards ai-docs reset <shard>`
- **Force update**: `shards ai-docs update <shard>`

## MCP Server Distribution

Shards with `.mcp.json` have their servers merged into `.mcp-shards.json`:
- Server names are namespaced: `<shard>/<server_name>`
- Relative command paths are rewritten to `lib/<shard>/...`
- Run `shards ai-docs merge-mcp` to merge into your `.mcp.json`

## Disabling

```
shards install --skip-ai-docs
```
