# class Shards::Lock

## Constants

- `CURRENT_VERSION` = `"2.0"`

## Constructors

### `new(version : String, shards : Array(Package))`

## Class Methods

### `from_file(path)`

### `from_yaml(str)`

### `write(packages : Array(Package), override_path : String | Nil, path : String)`

### `write(packages : Array(Package), override_path : String | Nil, io : IO)`

## Instance Methods

### `shards`

### `shards=(shards : Array(Package))`

### `version`

### `version=(version : String)`

