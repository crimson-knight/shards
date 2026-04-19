# Ashard

[![CI](https://github.com/crystal-lang/shards/workflows/CI/badge.svg)](https://github.com/crystal-lang/shards/actions?query=workflow%3ACI+event%3Apush+branch%3Amaster)

Ashard is the public name for this Shards-compatible fork of the
[Crystal language](https://crystal-lang.org) dependency manager.

The name is meant to read naturally as "a shard": tooling that wraps around a
shard, stays compatible with the `Shards` ecosystem, and adds the agent-first
workflows we want for Amber v2 and the broader amberverse. We may personify the
name more in the future as the Amber v2 tool family takes shape, but the
current promise is simple: Ashard should still feel like home to anyone who
already knows Shards.

## Usage

Crystal applications and libraries are expected to have a `shard.yml` file
at their root looking like this:

```yaml
name: amberverse_app
version: 0.1.0

dependencies:
  amber_support:
    path: vendors/amber_support

development_dependencies:
  ashard_spec:
    path: tools/ashard_spec

license: MIT
```

When libraries are installed from Git repositories, the repository is expected
to have version tags following a [semver](http://semver.org/)-like format,
prefixed with a `v`. Examples: `v1.2.3`, `v2.0.0-rc1` or `v2017.04.1`.

Please see the [SPEC](docs/shard.yml.adoc) for more details about the
`shard.yml` format.


## Install

Upstream Shards is usually distributed with Crystal itself. This fork is
currently distributed as `shards-alpha` while the public product name remains
**Ashard**.

You can download a source tarball from the same page (or clone the repository)
then run `make release=1`and copy `bin/shards-alpha` into your `PATH`. For
example `/usr/local/bin`.

You are now ready to create a `shard.yml` for your projects (see details in
[SPEC](docs/shard.yml.adoc)). You can type `shards-alpha init` to have an example
`shard.yml` file created for your project.

Run `shards-alpha install` to install your dependencies, which will lock your
dependencies into a `shard.lock` file. You should check both `shard.yml` and
`shard.lock` into version control, so further `shards-alpha install` will always
install locked versions, achieving reproducible installations across computers.

Run `shards-alpha --help` to list other commands with their options.

Happy Hacking!

## Public Name

The public name for this additive fork is **Ashard**.

For the current release-candidate period, the shipped binary and package names
remain `shards-alpha` so existing installs and automation keep working. The
product story we should publish is:

- **Ashard** is the public project name
- **`shards-alpha`** is the current compatibility-preserving binary/package name

More specifically:

- **Ashard** is intended to read as "a shard" in ordinary English
- The name signals tooling that sits around a shard instead of replacing the
  shard ecosystem with a separate one
- The codebase still exposes the `Shards` namespace because compatibility is
  the contract
- Over time we may personify the name more, alongside the rest of the Amber v2
  tooling family, for people building inside the amberverse

For the docs publishing story, see
[docs/crystal-docs-gap-analysis.md](docs/crystal-docs-gap-analysis.md). It
explains what Crystal Docs already provides and what Ashard adds on top.

## Compatibility Promise

This repository has two operating modes:

- `master` mirrors upstream `crystal-lang/shards`
- `alpha` carries additive tooling currently distributed as `shards-alpha`

The goal is not to replace core Shards behavior. The goal is to stay
compatible with normal `shards` dependency-management workflows while layering
additional tooling on top.

We now validate that promise against `amber_cli` before treating upstream syncs
or release-facing changes as safe. See
[docs/upstream-compatibility.md](docs/upstream-compatibility.md) for the local
and CI workflow, including `make compatibility`.

## Ashard Features

Ashard currently ships as the `shards-alpha` binary and extends the standard
Crystal dependency manager with features
for AI-assisted development. It distributes AI documentation and MCP server
configurations alongside library code, so consuming projects get everything
they need from `shards-alpha install`.

### AI Documentation Distribution

Shard authors can ship AI context files (`CLAUDE.md`, skills, agents,
commands) that are automatically installed into the consumer's `.claude/`
directory with shard-namespaced paths.

```sh
shards-alpha install          # AI docs are installed alongside dependencies
shards-alpha ai-docs          # Check status of installed AI documentation
```

Auto-detected locations in each dependency:

| Shard path | Installed as |
|---|---|
| `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
| `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
| `.claude/commands/<name>.md` | `.claude/commands/<shard>:<name>.md` |
| `CLAUDE.md` | `.claude/skills/<shard>--docs/SKILL.md` |
| `AGENTS.md` | `.claude/skills/<shard>--docs/reference/AGENTS.md` |
| `.mcp.json` | Merged into `.mcp-shards.json` |

#### Version tracking and update safety

Every installed AI doc file is tracked in `.claude/.ai-docs-info.yml` with:

- The **dependency version** from `shard.lock` (e.g., `kemal: 1.3.0`)
- A **dual-checksum** per file: the upstream checksum (as shipped by the shard) and the installed checksum (as it exists on disk)

When you run `shards update` and a dependency version changes:

- **Unmodified files** (checksums match) are silently updated to the new version
- **Locally modified files** (checksums differ) are preserved — the new upstream version is saved as `<file>.upstream` so you can merge manually

This means you can safely customize AI docs from your dependencies without
losing changes on update. Use `shards-alpha ai-docs diff <shard>` to compare
your modifications against upstream, or `shards-alpha ai-docs reset <shard>` to
discard changes and restore the original.

### MCP Server Distribution & Lifecycle

Shards that ship `.mcp.json` files have their MCP server configurations
merged into a project-level `.mcp-shards.json` during install. Server
names are namespaced as `<shard>/<server>` and paths are rewritten
automatically.

```sh
shards-alpha mcp              # Show server status
shards-alpha mcp start        # Start all MCP servers
shards-alpha mcp stop         # Stop all MCP servers
shards-alpha mcp restart      # Restart servers
shards-alpha mcp logs <name>  # Tail server logs
```

### Postinstall Script Tracking

Postinstall scripts are tracked by content hash. Changed scripts emit a
warning instead of running automatically, requiring explicit approval:

```sh
shards-alpha run-script              # Run all pending postinstall scripts
shards-alpha run-script <shard>      # Run for a specific shard
```

### SBOM Generation

Generate a Software Bill of Materials for your project's dependency tree:

```sh
shards-alpha sbom                      # SPDX 2.3 JSON (default)
shards-alpha sbom --format=cyclonedx   # CycloneDX 1.6 JSON
```

### Documentation Generation

Generate Crystal API documentation with optional theming:

```sh
shards-alpha docs
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
`shards-alpha install` by adding an `ai_assistant` section to `shard.yml`:

```yaml
ai_assistant:
  auto_install: true
```

When enabled, `shards-alpha install` will:
- Run `assistant init` if no assistant config exists
- Run `assistant update` if the installed version is older than the binary

Skip auto-configuration with `--skip-ai-assistant`.

#### Upgrading from `mcp-server init`

If you previously used `shards-alpha mcp-server init` to set up skills
and agents, running `assistant init` will detect the existing files,
adopt them into the tracking system, and create any missing files. Your
local modifications are preserved.

## Supply Chain Compliance

Ashard includes a suite of supply chain security tools, currently distributed
through `shards-alpha`, designed for
SOC2 and ISO 27001 compliance. These commands can be used individually or
combined into a unified compliance report.

For detailed usage, examples, and CI/CD integration patterns, see the
[Compliance Guide](docs/compliance-guide.md).

### Vulnerability Audit

Scan locked dependencies against the [OSV](https://osv.dev/) vulnerability
database:

```sh
shards-alpha audit                        # Colored terminal output
shards-alpha audit --format=json          # Machine-readable JSON
shards-alpha audit --format=sarif         # SARIF 2.1.0 for GitHub Code Scanning
shards-alpha audit --severity=high        # Only show high/critical
shards-alpha audit --fail-above=critical  # Exit 1 only for critical vulns
shards-alpha audit --ignore=GHSA-xxxx     # Suppress specific advisories
shards-alpha audit --offline              # Use cached data only
```

Suppressions can be managed in `.shards-audit-ignore`:

```yaml
- id: GHSA-xxxx-yyyy-zzzz
  reason: "Not applicable: we don't use the affected code path"
  expires: 2026-06-01
```

### Integrity Verification

Every `shards-alpha install` and `shards-alpha update` records SHA-256 checksums in
`shard.lock`. Subsequent installs verify that installed files match.

```sh
shards-alpha install               # Checksums computed and verified automatically
shards-alpha install --skip-verify # Bypass verification (logs a warning)
```

Tampered dependencies produce a clear error:

```
E: Checksum mismatch for web: expected sha256:abc123... got sha256:def456...
```

### License Compliance

List licenses for all locked dependencies with optional policy enforcement:

```sh
shards-alpha licenses                     # Colored table
shards-alpha licenses --format=json       # Machine-readable JSON
shards-alpha licenses --format=csv        # CSV export
shards-alpha licenses --format=markdown   # Markdown table
shards-alpha licenses --detect            # Heuristic detection from LICENSE files
shards-alpha licenses --check             # Exit 1 on policy violations
shards-alpha licenses --policy=path.yml   # Use custom license policy
```

### Dependency Policy

Define and enforce rules about what dependencies are allowed in your
project. Create a `.shards-policy.yml` file:

```sh
shards-alpha policy init    # Create a starter policy file
shards-alpha policy check   # Check dependencies against policy
shards-alpha policy show    # Display current policy summary
```

Policy rules include source host restrictions, blocked dependencies,
minimum version requirements, and postinstall script controls. Policies
are automatically enforced during `shards-alpha install` and `shards-alpha update`
when a `.shards-policy.yml` file is present.

### Change Audit Trail

Compare dependency states between lockfile versions:

```sh
shards-alpha diff                              # Compare HEAD vs current shard.lock
shards-alpha diff --from=HEAD --to=current     # Same as above (explicit)
shards-alpha diff --from=v1.0.0                # Compare against a git tag
shards-alpha diff --from=old.lock              # Compare against a saved lockfile
shards-alpha diff --format=json                # Machine-readable output
shards-alpha diff --format=markdown            # Markdown table for PR descriptions
```

An audit log is automatically maintained at `.shards/audit/changelog.json`
with timestamped entries for every `install` and `update` that modifies
the lock file.

### Compliance Report

Generate a unified report combining all compliance data into a single
document suitable for auditors:

```sh
shards-alpha compliance-report                           # JSON (default)
shards-alpha compliance-report --format=html             # Professional HTML report
shards-alpha compliance-report --format=markdown         # Markdown report
shards-alpha compliance-report --output=report.json      # Custom output path
shards-alpha compliance-report --sections=sbom,integrity # Only specific sections
shards-alpha compliance-report --reviewer=security@co.com # Add attestation
```

The report aggregates SBOM data, vulnerability findings, license inventory,
policy compliance status, integrity verification, and change history into a
single document with an executive summary and overall pass/fail status.
Reports are automatically archived to `.shards/audit/reports/`.

## Developers

### Requirements

These requirements are only necessary for compiling Ashard.

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

It is strongly recommended to use `make` for building Ashard and developing it.
The [`Makefile`](./Makefile) contains recipes for compiling and testing.

Run `make bin/shards-alpha` to build the binary.
* `release=1` for a release build (applies optimizations)
* `static=1` for static linking (only works with musl-libc)
* `debug=1` for full symbolic debug info

Run `make install` to install the binary. Target path can be adjusted with `PREFIX` (default: `PREFIX=/usr/bin`).

Run `make test` to run the test suites:
* `make test_unit` runs unit tests (`./spec/unit`)
* `make test_integration` runs integration tests (`./spec/integration`) on `bin/shards-alpha`

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
