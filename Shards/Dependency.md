# class Shards::Dependency

## Constructors

### `new(name : String, resolver : Resolver, requirement : Requirement = Any)`

## Class Methods

### `from_yaml(pull : YAML::PullParser)`

## Instance Methods

### `==(other : self)`

Returns `true` if this reference is the same as *other*. Invokes `same?`.

### `as_package?`

### `checksum`

### `checksum=(checksum : String | Nil)`

### `matches?(version : Version)`

### `name`

### `name=(name : String)`

### `prerelease?`

### `requirement`

### `requirement=(requirement : Requirement)`

### `resolver`

### `resolver=(resolver : Resolver)`

### `to_s(io)`

### `to_yaml(yaml : YAML::Builder)`

