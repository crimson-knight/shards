# module Shards::AssistantConfig

## Constants

- `COMPONENT_NAMES` = `["mcp", "skills", "agents", "settings"] of ::String`
- `MCP_SERVER_NAME` = `"shards-compliance"`

## Class Methods

### `auto_install(path : String)`

Called from install pipeline — auto-install or update as needed

### `component_for(path : String) : String`

Classify a file path into its component group.
Paths may have ./ prefix from the build script.

### `filter_by_components(files : Hash(String, String), components : Hash(String, Bool)) : Hash(String, String)`

Filter files by enabled components

### `install(path : String, skip_components : Array(String) = [] of String, force : Bool = false)`

Install assistant configuration files

### `install_mcp_config(path : String)`

Install/merge MCP server entry into .mcp.json

### `legacy_install?(path : String) : Bool`

Detect legacy mcp-server init installs (files exist but no tracking YAML)

### `remove(path : String)`

Remove all tracked assistant config files

### `status(path : String)`

Show status of installed assistant config

### `update(path : String, force : Bool = false, dry_run : Bool = false)`

Update assistant configuration files

