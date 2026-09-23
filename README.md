# Minecart

[![CI](https://github.com/crystal-lang/shards/workflows/CI/badge.svg)](https://github.com/crystal-lang/shards/actions?query=workflow%3ACI+event%3Apush+branch%3Amaster)

Minecart is a drop-in compatible fork of Crystal's [`shards`](https://crystal-lang.org)
dependency manager, with additional supply-chain and developer tooling. It was
formerly distributed as `shards-alpha`; that command remains as a deprecated
alias. Existing `shard.yml`, `shard.lock`, and `lib/` workflows remain readable
by stock `shards`.

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
  spec_helper:
    path: tools/spec_helper

license: MIT
```

When libraries are installed from Git repositories, the repository is expected
to have version tags following a [semver](http://semver.org/)-like format,
prefixed with a `v`. Examples: `v1.2.3`, `v2.0.0-rc1` or `v2017.04.1`.

Please see the [SPEC](docs/shard.yml.adoc) for more details about the
`shard.yml` format.


## Install

Upstream Shards is usually distributed with Crystal itself. Minecart uses the
`minecart` command. The old `shards-alpha` alias prints a one-line deprecation
notice; set `MINECART_NO_DEPRECATION=1` to suppress it.

You can download a source tarball from the same page (or clone the repository)
then run `make release=1` and copy `bin/minecart` and `bin/shards-alpha` into
your `PATH`. For example `/usr/local/bin`.

You are now ready to create a `shard.yml` for your projects (see details in
[SPEC](docs/shard.yml.adoc)). You can type `minecart init` to have an example
`shard.yml` file created for your project.

Run `minecart install` to install your dependencies, which will lock your
dependencies into a `shard.lock` file. You should check both `shard.yml` and
`shard.lock` into version control, so further `minecart install` will always
install locked versions, achieving reproducible installations across computers.

Run `minecart --help` to list other commands with their options.

Happy Hacking!

## Project and command names

The product and command are both named **Minecart** (`minecart`). The manifest's
shard name remains `shards-alpha` so existing package references keep their
identity. The deprecated `shards-alpha` executable runs the same command.

For the docs publishing story, see
[docs/crystal-docs-gap-analysis.md](docs/crystal-docs-gap-analysis.md). It
explains what Crystal Docs already provides and what Minecart adds on top.

## Compatibility Promise

This repository has two operating modes:

- `master` mirrors upstream `crystal-lang/shards`
- `alpha` carries additive tooling currently distributed as `minecart`

Minecart is a drop-in replacement for `shards` dependency management. It reads
stock manifests and locks, and stock `shards` reads Minecart-written manifests
and locks. The goal is to preserve normal Shards behavior while adding
additional tooling.

We now validate that promise against `amber_cli` before treating upstream syncs
or release-facing changes as safe. See
[docs/upstream-compatibility.md](docs/upstream-compatibility.md) for the local
and CI workflow, including `make compatibility`.

## Minecart Features

Minecart currently ships as the `minecart` binary and extends the standard
Crystal dependency manager with features
for AI-assisted development. It distributes AI documentation and MCP server
configurations alongside library code, so consuming projects get everything
they need from `minecart install`.

### AI Documentation Distribution

Shard authors can ship AI context files (`CLAUDE.md`, skills, agents,
commands) that are automatically installed into the consumer's `.claude/`
directory with shard-namespaced paths.

```sh
minecart install          # AI docs are installed alongside dependencies
minecart ai-docs          # Check status of installed AI documentation
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

When you run `minecart update` and a dependency version changes:

- **Unmodified files** (checksums match) are silently updated to the new version
- **Locally modified files** (checksums differ) are preserved — the new upstream version is saved as `<file>.upstream` so you can merge manually

This means you can safely customize AI docs from your dependencies without
losing changes on update. Use `minecart ai-docs diff <shard>` to compare
your modifications against upstream, or `minecart ai-docs reset <shard>` to
discard changes and restore the original.

### MCP Server Distribution & Lifecycle

Shards that ship `.mcp.json` files have their MCP server configurations
merged into a project-level `.mcp-shards.json` during install. Server
names are namespaced as `<shard>/<server>` and paths are rewritten
automatically.

```sh
minecart mcp              # Show server status
minecart mcp start        # Start all MCP servers
minecart mcp stop         # Stop all MCP servers
minecart mcp restart      # Restart servers
minecart mcp logs <name>  # Tail server logs
```

### Postinstall Script Tracking

Postinstall scripts are tracked by content hash. Changed scripts emit a
warning instead of running automatically, requiring explicit approval:

```sh
minecart run-script              # Run all pending postinstall scripts
minecart run-script <shard>      # Run for a specific shard
```

### SBOM Generation

Generate a Software Bill of Materials for your project's dependency tree:

```sh
minecart sbom                      # SPDX 2.3 JSON (default)
minecart sbom --format=cyclonedx   # CycloneDX 1.6 JSON
```

### Documentation Generation

Generate Crystal API documentation with optional theming:

```sh
minecart docs
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
minecart assistant init       # Install skills, agents, settings, and MCP config
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
minecart assistant status     # Show version, components, modified files
minecart assistant update     # Upgrade to latest (preserves local edits)
minecart assistant update --dry-run  # Preview what would change
minecart assistant remove     # Remove all tracked files
```

#### Selective installation

Skip components you don't need:

```sh
minecart assistant init --no-agents    # Skip agent definitions
minecart assistant init --no-mcp       # Skip .mcp.json configuration
minecart assistant init --no-skills    # Skip skill files
minecart assistant init --no-settings  # Skip settings.json and CLAUDE.md
```

#### Automatic setup via shard.yml

Projects can opt in to automatic assistant configuration during
`minecart install` by adding an `ai_assistant` section to `shard.yml`:

```yaml
ai_assistant:
  auto_install: true
```

When enabled, `minecart install` will:
- Run `assistant init` if no assistant config exists
- Run `assistant update` if the installed version is older than the binary

Skip auto-configuration with `--skip-ai-assistant`.

#### Upgrading from `mcp-server init`

If you previously used `minecart mcp-server init` to set up skills
and agents, running `assistant init` will detect the existing files,
adopt them into the tracking system, and create any missing files. Your
local modifications are preserved.

## Supply Chain Compliance

Minecart includes a suite of supply chain security tools, currently distributed
through `minecart`, designed for
SOC2 and ISO 27001 compliance. These commands can be used individually or
combined into a unified compliance report.

For detailed usage, examples, and CI/CD integration patterns, see the
[Compliance Guide](docs/compliance-guide.md).

### Vulnerability Audit

Scan locked dependencies against the [OSV](https://osv.dev/) vulnerability
database:

```sh
minecart audit                        # Colored terminal output
minecart audit --format=json          # Machine-readable JSON
minecart audit --format=sarif         # SARIF 2.1.0 for GitHub Code Scanning
minecart audit --severity=high        # Only show high/critical
minecart audit --fail-above=critical  # Exit 1 only for critical vulns
minecart audit --ignore=GHSA-xxxx     # Suppress specific advisories
minecart audit --offline              # Use cached data only
```

Suppressions can be managed in `.minecart-audit-ignore`. The legacy
`.shards-audit-ignore` name remains supported:

```yaml
- id: GHSA-xxxx-yyyy-zzzz
  reason: "Not applicable: we don't use the affected code path"
  expires: 2026-06-01
```

### Integrity Verification

Git dependencies use `git-tree:<hash>` in `shard.lock`. Minecart reads the tree
hash from the resolved commit's Git object database and verifies it before any
postinstall script runs. Path, Mercurial, and Fossil dependencies keep their
directory `sha256:` checksum. Existing `sha256:` lock checksums continue to
verify; `minecart update` or `minecart lock --rekey` rewrites Git checksums to
tree hashes. Stock `shards` safely ignores this additive checksum field.

During this release, `minecart install --frozen` warns if a lock entry has no
checksum. A later release will make that condition an error.

Tampered dependencies produce a clear error:

```
E: Checksum verification failed for web. The resolved source may have changed
```

### License Compliance

List licenses for all locked dependencies with optional policy enforcement:

```sh
minecart licenses                     # Colored table
minecart licenses --format=json       # Machine-readable JSON
minecart licenses --format=csv        # CSV export
minecart licenses --format=markdown   # Markdown table
minecart licenses --detect            # Heuristic detection from LICENSE files
minecart licenses --check             # Exit 1 on policy violations
minecart licenses --policy=path.yml   # Use custom license policy
```

### Dependency Policy

Define and enforce rules about what dependencies are allowed in your
project. Create a `.minecart-policy.yml` file:

```sh
minecart policy init    # Create a starter policy file
minecart policy check   # Check dependencies against policy
minecart policy show    # Display current policy summary
```

Policy rules include source host restrictions, blocked dependencies,
minimum version requirements, and postinstall script controls. Policies
are automatically enforced during `minecart install` and `minecart update`
when a `.minecart-policy.yml` or legacy `.shards-policy.yml` file is present.

### Dependency Pinning

`install` and `update` check only the root project's runtime dependencies.
Development dependencies, path dependencies, and transitive dependencies are
skipped. Missing selectors, branches, and version ranges produce one warning
per dependency; exact versions are accepted with an advisory that a commit plus
the lock checksum is stronger. Use `--strict-pinning` to make unpinned
dependencies errors now. The default is designed to become an error in a later
release.

Libraries that publish ranges can add `pinning: library` to the top level of
`shard.yml`. Minecart then checks that `shard.lock` is committed and is not
gitignored. Stock `shards` ignores this additive key. A policy can override the
default with `dependencies.require_exact`:

```yaml
version: 1
rules:
  dependencies:
    require_exact: warn # true, warn, or false
```

Minecart prefers `.minecart-policy.yml`, `.minecart-audit-ignore`,
`.minecart-license-policy.yml`, and `.minecart/` when both Minecart and legacy
`.shards-*`/`.shards/` names exist. Legacy names continue to work.

### Change Audit Trail

Compare dependency states between lockfile versions:

```sh
minecart diff                              # Compare HEAD vs current shard.lock
minecart diff --from=HEAD --to=current     # Same as above (explicit)
minecart diff --from=v1.0.0                # Compare against a git tag
minecart diff --from=old.lock              # Compare against a saved lockfile
minecart diff --format=json                # Machine-readable output
minecart diff --format=markdown            # Markdown table for PR descriptions
```

An audit log is automatically maintained at `.minecart/audit/changelog.json`
with timestamped entries for every `install` and `update` that modifies
the lock file.

### Compliance Report

Generate a unified report combining all compliance data into a single
document suitable for auditors:

```sh
minecart compliance-report                           # JSON (default)
minecart compliance-report --format=html             # Professional HTML report
minecart compliance-report --format=markdown         # Markdown report
minecart compliance-report --output=report.json      # Custom output path
minecart compliance-report --sections=sbom,integrity # Only specific sections
minecart compliance-report --reviewer=security@co.com # Add attestation
```

The report aggregates SBOM data, vulnerability findings, license inventory,
policy compliance status, integrity verification, and change history into a
single document with an executive summary and overall pass/fail status.
Reports are automatically archived to `.minecart/audit/reports/`.

## Developers

### Requirements

These requirements are only necessary for compiling Minecart.

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

It is strongly recommended to use `make` for building Minecart and developing it.
The [`Makefile`](./Makefile) contains recipes for compiling and testing.

Run `make bin/minecart` to build the binary.
* `release=1` for a release build (applies optimizations)
* `static=1` for static linking (only works with musl-libc)
* `debug=1` for full symbolic debug info

Run `make install` to install the binary. Target path can be adjusted with `PREFIX` (default: `PREFIX=/usr/bin`).

Run `make test` to run the test suites:
* `make test_unit` runs unit tests (`./spec/unit`)
* `make test_integration` runs integration tests (`./spec/integration`) on `bin/minecart`

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
