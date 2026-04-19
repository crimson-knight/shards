# class Shards::AIDocsInfo::FileEntry

Represents a single tracked file with dual checksums.

## Constructors

### `new(upstream_checksum : String, installed_checksum : String)`

## Instance Methods

### `installed_checksum`

### `installed_checksum=(installed_checksum : String)`

### `upstream_checksum`

### `upstream_checksum=(upstream_checksum : String)`

### `user_modified?`

Returns `true` if the installed file differs from the upstream version,
indicating the user has made local modifications.

