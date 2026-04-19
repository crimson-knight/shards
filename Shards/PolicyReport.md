# class Shards::PolicyReport

## Constructors

### `new`

## Instance Methods

### `add_violation(package : String, rule : String, severity : Severity, message : String)`

### `clean?`

### `errors`

### `exit_code(strict : Bool = false) : Int32`

### `has_errors?`

### `has_warnings?`

### `to_json_output(io : IO)`

### `to_terminal(io : IO, colors : Bool = Shards.colors?)`

### `violations`

### `warnings`

## Types

- `Shards::PolicyReport::Severity` (enum)
- `Shards::PolicyReport::Violation` (struct)

