# Shards-Alpha Examples

This directory contains a hands-on walkthrough of shards-alpha's features:
AI documentation distribution, MCP server management, and SBOM generation.

## What's Here

```
demo-shard/          A sample Crystal library that ships AI docs and an MCP server
demo-app/            A consumer project that depends on demo-shard
```

## Prerequisites

- Crystal (>= 1.0.0)
- shards-alpha (`shards` or `shards-alpha` binary built from this repo)

## Step 1: Examine the Demo Shard

Look at the files in `demo-shard/` to see what triggers auto-detection:

```
demo-shard/
  shard.yml                                   # Standard shard metadata
  src/demo_analytics.cr                       # Library code
  CLAUDE.md                                   # AI context — auto-detected
  .claude/skills/getting-started/SKILL.md     # AI skill — auto-detected
  .mcp.json                                   # MCP server config — auto-detected
  src/mcp_server.cr                           # MCP server source
```

**Auto-detected locations** — shards-alpha scans each dependency for:

| Path | What it does |
|------|-------------|
| `.claude/skills/<name>/` | Copied as `<shard>--<name>` skill |
| `.claude/agents/<name>.md` | Copied as `<shard>--<name>.md` agent |
| `.claude/commands/<name>.md` | Copied as `<shard>:<name>.md` command |
| `CLAUDE.md` | Wrapped as a passive `<shard>--docs` skill |
| `AGENTS.md` | Placed as reference doc |
| `.mcp.json` | Merged into `.mcp-shards.json` |

## Step 2: Install Dependencies

```sh
cd examples/demo-app
shards install
```

You should see output like:

```
Installing demo_analytics (0.1.0) from path ../demo-shard
Installed AI docs for demo_analytics (2 files)
MCP servers from demo_analytics available in .mcp-shards.json
```

## Step 3: Inspect What Was Distributed

After install, check what appeared in demo-app:

```sh
# AI docs were namespaced and installed
ls .claude/skills/
# => demo_analytics--getting-started/  demo_analytics--docs/

# The getting-started skill was copied with shard namespace
cat .claude/skills/demo_analytics--getting-started/SKILL.md

# CLAUDE.md was placed as a reference doc (since the shard also has skills)
cat .claude/skills/demo_analytics--docs/reference/CLAUDE.md

# MCP server config was merged with namespaced server names
cat .mcp-shards.json
# => { "mcpServers": { "demo_analytics/query-tool": { ... } } }
```

## Step 4: Check AI Docs Status

```sh
shards ai-docs
```

This shows all installed AI documentation, which shards they came from,
and whether any files have local modifications.

## Step 5: Start MCP Servers

```sh
shards mcp start
```

This starts all MCP servers defined in `.mcp-shards.json`. For our demo,
it launches the `demo_analytics/query-tool` server.

Check status:

```sh
shards mcp
```

Output shows each server's name, status (running/stopped), PID, and uptime.

## Step 6: View Server Logs

```sh
# Follow logs (Ctrl+C to stop)
shards mcp logs demo_analytics/query-tool

# Or show last 20 lines without following
shards mcp logs demo_analytics/query-tool --no-follow
```

## Step 7: Verify with Claude Code

The MCP server is now running and available to Claude Code:

```sh
# Point Claude Code at the shards MCP config
claude -p "Use the query_analytics tool to get page_views" \
  --mcp-config .mcp-shards.json
```

Claude Code will discover the `query_analytics` tool from the running
MCP server and call it, returning the demo analytics data.

## Step 8: Stop MCP Servers

```sh
# Stop all servers
shards mcp stop

# Or stop a specific server
shards mcp stop demo_analytics/query-tool
```

Servers are stopped gracefully with SIGTERM (5-second timeout) then SIGKILL
if needed.

## Step 9: Generate an SBOM

```sh
# Generate SPDX 2.3 JSON (default)
shards sbom

# Or CycloneDX 1.6 JSON
shards sbom --format=cyclonedx
```

This produces a Software Bill of Materials listing all dependencies with
their versions, licenses, and package URLs.

## Step 10: Generate Documentation

```sh
shards docs
```

This generates Crystal API documentation for the project.

## For Shard Authors

To make your shard distribute AI docs and MCP servers automatically:

1. **Add a `CLAUDE.md`** at your shard root with usage context for AI assistants
2. **Add skills** in `.claude/skills/<name>/SKILL.md` for specific workflows
3. **Add an `.mcp.json`** if your shard provides MCP tools:

```json
{
  "mcpServers": {
    "my-tool": {
      "command": "crystal",
      "args": ["run", "--no-color", "./src/mcp_server.cr"]
    }
  }
}
```

4. **Optionally configure** `ai_docs` in `shard.yml` for fine-grained control:

```yaml
ai_docs:
  include:
    - docs/extra_guide.md
  exclude:
    - .claude/skills/internal_only/
```

Everything is auto-detected on `shards install` — consumers don't need
any special configuration.
