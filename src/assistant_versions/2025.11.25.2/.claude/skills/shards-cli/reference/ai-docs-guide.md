# AI Documentation Distribution Guide

## Overview

Shards can distribute AI coding agent documentation alongside library code. When you run `shards install`, AI docs from dependencies are automatically installed into your project's `.claude/` directory.

## How It Works

Shards automatically detects these locations in dependencies:

| Source in shard | What it is |
|-----------------|------------|
| `.claude/skills/<name>/` | Claude Code skills |
| `.claude/agents/<name>.md` | Agent definitions |
| `CLAUDE.md` | General AI context |
| `.mcp.json` | MCP server configs |

Files are namespaced by shard name to avoid conflicts:

| Source | Destination |
|--------|-------------|
| `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
| `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
| `CLAUDE.md` | `.claude/skills/<shard>--docs/SKILL.md` |
| `.mcp.json` | Merged into `.mcp-shards.json` |

## Publishing AI Docs

Create `.claude/skills/` in your shard with `SKILL.md` files containing YAML frontmatter:

```markdown
---
name: getting-started
description: How to get started with your_shard
user-invocable: false
---
# Getting Started
...
```

Or simply add a `CLAUDE.md` at your shard root for basic documentation.

## User Customization

- **Unmodified files**: Auto-updated on `shards update`
- **Modified files**: Preserved on update
- **View changes**: `shards ai-docs diff <shard>`
- **Reset to upstream**: `shards ai-docs reset <shard>`
