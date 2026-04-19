# class Shards::PostinstallInfo::Entry

Tracks the state of a single shard's postinstall script.

## Constructors

### `new(script_hash : String, has_run : Bool = false)`

## Instance Methods

### `has_run`

Whether the script has been executed.

### `has_run=(has_run : Bool)`

Whether the script has been executed.

### `script_hash`

SHA-256 hash of the postinstall command string.

### `script_hash=(script_hash : String)`

SHA-256 hash of the postinstall command string.

