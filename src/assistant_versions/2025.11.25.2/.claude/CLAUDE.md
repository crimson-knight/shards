# Shards-Alpha: Supply Chain Compliance for Crystal

This project uses shards-alpha, a Crystal package manager with built-in supply chain compliance tools.

## Available Commands

| Command | Description |
|---------|-------------|
| `shards-alpha install` | Install dependencies from shard.yml |
| `shards-alpha update` | Update dependencies to latest compatible versions |
| `shards-alpha audit` | Scan dependencies for known vulnerabilities (OSV database) |
| `shards-alpha licenses` | List dependency licenses with SPDX compliance checking |
| `shards-alpha policy check` | Check dependencies against policy rules |
| `shards-alpha diff` | Show dependency changes between lockfile states |
| `shards-alpha compliance-report` | Generate unified compliance report |
| `shards-alpha sbom` | Generate Software Bill of Materials (SPDX/CycloneDX) |
| `shards-alpha assistant status` | Show assistant config version and state |
| `shards-alpha assistant update` | Update skills, agents, and settings to latest |

## Quick Compliance Check

```sh
shards-alpha audit                    # Check for vulnerabilities
shards-alpha licenses --check         # Verify license compliance
shards-alpha policy check             # Enforce dependency policies
```

## Key Files

| File | Purpose |
|------|---------|
| `shard.yml` | Dependency specification |
| `shard.lock` | Locked dependency versions |
| `.shards-policy.yml` | Dependency policy rules (optional) |
| `.shards-audit-ignore` | Suppressed vulnerability IDs (optional) |

## MCP Compliance Server

An MCP server exposes all compliance tools for AI agent integration:

```sh
shards-alpha mcp-server              # Start stdio MCP server
shards-alpha mcp-server --interactive # Manual testing mode
```

Supports MCP protocol versions: 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05.
