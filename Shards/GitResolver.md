# class Shards::GitResolver

## Class Methods

### `key`

### `normalize_key_source(key : String, source : String) : Tuple(String, String)`

## Instance Methods

### `available_releases`

### `commit_sha1_at(ref : GitRef)`

### `git_url`

### `install_sources(version : Version, install_path : String)`

### `latest_version_for_ref(ref : GitRef | Nil) : Version`

### `local_path`

### `matches_ref?(ref : GitRef, version : Version)`

### `parse_requirement(params : Hash(String, String)) : Requirement`

### `read_spec(version : Version) : String | Nil`

### `report_version(version : Version) : String`

### `update_local_cache`

## Types

- `Shards::GitResolver::GitVersion` (struct)

