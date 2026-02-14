# MCP Server Lifecycle Management in Shards

## The Vision

Library authors distribute MCP servers alongside their Crystal shards. When a developer starts working on a project, they run `shards mcp start` and all the MCP servers from their dependencies spin up as local processes. Their coding agent connects to these servers and gets specialized tooling for each library they're using -- database query builders, API explorers, schema validators, whatever the library author decides to ship.

When done, `shards mcp stop` cleanly shuts everything down.

## What We Already Have

Shards already handles the **distribution** side:

1. **`.mcp.json` in shards** -- library authors ship MCP server configs
2. **`install_mcp_config`** -- during `shards install`, configs are merged into `.mcp-shards.json` with namespaced server names and rewritten paths
3. **`shards ai-docs merge-mcp`** -- merges `.mcp-shards.json` into the user's `.mcp.json`
4. **Pruning** -- when shards are removed, their MCP entries are cleaned up

What's missing is the **runtime** side: actually starting, monitoring, and stopping these servers.

## Proposed Command Interface

```
shards mcp start [server_name]    # Start all (or one) MCP servers
shards mcp stop [server_name]     # Stop all (or one) MCP servers
shards mcp status                 # Show running MCP servers
shards mcp restart [server_name]  # Restart servers
shards mcp logs [server_name]     # Tail server logs
```

## How It Would Work

### Server Configuration (already exists in `.mcp-shards.json`)

```json
{
  "mcpServers": {
    "my_db_shard/explorer": {
      "command": "lib/my_db_shard/bin/mcp-server",
      "args": ["--mode", "readonly", "--port", "0"],
      "env": { "DB_URL": "${DATABASE_URL}" }
    }
  }
}
```

### Start Flow

1. Read `.mcp-shards.json` (or `.mcp.json` after merge)
2. For each server entry:
   - Resolve the command path (relative to project root)
   - If it's a Crystal source and no binary exists, build it first
   - Spawn the process with configured args and env
   - Capture the assigned port (if `--port 0` for auto-assign)
   - Write PID + port to `.shards/mcp/<server_name>.pid`
   - Redirect stdout/stderr to `.shards/mcp/<server_name>.log`
3. Update a runtime manifest (`.shards/mcp/servers.json`) with all running server info
4. Print connection info for the user/agent

### Stop Flow

1. Read `.shards/mcp/servers.json`
2. For each server: send SIGTERM, wait briefly, SIGKILL if needed
3. Clean up PID files and runtime manifest

### Status Output

```
MCP Servers:
  my_db_shard/explorer    running   pid=12345  port=9847  uptime=2h15m
  my_api_shard/validator  running   pid=12346  port=9848  uptime=2h15m
  my_auth_shard/tokens    stopped
```

## Server Distribution Patterns

### Pattern 1: Pre-compiled Binary

The library ships a pre-compiled MCP server binary in `bin/`.

```yaml
# shard.yml
scripts:
  postinstall: crystal build src/mcp_server.cr -o bin/mcp-server --release
```

```json
// .mcp.json
{
  "mcpServers": {
    "explorer": {
      "command": "./bin/mcp-server",
      "args": ["--stdio"]
    }
  }
}
```

After `shards install`, the postinstall builds the binary. `shards mcp start` just runs it.

### Pattern 2: Crystal Source (Build on Start)

The library ships Crystal source; shards builds it on first start.

```json
{
  "mcpServers": {
    "explorer": {
      "crystal_main": "src/mcp_server.cr",
      "args": ["--stdio"]
    }
  }
}
```

When `shards mcp start` sees `crystal_main` instead of `command`, it runs `crystal build` first, caching the binary in `.shards/mcp/bin/`.

### Pattern 3: HTTP Server (Port-based)

For agents that prefer HTTP over stdio:

```json
{
  "mcpServers": {
    "explorer": {
      "command": "./bin/mcp-server",
      "args": ["--http", "--port", "0"],
      "transport": "http"
    }
  }
}
```

The `--port 0` tells the OS to assign a free port. The server writes its port to stdout on startup. Shards captures this and records it in the runtime manifest.

