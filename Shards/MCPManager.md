# class Shards::MCPManager

## Constants

- `BIN_DIR` = `"bin"`
- `Log` = `::Log.for("shards.mcp")`
- `MCP_SHARDS_CONFIG` = `".mcp-shards.json"`
- `RUNTIME_DIR` = `".shards/mcp"`
- `STATE_FILE` = `"servers.json"`

## Constructors

### `new(path : String)`

## Instance Methods

### `load_configs`

### `logs(name : String, follow : Bool = true, lines : Int32 = 20)`

### `path`

### `restart(name : String | Nil = nil)`

### `sanitize_name(name : String) : String`

### `start(name : String | Nil = nil)`

### `status`

### `stop(name : String | Nil = nil)`

## Types

- `Shards::MCPManager::ServerConfig` (struct)
- `Shards::MCPManager::ServerState` (struct)
- `Shards::MCPManager::ServerStatusInfo` (struct)
- `Shards::MCPManager::StateFile` (struct)

