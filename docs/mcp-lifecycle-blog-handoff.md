# MCP Server Lifecycle Management — Blog Post Handoff

## What to announce

Minecart, formerly distributed as shards-alpha, manages the full lifecycle of MCP (Model Context Protocol) servers distributed through shard dependencies. Previously, `minecart install` could distribute MCP server configurations from dependencies into `.mcp-shards.json` and merge them into `.mcp.json` for agent discovery. What was missing was the **runtime** side — actually starting, monitoring, and stopping these servers. This release closes that gap.

## The command

```
minecart mcp                         # Show server status (default)
minecart mcp start [server_name]     # Start all or one server
minecart mcp stop [server_name]      # Stop all or one server
minecart mcp restart [server_name]   # Restart all or one server
minecart mcp logs <name> [--no-follow] [--lines=N]  # Tail server logs
```

## What it does

**Distribution → Execution pipeline, now complete:**

1. A shard author ships `.mcp.json` in their repository
2. `minecart install` parses it, namespaces the servers (e.g., `my_shard/db-explorer`), rewrites paths, and merges into `.mcp-shards.json`
3. `minecart ai-docs merge-mcp` optionally merges into the user's `.mcp.json` for Claude Code discovery
4. **NEW:** `minecart mcp start` launches the servers as managed background processes

**Process management details:**

- Servers are spawned via Crystal's `Process.new` (non-blocking) with stdout/stderr redirected to per-server log files in `.minecart/mcp/` for new projects; existing `.shards/mcp/` state continues to be used
- PID tracking and health checking via POSIX `kill(pid, 0)`
- Graceful shutdown: SIGTERM → 5 second grace period → SIGKILL
- Stale PID detection: if a server crashes or is killed externally, `minecart mcp status` detects it and updates state automatically
- State persisted in `.minecart/mcp/servers.json` for new projects; existing `.shards/mcp/servers.json` remains supported

**Name resolution:**

Server names use the existing namespacing from `.mcp-shards.json` (e.g., `my_shard/explorer`). Partial matching is supported — `minecart mcp start explorer` finds `my_shard/explorer` if the name is unambiguous.

**Crystal source builds:**

When an MCP server config specifies `crystal_main` instead of `command`, Minecart compiles the Crystal source to `.minecart/mcp/bin/` for new projects. Rebuilds are skipped if the binary is newer than the source file (modification time comparison).

## End-to-end verified

The feature was tested end-to-end by:

1. Building a minimal Crystal MCP stdio server that implements the JSON-RPC 2.0 protocol and exposes a `get_shards_build_info` tool returning a verification phrase
2. Testing the raw MCP protocol (initialize → tools/list → tools/call) to confirm correct JSON-RPC responses
3. Testing `minecart mcp start/stop/status/restart/logs` lifecycle management
4. Using `claude -p --mcp-config` to have Claude Code discover and invoke the tool, confirming the verification phrase appeared in Claude's response

All 11 E2E tests pass, plus 15 Crystal integration tests in `spec/integration/mcp_spec.cr`.

## Example workflow for a user

```bash
# Install a shard that ships an MCP server
minecart install

# See what MCP servers are available from dependencies
minecart mcp
# Output:
#   MCP Servers:
#     analytics_shard/query-tool  [stopped]  stdio

# Start the server
minecart mcp start
# Output:
#   Starting analytics_shard/query-tool: lib/analytics_shard/bin/mcp-server --stdio
#   Started analytics_shard/query-tool (PID 12345)

# Check it's running
minecart mcp
# Output:
#   MCP Servers:
#     analytics_shard/query-tool  [running]  stdio  PID 12345  uptime 2m 15s

# Tail the logs
minecart mcp logs query-tool

# When done, stop it
minecart mcp stop
```

## For shard authors

No changes needed if you already ship `.mcp.json`. The lifecycle commands work with the existing `.mcp-shards.json` format produced by `minecart install`.

If you want to ship a Crystal-based MCP server that gets compiled on install, use `crystal_main` in your `.mcp.json`:

```json
{
  "mcpServers": {
    "my-tool": {
      "crystal_main": "src/mcp_server.cr",
      "args": ["--stdio"]
    }
  }
}
```

Minecart compiles it to `.minecart/mcp/bin/` on first `minecart mcp start`, skipping rebuilds when the binary is up to date.

## Technical notes for the blog writer

- **No new dependencies** — uses Crystal stdlib only (`Process`, `JSON`, `File`, `Time`, `LibC`)
- **Runtime state is ephemeral** — new projects keep it in `.minecart/mcp/`; existing `.shards/mcp/` state is reused. No project files are modified.
- **POSIX-first** — PID management uses `LibC.kill(pid, 0)` for process checking, `SIGTERM`/`SIGKILL` for shutdown. The approach mirrors how systemd manages services but without requiring root.
- **Transport detection** — the config is inspected for `transport: "sse"` or `url` fields to distinguish HTTP/SSE servers from stdio. Default is stdio.

## Files changed

| File | What |
|------|------|
| `src/mcp_manager.cr` | Core lifecycle manager (~280 lines) |
| `src/commands/mcp.cr` | CLI command dispatcher (~80 lines) |
| `src/cli.cr` | Added `mcp` to builtin commands |
| `src/docs.cr` | Added MCPLifecycle documentation module |
| `spec/integration/mcp_spec.cr` | 15 integration tests |
| `test/mcp_e2e/` | E2E test suite with real MCP server + Claude Code verification |
