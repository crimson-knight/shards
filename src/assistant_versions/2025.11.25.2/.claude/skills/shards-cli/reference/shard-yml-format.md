# shard.yml Format Reference

## Required Fields

```yaml
name: my_shard          # Shard name
version: 1.0.0          # Semantic version
```

## Optional Fields

```yaml
description: My shard description
authors:
  - Author Name <email@example.com>
crystal: ">= 1.0.0, < 2.0.0"
license: MIT
repository: https://github.com/user/repo
```

## Dependencies

```yaml
dependencies:
  kemal:
    github: kemalcr/kemal
    version: ~> 1.0

  my_lib:
    git: https://example.com/repo.git
    branch: main

  local_dep:
    path: ../local_dep

development_dependencies:
  ameba:
    github: crystal-ameba/ameba
```

### Dependency Sources

| Key | Description |
|-----|-------------|
| `github: user/repo` | GitHub repository |
| `gitlab: user/repo` | GitLab repository |
| `bitbucket: user/repo` | Bitbucket repository |
| `git: <url>` | Any git repository URL |
| `path: <path>` | Local path dependency |

### Version Constraints

| Pattern | Meaning |
|---------|---------|
| `~> 1.0` | >= 1.0.0, < 2.0.0 |
| `~> 1.0.3` | >= 1.0.3, < 1.1.0 |
| `>= 1.0, < 2.0` | Range |
| `1.0.0` | Exact version |

## Build Targets

```yaml
targets:
  my_app:
    main: src/my_app.cr
```

## Scripts

```yaml
scripts:
  postinstall: make ext
```

## AI Assistant

Auto-install Claude Code skills, agents, and settings during `shards install`:

```yaml
ai_assistant:
  auto_install: true
```

When enabled, `shards install` runs `assistant init` (if not yet configured)
or `assistant update` (if an older version is installed). Skip with
`--skip-ai-assistant`.
