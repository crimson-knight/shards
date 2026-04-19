# class Shards::Spec::AIDocs

Optional `ai_docs` section in `shard.yml` for customizing AI documentation
distribution. When absent, auto-detection handles standard locations.

```yaml
ai_docs:
  include:
    - docs/claude/custom_guide.md
  exclude:
    - .claude/skills/internal_dev_tool/
```

## Constructors

### `new(pull : YAML::PullParser)`

### `new(include __arg1 : Array(String) = [] of String, exclude : Array(String) = [] of String)`

## Instance Methods

### `exclude`

Paths to exclude from auto-detected AI docs.

### `include`

Extra files to include beyond auto-detected locations.

