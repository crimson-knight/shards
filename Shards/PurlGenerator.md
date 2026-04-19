# module Shards::PurlGenerator

## Class Methods

### `generate(pkg : Package) : String | Nil`

Returns a Package URL (purl) string for the given package, or nil for
path dependencies that have no meaningful remote identity.

### `parse_owner_repo(source : String) : Tuple(String | Nil, String | Nil)`

Parses "owner/repo" from a git source URL.

