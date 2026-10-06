# module Shards::Docs::CLIReference

## CLI Commands Reference

### Core commands

| Command | Description |
|---|---|
| `minecart install` | Install dependencies from `shard.yml` |
| `minecart update [names...]` | Update dependencies to latest compatible |
| `minecart build [targets...]` | Build targets defined in `shard.yml` |
| `minecart run [target]` | Build and run a target |
| `minecart check` | Verify all dependencies are installed |
| `minecart list [--tree]` | List installed dependencies |
| `minecart lock [--update] [--rekey]` | Lock dependencies without installing |
| `shards outdated [--pre]` | Show outdated dependencies |
| `shards prune` | Remove unused dependencies |
| `shards version [path]` | Print the shard version |
| `minecart init` | Generate a new `shard.yml` |

### AI docs commands

| Command | Description |
|---|---|
| `shards ai-docs` | Show installed AI docs status |
| `shards ai-docs diff <shard>` | Diff local changes vs upstream |
| `shards ai-docs reset <shard> [file]` | Reset to upstream version |
| `shards ai-docs update [shard]` | Force re-install AI docs |
| `shards ai-docs merge-mcp` | Merge shard MCP configs into `.mcp.json` |
| `minecart run-script [names...]` | Run pending postinstall scripts |
| `minecart docs [options]` | Generate themed docs with AI buttons |
| `minecart sbom [options]` | Generate SBOM (SPDX/CycloneDX) |

### MCP lifecycle commands

| Command | Description |
|---|---|
| `minecart mcp` | Show MCP server status (default) |
| `minecart mcp start [name]` | Start all or one MCP server |
| `minecart mcp stop [name]` | Stop all or one MCP server |
| `minecart mcp restart [name]` | Restart all or one MCP server |
| `minecart mcp logs <name>` | Tail server logs (`--no-follow`, `--lines=N`) |

### Global flags

| Flag | Description |
|---|---|
| `--frozen` | Strictly install locked versions |
| `--without-development` | Skip dev dependencies |
| `--production` | `--frozen --without-development` |
| `--skip-postinstall` | Skip postinstall scripts |
| `--skip-executables` | Skip executable installation |
| `--skip-ai-docs` | Skip AI documentation installation |
| `--local` | Use local cache only |
| `--jobs=N` | Parallel downloads (default: 8) |

See individual command classes in `Commands`.

