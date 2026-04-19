# module Shards::Docs::PublishingGuide

## Publishing AI Docs for Your Shard

### Recommended: ship skills

Create `.claude/skills/` in your shard repository:

```
your_shard/
  .claude/
    skills/
      getting-started/
        SKILL.md
      api-reference/
        SKILL.md
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

### Simple: ship CLAUDE.md

For basic documentation, add a `CLAUDE.md` at your shard root.
It is auto-converted to a passive skill during installation.

### Optional: customize with shard.yml

```yaml
ai_docs:
  include:
    - docs/claude/advanced_guide.md
  exclude:
    - .claude/skills/internal_dev_tool/
```

### Ship MCP servers

Add `.mcp.json` to your shard root with standard MCP configuration.
Relative paths in `command` and `args` are automatically rewritten.

See `AIDocsInstaller`, `Docs::AIDocumentation`, `Docs::MCPDistribution`.

