# module Shards::Docs

# Shards Documentation

Shards is the dependency manager for the Crystal programming language.
It reads `shard.yml` to resolve, install, and update dependencies from
source repositories.

## Features

- **Dependency resolution** via `shard.yml` with semantic versioning
- **Lock files** (`shard.lock`) for reproducible builds
- **Build targets** for compiling Crystal executables
- **Postinstall scripts** with version-aware execution tracking
- **AI documentation distribution** from shard dependencies
- **MCP server distribution** via `.mcp-shards.json`

See `Shards::Docs` submodules for detailed guides on each feature area.

## Types

- `Shards::Docs::AIDocumentation` (module)
- `Shards::Docs::CLIReference` (module)
- `Shards::Docs::DocsGeneration` (module)
- `Shards::Docs::MCPDistribution` (module)
- `Shards::Docs::MCPLifecycle` (module)
- `Shards::Docs::PostinstallScripts` (module)
- `Shards::Docs::PublishingGuide` (module)
- `Shards::Docs::SBOMGeneration` (module)
- `Shards::Docs::ShardYmlFormat` (module)

