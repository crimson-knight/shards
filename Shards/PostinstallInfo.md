# class Shards::PostinstallInfo

Tracks postinstall script execution state across installs.

Persisted at `lib/.shards.postinstall`, this tracker stores a hash of
each shard's postinstall command and whether it has been executed.

This enables version-aware postinstall behavior:
- First install: run the script, record its hash
- Subsequent installs with same script: skip silently
- Script changed: warn the user, require explicit `shards run-script`

## Constants

- `CURRENT_VERSION` = `"1.0"`

## Constructors

### `new(path : String)`

## Class Methods

### `hash_script(command : String) : String`

Computes a SHA-256 hash of a postinstall command string.

## Instance Methods

### `load`

Loads tracker state from the YAML file at `#path`.

### `path`

Absolute path to the `.shards.postinstall` file.

### `save`

Persists the current tracker state to the YAML file at `#path`.

### `shards`

Map of shard name to its postinstall entry.

## Types

- `Shards::PostinstallInfo::Entry` (class)

