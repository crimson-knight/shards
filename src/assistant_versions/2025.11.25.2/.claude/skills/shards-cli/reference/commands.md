# Shards CLI Commands Reference

## shards install

Install dependencies from `shard.yml`. Creates `shard.lock` if it doesn't exist.

```
shards install [options]
```

## shards update

Update dependencies to latest compatible versions.

```
shards update [shard_names...] [options]
```

## shards build

Build targets defined in `shard.yml`.

```
shards build [targets...] [-- build_options...]
```

## shards check

Verify all dependencies are installed and match `shard.lock`.

## shards list

List installed dependencies.

```
shards list [--tree]
```

## shards lock

Lock dependencies without installing.

```
shards lock [--print] [--update [shards...]]
```

## shards outdated

Show outdated dependencies.

```
shards outdated [--pre]
```

## shards prune

Remove unused dependencies from `lib/`.

## shards init

Generate a new `shard.yml`.

## shards version

Print the shard version from `shard.yml`.

```
shards version [path]
```

## shards audit

Scan dependencies for known vulnerabilities via OSV database.

```
shards audit [--severity=LEVEL] [--format=FORMAT] [--fail-above=LEVEL] [--offline]
```

## shards licenses

List dependency licenses with SPDX validation.

```
shards licenses [--check] [--detect] [--format=FORMAT] [--include-dev]
```

## shards policy

Manage dependency policies.

```
shards policy check [--strict] [--format=FORMAT]
shards policy init
shards policy show
```

## shards diff

Show dependency changes between lockfile states.

```
shards diff [--from=REF] [--to=REF] [--format=FORMAT]
```

## shards compliance-report

Generate unified compliance report.

```
shards compliance-report [--format=FORMAT] [--sections=LIST] [--reviewer=EMAIL]
```

## shards sbom

Generate Software Bill of Materials.

```
shards sbom [--format=spdx|cyclonedx] [--output=FILE] [--include-dev]
```

## shards mcp-server

Start MCP compliance server for AI agent integration.

```
shards mcp-server              # Start stdio server
shards mcp-server --interactive # Interactive testing mode
shards mcp-server init          # Configure .mcp.json
shards mcp-server --help        # Show help
```

## shards assistant

Manage Claude Code assistant configuration (skills, agents, settings).

```
shards assistant init [options]   # Install skills, agents, settings, MCP config
shards assistant update [options] # Update to latest version
shards assistant status           # Show installed version and state
shards assistant remove           # Remove all tracked files
```

Options:
- `--no-mcp` — Skip MCP server configuration
- `--no-skills` — Skip skill files
- `--no-agents` — Skip agent definitions
- `--no-settings` — Skip settings.json and CLAUDE.md
- `--force` — Overwrite existing/modified files
- `--dry-run` — Preview changes without writing (update only)
