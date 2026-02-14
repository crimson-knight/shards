---
name: shards-cli
description: Crystal Shards package manager CLI reference. Provides guidance on shard.yml format, dependency management, installation, building, and AI docs distribution.
user-invocable: false
---

# Crystal Shards CLI

Shards is the dependency manager for Crystal. It reads `shard.yml` to resolve, install, and update dependencies from source repositories.

## Common Workflows

### Install dependencies
```
shards install                  # Install from shard.yml, using shard.lock if present
shards install --production     # Frozen + without development dependencies
shards install --skip-ai-docs   # Skip AI documentation installation
```

### Update dependencies
```
shards update                   # Update all to latest compatible versions
shards update kemal             # Update only kemal
```

### Build targets
```
shards build                    # Build all targets
shards build my_app             # Build specific target
shards build --release          # Build with --release flag
```

### Other commands
```
shards check                    # Verify all dependencies are installed
shards list                     # List installed dependencies
shards list --tree              # List with dependency tree
shards outdated                 # Show outdated dependencies
shards prune                    # Remove unused dependencies from lib/
shards version                  # Print shard version
shards init                     # Generate a new shard.yml
shards lock                     # Lock dependencies without installing
```

### AI docs management
```
shards ai-docs                  # Show installed AI docs status
shards ai-docs diff <shard>     # Diff local changes vs upstream
shards ai-docs reset <shard>    # Reset to upstream version
shards ai-docs update [shard]   # Force re-install AI docs
shards ai-docs merge-mcp        # Merge shard MCP configs into .mcp.json
```

### Postinstall scripts
```
shards run-script               # Run all pending postinstall scripts
shards run-script <shard>       # Run postinstall for a specific shard
```

### Documentation generation
```
shards docs                     # Generate themed docs with AI buttons
shards docs --skip-ai-buttons   # Without AI assistant buttons
shards docs -o my_docs          # Custom output directory
```

Theme your docs by creating `docs-theme/style.css` with CSS variable overrides.

### SBOM generation
```
shards sbom                          # Generate SPDX 2.3 JSON (default)
shards sbom --format=cyclonedx       # Generate CycloneDX 1.6 JSON
shards sbom --output=custom.json     # Custom output path
shards sbom --include-dev            # Include development dependencies
```

## Key Flags

| Flag | Description |
|------|-------------|
| `--frozen` | Strictly install locked versions from shard.lock |
| `--without-development` | Skip development dependencies |
| `--production` | Same as `--frozen --without-development` |
| `--skip-postinstall` | Skip postinstall scripts |
| `--skip-executables` | Skip executable installation |
| `--skip-ai-docs` | Skip AI documentation installation |
| `--local` | Use local cache only, don't fetch |
| `--jobs=N` | Parallel downloads (default: 8) |

## Important Files

| File | Purpose |
|------|---------|
| `shard.yml` | Dependency specification |
| `shard.lock` | Locked dependency versions |
| `lib/` | Installed dependencies |
| `lib/.shards.info` | Installation state tracker |
| `.claude/.ai-docs-info.yml` | AI docs installation tracker |
| `.mcp-shards.json` | MCP servers from dependencies |
| `docs-theme/style.css` | Custom CSS theme for generated docs |

## Reference

- [shard.yml format](reference/shard-yml-format.md)
- [All CLI commands](reference/commands.md)
- [AI docs distribution guide](reference/ai-docs-guide.md)
