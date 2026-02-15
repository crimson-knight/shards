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

### Supply chain compliance
```
shards audit                    # Vulnerability scan
shards licenses                 # License compliance
shards policy check             # Policy enforcement
shards diff                     # Dependency changes
shards compliance-report        # Full compliance report
shards sbom                     # Software Bill of Materials
```

### Claude Code assistant
```
shards assistant init           # Install skills, agents, settings
shards assistant status         # Show version and state
shards assistant update         # Upgrade to latest version
shards assistant remove         # Remove tracked files
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
```

## Key Flags

| Flag | Description |
|------|-------------|
| `--frozen` | Strictly install locked versions from shard.lock |
| `--without-development` | Skip development dependencies |
| `--production` | Same as `--frozen --without-development` |
| `--skip-postinstall` | Skip postinstall scripts |
| `--skip-ai-docs` | Skip AI documentation installation |
| `--skip-ai-assistant` | Skip AI assistant auto-configuration |
| `--jobs=N` | Parallel downloads (default: 8) |

## Reference

- [shard.yml format](reference/shard-yml-format.md)
- [All CLI commands](reference/commands.md)
- [AI docs distribution guide](reference/ai-docs-guide.md)
