# class Shards::Commands::AIDocs

Manages AI documentation installed from shard dependencies.

Subcommands:
- `status` (default): show installed AI docs and their state
- `diff <shard>`: compare local modifications against upstream
- `reset <shard> [file]`: discard local changes, restore upstream
- `update [shard]`: force re-install, overwriting local changes
- `merge-mcp`: merge `.mcp-shards.json` entries into `.mcp.json`

## Instance Methods

### `run(args : Array(String))`

Dispatches to the appropriate subcommand based on *args*.

