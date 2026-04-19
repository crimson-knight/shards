# class Shards::AIDocsInfo

Tracks installed AI documentation files and their checksums.

Persisted at `.claude/.ai-docs-info.yml`, this tracker enables
conflict detection during updates by storing two checksums per file:

- `upstream_checksum`: the checksum of the file as shipped by the shard
- `installed_checksum`: the checksum of the file as it exists on disk

When both match, the file is unmodified and safe to auto-update.
When they differ, the user has customized the file and it should
not be overwritten.

## Constants

- `CURRENT_VERSION` = `"1.0"`

## Constructors

### `new(path : String)`

## Class Methods

### `checksum(content : String) : String`

Computes a SHA-256 checksum for the given string content.

### `checksum_file(path : String) : String`

Computes a SHA-256 checksum for the file at the given path.

## Instance Methods

### `load`

Loads tracker state from the YAML file at `#path`.

### `path`

Absolute path to the `.ai-docs-info.yml` file.

### `save`

Persists the current tracker state to the YAML file at `#path`.

### `shards`

Map of shard name to its tracked entry.

## Types

- `Shards::AIDocsInfo::FileEntry` (class)
- `Shards::AIDocsInfo::ShardEntry` (class)

