# class Shards::Policy

## Constants

- `CURRENT_VERSION` = `"1"`

## Constructors

### `from_file(path : String) : self`

### `from_yaml(input : String, filename = POLICY_FILENAME) : self`

### `new(pull : YAML::PullParser)`

### `new(version : String = CURRENT_VERSION, sources : Shards::Policy::SourceRules = SourceRules.new, dependencies : Shards::Policy::DependencyRules = DependencyRules.new, freshness : Shards::Policy::FreshnessRules = FreshnessRules.new, security : Shards::Policy::SecurityRules = SecurityRules.new, custom : Array(Shards::Policy::CustomRule) = [] of CustomRule)`

## Instance Methods

### `custom`

### `dependencies`

### `freshness`

### `security`

### `sources`

### `version`

## Types

- `Shards::Policy::BlockedDep` (class)
- `Shards::Policy::CustomRule` (class)
- `Shards::Policy::DependencyRules` (class)
- `Shards::Policy::FreshnessRules` (class)
- `Shards::Policy::SecurityRules` (class)
- `Shards::Policy::SourceRules` (class)