## Integration with Coding Agents

### Agent Discovery

When a coding agent starts, it can read `.shards/mcp/servers.json` to discover running MCP servers:

```json
{
  "servers": {
    "my_db_shard/explorer": {
      "pid": 12345,
      "transport": "stdio",
      "command": "lib/my_db_shard/bin/mcp-server",
      "started_at": "2026-02-14T10:30:00Z"
    }
  }
}
```

### Auto-start on Agent Launch

A `.claude/hooks/` pre-session hook could auto-start MCP servers:

```json
{
  "hooks": {
    "PreToolUse": [{
      "command": "shards mcp start --quiet",
      "event": "session_start"
    }]
  }
}
```

### Connection via .mcp.json

After `shards mcp start`, the merge into `.mcp.json` means Claude Code (or any MCP-aware agent) automatically sees and can connect to these servers. The lifecycle is:

1. `shards install` -- installs code, copies MCP configs to `.mcp-shards.json`
2. `shards ai-docs merge-mcp` -- merges into `.mcp.json`
3. `shards mcp start` -- spawns the actual processes
4. Agent connects via `.mcp.json` entries
5. `shards mcp stop` -- cleans up when done

## What the MCP Shard Provides

There's an existing Crystal MCP shard that implements the MCP protocol. This means Crystal library authors can write MCP servers in Crystal with:

- Tool definitions
- Resource providers
- Prompt templates
- Stdio and HTTP transports

The shards package manager would handle distribution and lifecycle; the MCP shard handles the protocol implementation.

## Key Design Decisions to Make

### 1. Stdio vs HTTP

Most MCP implementations use stdio (agent spawns the server as a child process). But shards managing server lifecycle means the server is already running when the agent starts. Options:

- **Stdio proxy**: Shards starts the server, agent connects via stdio pipe (needs a proxy or named pipe)
- **HTTP transport**: Servers listen on localhost ports, agent connects via HTTP (simpler for pre-started servers)
- **Both**: Support both, let the config decide

**Recommendation**: Start with the stdio approach since that's what most MCP clients expect. The `.mcp.json` `command` field already tells the agent how to spawn. Shards' role would be to ensure the binary is built and ready, not necessarily to keep it running as a daemon. For HTTP servers, shards would manage the lifecycle.

### 2. Build on Install vs Build on Start

- **Install time** (via postinstall): Simpler, binary ready when needed. But postinstall scripts have security implications.
- **Start time**: Lazier, only builds if needed. But adds latency to `shards mcp start`.

**Recommendation**: Support both. Postinstall for shards that want it. `crystal_main` auto-build for convenience.

### 3. Process Management

- **Foreground** (`shards mcp start --foreground`): Stays in terminal, Ctrl-C stops all. Good for development.
- **Background** (default): Daemonize, write PID files. Good for long-running sessions.

### 4. Port Management

For HTTP servers, auto-assign ports and write them to the runtime manifest. The manifest becomes the discovery mechanism.

## Implementation Estimate

| Component | Description |
|-----------|-------------|
| `src/commands/mcp.cr` | Command dispatcher (start/stop/status/restart/logs) |
| `src/mcp_manager.cr` | Process spawning, PID tracking, log management |
| MCP shard integration | Ensure the existing MCP shard works for server authoring |
| `.shards/mcp/` directory | Runtime state (PIDs, logs, manifest) |
| Tests | Integration tests for start/stop/status lifecycle |

## Relationship to Existing Features

This builds directly on the existing MCP distribution pipeline:

```
Library author writes MCP server (using MCP shard)
  → Ships .mcp.json + binary/source in their shard
    → shards install copies config to .mcp-shards.json  [EXISTS]
      → shards ai-docs merge-mcp updates .mcp.json      [EXISTS]
        → shards mcp start spawns the servers            [NEW]
          → Agent discovers and connects                 [NEW]
            → shards mcp stop cleans up                  [NEW]
```

The upward spiral: better tools make it easier to build libraries, which attract more users, which incentivizes more tooling.
