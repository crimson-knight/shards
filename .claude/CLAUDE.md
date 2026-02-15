# Shards-Alpha Project Context

Shards-alpha is the Crystal language package manager extended with supply-chain compliance tools. It is a drop-in replacement for the upstream `shards` binary, adding security auditing, license compliance, dependency policy enforcement, SBOM generation, change tracking, and a unified compliance reporting system suitable for SOC2 and ISO 27001 audits.

## Key Commands

| Command | Description |
|---------|-------------|
| `shards-alpha install` | Install dependencies from shard.yml, creating or using shard.lock |
| `shards-alpha update [shards...]` | Update dependencies and shard.lock |
| `shards-alpha build [targets] [opts]` | Build targets defined in shard.yml |
| `shards-alpha audit [options]` | Scan dependencies for known vulnerabilities (OSV database) |
| `shards-alpha licenses [options]` | List dependency licenses, check SPDX compliance |
| `shards-alpha policy [check\|init\|show]` | Manage and enforce dependency policies |
| `shards-alpha diff [options]` | Show dependency changes between lockfile states |
| `shards-alpha compliance-report [options]` | Generate unified supply-chain compliance report |
| `shards-alpha sbom [options]` | Generate Software Bill of Materials (SPDX or CycloneDX) |
| `shards-alpha mcp-server [options]` | Start MCP compliance server for AI agent integration |
| `shards-alpha assistant [init\|update\|status\|remove]` | Manage Claude Code assistant configuration (skills, agents, settings) |

## Build

```sh
crystal build src/shards.cr -o bin/shards-alpha
```

## Test

```sh
# Unit tests
crystal spec spec/unit/

# Integration tests
crystal spec spec/integration/

# Single test file
crystal spec spec/unit/audit_spec.cr
```

## Format

```sh
crystal tool format src/ spec/
```

## Key Directories

| Directory | Contents |
|-----------|----------|
| `src/` | Main source files (dependency, lock, config, etc.) |
| `src/commands/` | CLI command implementations (audit, licenses, policy, etc.) |
| `src/mcp/` | MCP compliance server implementation |
| `src/assistant_versions/` | Versioned assistant config files (embedded at compile time) |
| `src/compliance/` | Compliance report generation internals |
| `spec/unit/` | Unit tests |
| `spec/integration/` | Integration tests |
| `docs/` | Documentation (compliance guide, plans) |

## Configuration Files

| File | Purpose |
|------|---------|
| `shard.yml` | Project dependency specification |
| `shard.lock` | Locked dependency versions with SHA-256 checksums |
| `.shards-policy.yml` | Dependency policy rules (allowed hosts, blocked deps, etc.) |
| `.shards-audit-ignore` | Suppressed vulnerability advisory IDs with expiry dates |
| `.mcp.json` | MCP server configuration for Claude Code integration |
| `.claude/.assistant-config.yml` | Assistant config tracking (version, components, checksums) |

## MCP Compliance Server

The MCP server (`src/mcp/compliance_server.cr`) exposes 6 compliance tools over JSON-RPC 2.0 (stdio transport): `audit`, `licenses`, `policy_check`, `diff`, `compliance_report`, and `sbom`. It supports MCP protocol version negotiation across versions 2024-11-05, 2025-03-26, 2025-06-18, and 2025-11-25. The server negotiates the highest version both client and server support.

Start the server:
```sh
shards-alpha mcp-server              # stdio mode
shards-alpha mcp-server --interactive # manual testing
shards-alpha mcp-server init          # add to .mcp.json
```

## Assistant Configuration

The `assistant` command (`src/commands/assistant.cr`) manages Claude Code skills, agents, and settings. File contents are embedded at compile time from `src/assistant_versions/` via `{{ run() }}` macro.

Key files:
- `src/assistant_versions.cr` — Version overlay logic (compile-time embedded)
- `src/build_assistant_versions.cr` — Compile-time script that walks version directories
- `src/assistant_config.cr` — Install/update/remove logic with modification detection
- `src/assistant_config_info.cr` — Tracking YAML class (`.claude/.assistant-config.yml`)

To add a new version: create `src/assistant_versions/<version>/` with only changed files. The binary picks them up at compile time.

```sh
shards-alpha assistant init                # Install all components
shards-alpha assistant init --no-agents    # Skip agents
shards-alpha assistant update              # Upgrade, preserve local edits
shards-alpha assistant status              # Show installed version and state
shards-alpha assistant remove              # Remove tracked files
```

Projects can auto-install via `shard.yml`:
```yaml
ai_assistant:
  auto_install: true
```

## Language and Style

- Written in Crystal (https://crystal-lang.org)
- All source must pass `crystal tool format`
- Specs use Crystal's built-in `spec` framework
- Error handling uses `Shards::Error` and `Shards::ParseError`
- CLI option parsing is in `src/cli.cr`; each command is a class in `src/commands/`
