# module Shards::Checksum

## Constants

- `ALGORITHM_PREFIX` = `"sha256"`
- `EXCLUDED_DIRS` = `{".git", ".hg", ".fossil", ".fslckout", "_FOSSIL_"}`

## Class Methods

### `compute(path : String) : String`

Compute a deterministic SHA-256 checksum for a directory of source files.
Returns a string like "sha256:abcdef1234..."

### `verify(path : String, expected : String) : Bool`

Verify a checksum against a directory.
Returns true if match, false if mismatch.

