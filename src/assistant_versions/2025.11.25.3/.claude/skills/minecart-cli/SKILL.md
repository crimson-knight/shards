---
name: minecart-cli
description: Minecart package manager CLI reference. Provides guidance on shard.yml format, dependency management, installation, building, and AI docs distribution.
user-invocable: false
---

# Minecart CLI

Minecart is a drop-in compatible fork of the stock Crystal `shards`
dependency manager. It reads `shard.yml` to resolve, install, and update
dependencies from source repositories.

## Common Workflows

### Install dependencies
```
minecart install                  # Install from shard.yml, using shard.lock if present
minecart install --production     # Frozen + without development dependencies
minecart install --skip-ai-docs   # Skip AI documentation installation
```

### Update dependencies
```
minecart update                   # Update all to latest compatible versions
minecart update kemal             # Update only kemal
```

### Build targets
```
minecart build                    # Build all targets
minecart build my_app             # Build specific target
minecart build --release          # Build with --release flag
```

### Supply chain compliance
```
minecart audit                    # Vulnerability scan
minecart licenses                 # License compliance
minecart policy check             # Policy enforcement
minecart diff                     # Dependency changes
minecart compliance-report        # Full compliance report
minecart sbom                     # Software Bill of Materials
```

### Other commands
```
minecart check                    # Verify all dependencies are installed
minecart list                     # List installed dependencies
minecart list --tree              # List with dependency tree
minecart outdated                 # Show outdated dependencies
minecart prune                    # Remove unused dependencies from lib/
minecart version                  # Print shard version
minecart init                     # Generate a new shard.yml
```

## Key Flags

| Flag | Description |
|------|-------------|
| `--frozen` | Strictly install locked versions from shard.lock |
| `--without-development` | Skip development dependencies |
| `--production` | Same as `--frozen --without-development` |
| `--skip-postinstall` | Skip postinstall scripts |
| `--skip-ai-docs` | Skip AI documentation installation |
| `--jobs=N` | Parallel downloads (default: 8) |

## Reference

- [shard.yml format](reference/shard-yml-format.md)
- [All CLI commands](reference/commands.md)
- [AI docs distribution guide](reference/ai-docs-guide.md)