# Shards

[![CI](https://github.com/crystal-lang/shards/workflows/CI/badge.svg)](https://github.com/crystal-lang/shards/actions?query=workflow%3ACI+event%3Apush+branch%3Amaster)

Dependency manager for the [Crystal language](https://crystal-lang.org).

## Usage

Crystal applications and libraries are expected to have a `shard.yml` file
at their root looking like this:

```yaml
name: shards
version: 0.1.0

dependencies:
  openssl:
    github: datanoise/openssl.cr
    branch: master

development_dependencies:
  minitest:
    git: https://github.com/ysbaddaden/minitest.cr.git
    version: ~> 0.3.1

license: MIT
```

When libraries are installed from Git repositories, the repository is expected
to have version tags following a [semver](http://semver.org/)-like format,
prefixed with a `v`. Examples: `v1.2.3`, `v2.0.0-rc1` or `v2017.04.1`.

Please see the [SPEC](docs/shard.yml.adoc) for more details about the
`shard.yml` format.


## Install

Shards is usually distributed with Crystal itself (e.g. Homebrew and Debian
packages). Alternatively, a `shards` package may be available for your system.

You can download a source tarball from the same page (or clone the repository)
then run `make release=1`and copy `bin/shards` into your `PATH`. For
example `/usr/local/bin`.

You are now ready to create a `shard.yml` for your projects (see details in
[SPEC](docs/shard.yml.adoc)). You can type `shards init` to have an example
`shard.yml` file created for your project.

Run `shards install` to install your dependencies, which will lock your
dependencies into a `shard.lock` file. You should check both `shard.yml` and
`shard.lock` into version control, so further `shards install` will always
install locked versions, achieving reproducible installations across computers.

Run `shards --help` to list other commands with their options.

Happy Hacking!

## Shards-Alpha Features

Shards-alpha extends the standard Crystal dependency manager with features
for AI-assisted development. It distributes AI documentation and MCP server
configurations alongside library code, so consuming projects get everything
they need from `shards install`.

### AI Documentation Distribution

Shard authors can ship AI context files (`CLAUDE.md`, skills, agents,
commands) that are automatically installed into the consumer's `.claude/`
directory with shard-namespaced paths.

```sh
shards install          # AI docs are installed alongside dependencies
shards ai-docs          # Check status of installed AI documentation
```

Auto-detected locations in each dependency:

| Shard path | Installed as |
|---|---|
| `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
| `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
| `.claude/commands/<name>.md` | `.claude/commands/<shard>:<name>.md` |
| `CLAUDE.md` | `.claude/skills/<shard>--docs/SKILL.md` |
| `.mcp.json` | Merged into `.mcp-shards.json` |

### MCP Server Distribution & Lifecycle

Shards that ship `.mcp.json` files have their MCP server configurations
merged into a project-level `.mcp-shards.json` during install. Server
names are namespaced as `<shard>/<server>` and paths are rewritten
automatically.

```sh
shards mcp              # Show server status
shards mcp start        # Start all MCP servers
shards mcp stop         # Stop all MCP servers
shards mcp restart      # Restart servers
shards mcp logs <name>  # Tail server logs
```

### Postinstall Script Tracking

Postinstall scripts are tracked by content hash. Changed scripts emit a
warning instead of running automatically, requiring explicit approval:

```sh
shards run-script              # Run all pending postinstall scripts
shards run-script <shard>      # Run for a specific shard
```

### SBOM Generation

Generate a Software Bill of Materials for your project's dependency tree:

```sh
shards sbom                      # SPDX 2.3 JSON (default)
shards sbom --format=cyclonedx   # CycloneDX 1.6 JSON
```

### Documentation Generation

Generate Crystal API documentation with optional theming:

```sh
shards docs
```

### For Shard Authors

To distribute AI docs and MCP servers with your shard, add any of:

- `CLAUDE.md` — General AI context for your library
- `.claude/skills/<name>/SKILL.md` — Specific AI workflows
- `.mcp.json` — MCP server configurations
- `ai_docs` section in `shard.yml` — Fine-grained include/exclude control

See [`examples/`](examples/) for a complete walkthrough with a working
demo project.

### Claude Code Assistant Setup

Set up Claude Code with compliance skills, agents, and settings for your
project in one command:

```sh
shards-alpha assistant init       # Install skills, agents, settings, and MCP config
```

This creates:

| What | Files |
|------|-------|
| **Skills** (6) | `/audit`, `/licenses`, `/policy-check`, `/diff-deps`, `/compliance-report`, `/sbom` |
| **Agents** (2) | `compliance-checker`, `security-reviewer` |
| **Settings** | `.claude/settings.json` (pre-approved compliance commands) |
| **Context** | `.claude/CLAUDE.md` (project overview for Claude) |
| **MCP server** | `.mcp.json` entry for the compliance MCP server |

A tracking file (`.claude/.assistant-config.yml`) records the installed
version, enabled components, and per-file checksums so upgrades can
detect and preserve your local modifications.

#### Managing the assistant config

```sh
shards-alpha assistant status     # Show version, components, modified files
shards-alpha assistant update     # Upgrade to latest (preserves local edits)
shards-alpha assistant update --dry-run  # Preview what would change
shards-alpha assistant remove     # Remove all tracked files
```

#### Selective installation

Skip components you don't need:

```sh
shards-alpha assistant init --no-agents    # Skip agent definitions
shards-alpha assistant init --no-mcp       # Skip .mcp.json configuration
shards-alpha assistant init --no-skills    # Skip skill files
shards-alpha assistant init --no-settings  # Skip settings.json and CLAUDE.md
```

#### Automatic setup via shard.yml

Projects can opt in to automatic assistant configuration during
`shards install` by adding an `ai_assistant` section to `shard.yml`:

```yaml
ai_assistant:
  auto_install: true
```

When enabled, `shards install` will:
- Run `assistant init` if no assistant config exists
- Run `assistant update` if the installed version is older than the binary

Skip auto-configuration with `--skip-ai-assistant`.

#### Upgrading from `mcp-server init`

If you previously used `shards-alpha mcp-server init` to set up skills
and agents, running `assistant init` will detect the existing files,
adopt them into the tracking system, and create any missing files. Your
local modifications are preserved.

## Supply Chain Compliance

Shards-alpha includes a suite of supply chain security tools designed for
SOC2 and ISO 27001 compliance. These commands can be used individually or
combined into a unified compliance report.

For detailed usage, examples, and CI/CD integration patterns, see the
[Compliance Guide](docs/compliance-guide.md).

### Vulnerability Audit

Scan locked dependencies against the [OSV](https://osv.dev/) vulnerability
database:

```sh
shards audit                        # Colored terminal output
shards audit --format=json          # Machine-readable JSON
shards audit --format=sarif         # SARIF 2.1.0 for GitHub Code Scanning
shards audit --severity=high        # Only show high/critical
shards audit --fail-above=critical  # Exit 1 only for critical vulns
shards audit --ignore=GHSA-xxxx    # Suppress specific advisories
shards audit --offline              # Use cached data only
```

Suppressions can be managed in `.shards-audit-ignore`:

```yaml
- id: GHSA-xxxx-yyyy-zzzz
  reason: "Not applicable: we don't use the affected code path"
  expires: 2026-06-01
```

### Integrity Verification

Every `shards install` and `shards update` records SHA-256 checksums in
`shard.lock`. Subsequent installs verify that installed files match.

```sh
shards install              # Checksums computed and verified automatically
shards install --skip-verify # Bypass verification (logs a warning)
```

Tampered dependencies produce a clear error:

```
E: Checksum mismatch for web: expected sha256:abc123... got sha256:def456...
```

### License Compliance

List licenses for all locked dependencies with optional policy enforcement:

```sh
shards licenses                     # Colored table
shards licenses --format=json       # Machine-readable JSON
shards licenses --format=csv        # CSV export
shards licenses --format=markdown   # Markdown table
shards licenses --detect            # Heuristic detection from LICENSE files
shards licenses --check             # Exit 1 on policy violations
shards licenses --policy=path.yml   # Use custom license policy
```

### Dependency Policy

Define and enforce rules about what dependencies are allowed in your
project. Create a `.shards-policy.yml` file:

```sh
shards policy init    # Create a starter policy file
shards policy check   # Check dependencies against policy
shards policy show    # Display current policy summary
```

Policy rules include source host restrictions, blocked dependencies,
minimum version requirements, and postinstall script controls. Policies
are automatically enforced during `shards install` and `shards update`
when a `.shards-policy.yml` file is present.

### Change Audit Trail

Compare dependency states between lockfile versions:

```sh
shards diff                              # Compare HEAD vs current shard.lock
shards diff --from=HEAD --to=current     # Same as above (explicit)
shards diff --from=v1.0.0                # Compare against a git tag
shards diff --from=old.lock              # Compare against a saved lockfile
shards diff --format=json                # Machine-readable output
shards diff --format=markdown            # Markdown table for PR descriptions
```

An audit log is automatically maintained at `.shards/audit/changelog.json`
with timestamped entries for every `install` and `update` that modifies
the lock file.

### Compliance Report

Generate a unified report combining all compliance data into a single
document suitable for auditors:

```sh
shards compliance-report                         # JSON (default)
shards compliance-report --format=html           # Professional HTML report
shards compliance-report --format=markdown       # Markdown report
shards compliance-report --output=report.json    # Custom output path
shards compliance-report --sections=sbom,integrity # Only specific sections
shards compliance-report --reviewer=security@co.com # Add attestation
```

The report aggregates SBOM data, vulnerability findings, license inventory,
policy compliance status, integrity verification, and change history into a
single document with an executive summary and overall pass/fail status.
Reports are automatically archived to `.shards/audit/reports/`.

## Developers

### Requirements

These requirements are only necessary for compiling Shards.

* Crystal

  Please refer to <https://crystal-lang.org/install/> for
  instructions for your operating system.

* libyaml

  On Debian/Ubuntu Linux you may install the `libyaml-dev` package.

  On Mac OS X you may install it using homebrew with `brew install libyaml`
  then make sure to have `/usr/local/lib` in your `LIBRARY_PATH` environment
  variable (eg: `export LIBRARY_PATH="/usr/local/lib:$LIBRARY_PATH"`).
  Please adjust the path per your Homebrew installation.

* [asciidoctor](https://asciidoctor.org/)

  Needed for building manpages.

### Getting started

It is strongly recommended to use `make` for building shards and developing it.
The [`Makefile`](./Makefile) contains recipes for compiling and testing.

Run `make bin/shards` to build the binary.
* `release=1` for a release build (applies optimizations)
* `static=1` for static linking (only works with musl-libc)
* `debug=1` for full symbolic debug info

Run `make install` to install the binary. Target path can be adjusted with `PREFIX` (default: `PREFIX=/usr/bin`).

Run `make test` to run the test suites:
* `make test_unit` runs unit tests (`./spec/unit`)
* `make test_integration` runs integration tests (`./spec/integration`) on `bin/shards`

Run `make docs` to build the manpages.

### Devenv

This repository contains a configuration for [devenv.sh](https://devenv.sh) which
makes it easy to setup a reproducible environment with all necessary tools for
building and testing.

- Checkout the repository
- Run `devenv shell` to get a shell with development environment

A hook for [automatic shell activation](https://devenv.sh/automatic-shell-activation/)
is also included. If you have `direnv` installed, the devenv environment loads
automatically upon entering the repo folder.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](./LICENSE) for
details.
