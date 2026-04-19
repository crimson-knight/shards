# class Shards::HgResolver

## Class Methods

### `key`

### `normalize_key_source(key : String, source : String) : Tuple(String, String)`

## Instance Methods

### `available_releases`

### `commit_sha1_at(ref : HgRef)`

### `hg_url`

### `install_sources(version : Version, install_path : String)`

### `latest_version_for_ref(ref : HgRef | Nil) : Version`

### `local_path`

### `matches_ref?(ref : HgRef, version : Version)`

### `parse_requirement(params : Hash(String, String)) : Requirement`

### `read_spec(version : Version) : String | Nil`

### `report_version(version : Version) : String`

### `update_local_cache`

## Types

- `Shards::HgResolver::HgVersion` (struct)

