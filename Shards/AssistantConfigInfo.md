# class Shards::AssistantConfigInfo

Tracks the installed assistant configuration state.

Persisted at `.claude/.assistant-config.yml`, this tracker stores
which version is installed, which components are enabled, and
per-file checksums for detecting user modifications during upgrades.

## Constants

- `CURRENT_VERSION` = `"1.0"`
- `FILENAME` = `".assistant-config.yml"`

## Constructors

### `new(path : String)`

## Instance Methods

### `assistant`

### `assistant=(assistant : String)`

### `components`

### `components=(components : Hash(String, Bool))`

### `files`

### `files=(files : Hash(String, String))`

### `installed?`

### `installed_at`

### `installed_at=(installed_at : String)`

### `installed_version`

### `installed_version=(installed_version : String)`

### `load`

### `path`

### `save`

