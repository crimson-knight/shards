# shard.yml Format Reference

## Required Fields

```yaml
name: my_shard          # Shard name (must match repo name convention)
version: 1.0.0          # Semantic version
```

## Optional Fields

```yaml
description: |
  Multi-line description of the shard.

authors:
  - Author Name <email@example.com>

crystal: ">= 1.0.0, < 2.0.0"    # Crystal version constraint
license: MIT

repository: https://github.com/user/repo
documentation: https://user.github.io/repo
```

## Dependencies

```yaml
dependencies:
  kemal:
    github: kemalcr/kemal
    version: ~> 1.0       # >= 1.0.0, < 2.0.0

  my_lib:
    git: https://example.com/repo.git
    branch: main

  local_dep:
    path: ../local_dep

development_dependencies:
  ameba:
    github: crystal-ameba/ameba
    version: ~> 1.5
```

### Dependency Sources

| Key | Description |
|-----|-------------|
| `github: user/repo` | GitHub repository |
| `gitlab: user/repo` | GitLab repository |
| `bitbucket: user/repo` | Bitbucket repository |
| `git: <url>` | Any git repository URL |
| `hg: <url>` | Mercurial repository |
| `fossil: <url>` | Fossil repository |
| `path: <path>` | Local path dependency |

### Version Constraints

| Pattern | Meaning |
|---------|---------|
| `*` | Any version |
| `1.0.0` | Exact version |
| `>= 1.0.0` | Minimum version |
| `~> 1.0` | >= 1.0.0, < 2.0.0 |
| `~> 1.0.3` | >= 1.0.3, < 1.1.0 |
| `>= 1.0, < 2.0` | Range |

### Branch/Tag Refs

```yaml
dependencies:
  my_shard:
    github: user/repo
    branch: develop       # Track a branch
    # or
    tag: v1.0.0           # Pin to a tag
    # or
    commit: abc123        # Pin to a commit
```

## Build Targets

```yaml
targets:
  my_app:
    main: src/my_app.cr
  cli_tool:
    main: src/cli.cr
```

## Executables

```yaml
executables:
  - my_app
  - cli_tool
```

Executables are installed from `bin/` in the shard directory.

## Libraries (C bindings)

```yaml
libraries:
  libsqlite3: ">= 3.0.0"
  libpcre2-8: "*"
```

## Scripts

```yaml
scripts:
  postinstall: make ext
```

Postinstall scripts run after first installation. Changed scripts require `shards run-script <name>` to re-execute.

## AI Documentation (optional)

```yaml
ai_docs:
  include:                      # Extra files beyond auto-detected
    - docs/claude/custom_guide.md
  exclude:                      # Skip specific auto-detected files
    - .claude/skills/internal_dev_tool/
```

The `ai_docs` section is optional. By default, shards auto-detects:
- `.claude/skills/` directories
- `.claude/agents/` files
- `.claude/commands/` files
- `CLAUDE.md` at shard root
- `AGENTS.md` at shard root
- `.mcp.json` at shard root
