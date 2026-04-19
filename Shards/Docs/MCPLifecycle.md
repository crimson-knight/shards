# module Shards::Docs::MCPLifecycle

## MCP Server Lifecycle Management

The `shards mcp` command manages the runtime lifecycle of MCP servers
distributed via `.mcp-shards.json`. This completes the pipeline from
distribution (handled by `shards install`) to execution.

### Commands

```
shards mcp                         # Show server status (default)
shards mcp start [server_name]     # Start all or one server
shards mcp stop [server_name]      # Stop all or one server
shards mcp restart [server_name]   # Restart all or one server
shards mcp logs <name> [--no-follow] [--lines=N]
```

### Runtime state

All managed state lives in `.shards/mcp/`:
- `servers.json`: PID, port, timestamps per server
- `<name>.log`: per-server stdout/stderr logs
- `bin/`: cached builds for `crystal_main` servers

### Process management

Servers are spawned via `Process.new` (non-blocking) with output
redirected to log files. PID tracking uses `LibC.kill(pid, 0)`.
Shutdown sends SIGTERM, waits 5 seconds, then SIGKILL if needed.
Stale PIDs are detected and cleaned on every status check.

### Name resolution

Server names use the existing namespacing from `.mcp-shards.json`
(e.g., `my_shard/explorer`). Partial name matching is supported:
`explorer` finds `my_shard/explorer` if unambiguous.

See `MCPManager`, `Commands::MCP`.

