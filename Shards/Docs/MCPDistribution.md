# module Shards::Docs::MCPDistribution

## MCP Server Distribution

Shards that ship `.mcp.json` can distribute MCP (Model Context Protocol)
server configurations to consuming projects.

### How it works

When a dependency contains `.mcp.json`, the `AIDocsInstaller`:

1. Parses the JSON and extracts `mcpServers` entries
2. Namespaces server names as `<shard>/<server_name>`
3. Rewrites relative command/args paths to `lib/<shard>/...`
4. Merges into `.mcp-shards.json` at the project root

The user's `.mcp.json` is never modified automatically. To merge
shard servers into the user's config:

```
shards ai - docs merge - mcp
```

### Example .mcp.json in a shard

```json
{
  "mcpServers": {
    "db-explorer": {
      "command": "./bin/mcp-server",
      "args": ["--mode", "readonly"]
    }
  }
}
```

After installation, this becomes `<shard>/db-explorer` in `.mcp-shards.json`
with the command rewritten to `lib/<shard>/bin/mcp-server`.

See `AIDocsInstaller#install_mcp_config`, `Commands::AIDocs`.

