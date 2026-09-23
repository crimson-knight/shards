# Minecart CLI Commands Reference

## minecart install

Install dependencies from `shard.yml`. Creates `shard.lock` if it doesn't exist.

```
minecart install [options]
```

## minecart update

Update dependencies to latest compatible versions.

```
minecart update [shard_names...] [options]
```

## minecart build

Build targets defined in `shard.yml`.

```
minecart build [targets...] [-- build_options...]
```

## minecart check

Verify all dependencies are installed and match `shard.lock`.

## minecart list

List installed dependencies.

```
minecart list [--tree]
```

## minecart lock

Lock dependencies without installing.

```
minecart lock [--print] [--update [shards...]] [--rekey]
```

## minecart outdated

Show outdated dependencies.

```
minecart outdated [--pre]
```

## minecart prune

Remove unused dependencies from `lib/`.

## minecart init

Generate a new `shard.yml`.

## minecart version

Print the shard version from `shard.yml`.

```
minecart version [path]
```

## minecart audit

Scan dependencies for known vulnerabilities via OSV database.

```
minecart audit [--severity=LEVEL] [--format=FORMAT] [--fail-above=LEVEL] [--offline]
```

## minecart licenses

List dependency licenses with SPDX validation.

```
minecart licenses [--check] [--detect] [--format=FORMAT] [--include-dev]
```

## minecart policy

Manage dependency policies.

```
minecart policy check [--strict] [--format=FORMAT]
minecart policy init
minecart policy show
```

## minecart diff

Show dependency changes between lockfile states.

```
minecart diff [--from=REF] [--to=REF] [--format=FORMAT]
```

## minecart compliance-report

Generate unified compliance report.

```
minecart compliance-report [--format=FORMAT] [--sections=LIST] [--reviewer=EMAIL]
```

## minecart sbom

Generate Software Bill of Materials.

```
minecart sbom [--format=spdx|cyclonedx] [--output=FILE] [--include-dev]
```

## minecart mcp-server

Start MCP compliance server for AI agent integration.

```
minecart mcp-server              # Start stdio server
minecart mcp-server --interactive # Interactive testing mode
minecart mcp-server init          # Configure .mcp.json and .claude/
minecart mcp-server --help        # Show help
```