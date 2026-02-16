# AI Documentation Distribution Guide

## Overview

Shards can distribute AI coding agent documentation alongside library code. When you run `shards install`, AI docs from dependencies are automatically installed into your project's `.claude/` directory. Each dependency's version is recorded so that updates are tracked per-shard.

## How It Works

Shards automatically detects these locations in dependencies:

| Source in shard | What it is |
|-----------------|------------|
| `.claude/skills/<name>/` | Claude Code skills |
| `.claude/agents/<name>.md` | Agent definitions |
| `.claude/commands/<name>.md` | Slash command files |
| `CLAUDE.md` | General AI context |
| `AGENTS.md` | Agent specifications |
| `.mcp.json` | MCP server configs |

Files are namespaced by shard name to avoid conflicts:

| Source | Destination |
|--------|-------------|
| `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
| `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
| `.claude/commands/<name>.md` | `.claude/commands/<shard>:<name>.md` |
| `CLAUDE.md` | `.claude/skills/<shard>--docs/SKILL.md` |
| `AGENTS.md` | `.claude/skills/<shard>--docs/reference/AGENTS.md` |
| `.mcp.json` | Merged into `.mcp-shards.json` |

## Version and Checksum Tracking

Every installed AI doc file is tracked in `.claude/.ai-docs-info.yml`. This file records:

- **Which version** of each dependency the docs came from (the version in `shard.lock`)
- **Two checksums per file** for detecting local modifications

Example tracking file:

```yaml
version: "1.0"
shards:
  kemal:
    version: "1.3.0"
    files:
      .claude/skills/kemal--routing/SKILL.md:
        upstream_checksum: "sha256:abc123..."
        installed_checksum: "sha256:abc123..."
      .claude/skills/kemal--docs/SKILL.md:
        upstream_checksum: "sha256:def456..."
        installed_checksum: "sha256:789xyz..."
```

### How the dual-checksum system works

- **`upstream_checksum`**: SHA-256 of the file as shipped by the shard author
- **`installed_checksum`**: SHA-256 of the file as it currently exists on disk

When both match, the file is unmodified and safe to auto-update. When they differ, the user has customized the file and it will not be overwritten.

### What happens on `shards install` and `shards update`

1. For each dependency with AI docs, shards reads the **resolved version** from `shard.lock`
2. That version is stored in the tracking file alongside the shard name
3. Each file from the dependency is checksummed before writing
4. If the file already exists on disk:
   - **Unmodified** (disk checksum matches `installed_checksum`): file is overwritten with the new version
   - **Modified by user** (disk checksum differs from both): the user's version is preserved, and the new upstream version is saved as `<file>.upstream` for manual comparison
5. If the file is new: it is written directly

### When a dependency version changes

When you update a dependency (e.g., `kemal` goes from 1.3.0 to 1.4.0), the next `shards install` or `shards update` will:

1. Record the new version (`1.4.0`) in the tracking file
2. Compare each file the shard ships against what's on disk
3. Auto-update files you haven't touched; preserve files you've customized

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

You can also control what gets distributed via `shard.yml`:

```yaml
ai_docs:
  include:
    - docs/api-guide.md
  exclude:
    - .claude/skills/internal-only
```

## Managing AI Docs

```sh
shards ai-docs                  # Show status of all installed AI docs
shards ai-docs diff <shard>     # Compare local modifications vs upstream
shards ai-docs reset <shard>    # Discard local changes, restore upstream
shards ai-docs update [shard]   # Force re-install (overwrites local changes)
shards ai-docs merge-mcp        # Merge .mcp-shards.json into .mcp.json
```

### Status output

The `ai-docs` command shows each shard's version and per-file status:

```
AI Documentation Status:
  kemal (1.3.0):
    .claude/skills/kemal--routing/SKILL.md  [up to date]
    .claude/skills/kemal--docs/SKILL.md     [modified locally]
```

### Handling modifications

- **Unmodified files**: Auto-updated on `shards update`
- **Modified files**: Preserved on update; upstream version saved as `.upstream`
- **View changes**: `shards ai-docs diff <shard>` shows a line-by-line diff
- **Reset to upstream**: `shards ai-docs reset <shard>` or `shards ai-docs reset <shard> <file>`
