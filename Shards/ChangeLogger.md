# class Shards::ChangeLogger

## Constants

- `AUDIT_DIR` = `".shards/audit"`
- `LOG_FILE` = `"changelog.json"`

## Class Methods

### `load(project_path : String) : Array(JSON::Any)`

### `record(project_path : String, action : String, old_packages : Array(Package), new_packages : Array(Package), lockfile_path : String) : Nil`

