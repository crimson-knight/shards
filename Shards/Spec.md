# class Shards::Spec

## Constructors

### `new(name : String, version : Version, resolver : Resolver | Nil = nil)`

## Class Methods

### `from_file(path, validate = false)`

### `from_yaml(input, filename = SPEC_FILENAME, validate = false)`

## Instance Methods

### `ai_assistant`

### `ai_docs`

### `authors`

### `crystal`

### `dependencies`

### `description`

### `development_dependencies`

### `executables`

### `libraries`

### `license`

### `license_url`

### `mismatched_version?`

### `name`

### `name=(name : String)`

### `name?`

### `original_version`

### `original_version?`

### `read_from_yaml?`

### `resolver`

### `resolver=(resolver : Resolver | Nil)`

### `scripts`

### `targets`

### `to_s(io)`

### `version`

### `version=(version : Version)`

### `version?`

## Types

- `Shards::Spec::AIAssistant` (class)
- `Shards::Spec::AIDocs` (class)
- `Shards::Spec::Author` (class)
- `Shards::Spec::Library` (class)

