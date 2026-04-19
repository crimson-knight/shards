# class Shards::Package

## Constructors

### `new(name : String, resolver : Shards::Resolver, version : Shards::Version, is_override : Bool = false, checksum : String | Nil = nil)`

## Instance Methods

### `==(other : self)`

Returns `true` if this reference is the same as *other*. Invokes `same?`.

### `checksum`

### `checksum=(checksum : String | Nil)`

### `compute_checksum`

### `find_executable_file(install_path, name)`

### `install`

### `install_executables`

### `install_path`

### `installed?`

### `is_override`

### `name`

### `postinstall`

### `report_version`

### `resolver`

### `run_script(name, skip)`

### `spec`

### `to_s(io)`

### `to_yaml(builder)`

### `version`

