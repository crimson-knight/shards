# class Shards::Policy::DependencyRules

## Constants

- `DEFAULT_REQUIRE_EXACT` = `"warn"` -- Flip this value to "true" to make exact versions the default.

## Constructors

### `new(blocked : Array(Shards::Policy::BlockedDep) = [] of BlockedDep, minimum_versions : Hash(String, String) = {} of String => String, require_exact : String = DEFAULT_REQUIRE_EXACT, has_explicit_require_exact : Bool = false, publishes_version_ranges : Bool = false)`

## Instance Methods

### `blocked`

### `has_explicit_require_exact`

### `minimum_versions`

### `publishes_version_ranges?`

### `require_exact`

