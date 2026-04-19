# enum Shards::Severity

Severity levels with ordering support.

## Constants

- `Unknown` = `0`
- `Low` = `1`
- `Medium` = `2`
- `High` = `3`
- `Critical` = `4`

## Constructors

### `parse(str : String) : Severity`

## Instance Methods

### `at_or_above?(threshold : Severity) : Bool`

Returns true if this severity is at or above the given threshold.

### `critical?`

Returns `true` if this enum value equals `Critical`

### `high?`

Returns `true` if this enum value equals `High`

### `low?`

Returns `true` if this enum value equals `Low`

### `medium?`

Returns `true` if this enum value equals `Medium`

### `unknown?`

Returns `true` if this enum value equals `Unknown`

