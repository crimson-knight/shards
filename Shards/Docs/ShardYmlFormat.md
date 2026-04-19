# module Shards::Docs::ShardYmlFormat

## shard.yml Format

### Required fields

```yaml
name: my_shard
version: 1.0.0
```

### Dependencies

```yaml
dependencies:
  kemal:
    github: kemalcr/kemal
    version: ~> 1.0
  local_dep:
    path: ../local_dep

development_dependencies:
  ameba:
    github: crystal-ameba/ameba
```

### Dependency sources

| Key | Description |
|---|---|
| `github: user/repo` | GitHub repository |
| `gitlab: user/repo` | GitLab repository |
| `bitbucket: user/repo` | Bitbucket repository |
| `git: <url>` | Any git URL |
| `hg: <url>` | Mercurial |
| `fossil: <url>` | Fossil |
| `path: <path>` | Local path |

### Version constraints

| Pattern | Meaning |
|---|---|
| `*` | Any version |
| `1.0.0` | Exact version |
| `>= 1.0.0` | Minimum version |
| `~> 1.0` | >= 1.0.0, < 2.0.0 |
| `~> 1.0.3` | >= 1.0.3, < 1.1.0 |

### Build targets

```yaml
targets:
  my_app:
    main: src/my_app.cr
```

### Scripts

```yaml
scripts:
  postinstall: make ext
```

### AI documentation (optional)

```yaml
ai_docs:
  include:
    - docs/claude/custom_guide.md
  exclude:
    - .claude/skills/internal_dev_tool/
```

See `Spec`, `Spec::AIDocs`, `Dependency`.

