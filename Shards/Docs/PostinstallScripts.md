# module Shards::Docs::PostinstallScripts

## Postinstall Scripts

Shards supports postinstall scripts defined in `shard.yml`:

```yaml
scripts:
  postinstall: make ext
```

### Version-aware execution

Postinstall scripts use `PostinstallInfo` for tracking:

- **First install**: the script runs automatically, and its hash is recorded
- **Subsequent installs** (same script): skipped silently
- **Script changed**: a warning is emitted, the user must run
  `shards run-script <shard>` explicitly

This prevents unexpected re-execution of potentially destructive scripts
while still notifying users when scripts change.

### Manual execution

```
shards run - script          # run all pending scripts
shards run - script my_shard # run for specific shard
```

See `PostinstallInfo`, `Commands::RunScript`, `Package#postinstall`.

