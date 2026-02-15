# Supply Chain Compliance Guide

Shards-alpha provides six supply chain security features that address
SOC2 and ISO 27001 audit requirements. This guide covers each feature
in detail with usage examples, configuration references, and CI/CD
integration patterns.

## Table of Contents

- [1. Vulnerability Audit](#1-vulnerability-audit)
- [2. Integrity Verification (Checksum Pinning)](#2-integrity-verification)
- [3. License Compliance](#3-license-compliance)
- [4. Dependency Policy](#4-dependency-policy)
- [5. Change Audit Trail](#5-change-audit-trail)
- [6. Compliance Report](#6-compliance-report)
- [CI/CD Integration](#cicd-integration)
- [Auditor FAQ](#auditor-faq)

---

## 1. Vulnerability Audit

Scan locked dependencies against the [OSV](https://osv.dev/) vulnerability
database. Requires a `shard.lock` file.

### Usage

```sh
shards audit [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--format=FORMAT` | Output format: `terminal` (default), `json`, `sarif` |
| `--severity=LEVEL` | Filter by minimum severity: `low`, `medium`, `high`, `critical` |
| `--ignore=ID[,ID]` | Comma-separated advisory IDs to suppress |
| `--ignore-file=PATH` | Path to ignore file (default: `.shards-audit-ignore`) |
| `--fail-above=LEVEL` | Only exit 1 for vulnerabilities at or above this severity |
| `--offline` | Use cached vulnerability data only (no network requests) |
| `--update-db` | Force a cache refresh before scanning |

### Exit Codes

- `0` — No vulnerabilities found (or all filtered/ignored)
- `1` — Vulnerabilities found matching the severity threshold

### Ignore File Format

Create `.shards-audit-ignore` in your project root:

```yaml
- id: GHSA-xxxx-yyyy-zzzz
  reason: "Not applicable: we don't use the affected code path"
  expires: 2026-06-01

- id: GHSA-aaaa-bbbb-cccc
  reason: "Accepted risk: waiting for upstream fix"
```

When an ignore rule's `expires` date passes, the vulnerability is
automatically resurfaced. Rules without an `expires` field never expire.

### Output Formats

**Terminal** (default) — colored, human-readable output with severity
indicators.

**JSON** — machine-readable output suitable for dashboards and tooling.

**SARIF** — SARIF 2.1.0 format for integration with GitHub Code Scanning
and other static analysis platforms.

### Example

```sh
# CI pipeline: fail only on critical vulnerabilities
shards audit --format=sarif --fail-above=critical > results.sarif
```

---

## 2. Integrity Verification

SHA-256 checksums are automatically computed and stored in `shard.lock`
for every installed dependency. This ensures that installed files match
what was originally locked, protecting against supply chain tampering.

### How It Works

1. On `shards install` or `shards update`, a deterministic SHA-256 hash
   is computed over all source files in each dependency (sorted
   lexicographically, excluding `.git`, `.hg`, `.fossil`, and `lib`
   directories).
2. The checksum is written to `shard.lock` as a `checksum:` field on each
   dependency entry.
3. On subsequent `shards install`, the installed files are verified
   against the stored checksum. A mismatch raises an error.
4. Old lock files without checksums are transparently upgraded — the first
   install computes and stores the checksums.

### Lock File Format

```yaml
version: 2.0
shards:
  web:
    git: https://github.com/example/web.git
    version: 1.2.0
    checksum: sha256:a1b2c3d4e5f6...

  pg:
    git: https://github.com/example/pg.git
    version: 0.3.0
    checksum: sha256:f6e5d4c3b2a1...
```

### Skipping Verification

```sh
shards install --skip-verify
```

This logs a warning and proceeds without checking checksums. Useful for
development when you've intentionally modified files in `lib/`.

### Error Output

When a checksum mismatch is detected:

```
E: Checksum mismatch for web: expected sha256:a1b2c3... got sha256:x9y8z7...
```

This indicates the installed files differ from what was originally locked.
Delete the `lib/` directory and re-run `shards install` to resolve, or
investigate whether the dependency was tampered with.

---

## 3. License Compliance

List and audit licenses for all locked dependencies. Supports heuristic
detection from LICENSE files and policy-based enforcement.

### Usage

```sh
shards licenses [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--format=FORMAT` | Output format: `terminal` (default), `json`, `csv`, `markdown` |
| `--policy=PATH` | Path to a license policy YAML file |
| `--check` | Exit 1 if any license policy violations are found |
| `--include-dev` | Include development dependencies |
| `--detect` | Use heuristic detection to identify licenses from LICENSE files |

### Output Formats

**Terminal** — colored table with dependency name, version, declared
license, and SPDX validity.

**JSON** — structured output with license details, SPDX validation,
and policy evaluation results per dependency.

**CSV** — comma-separated values for spreadsheet import.

**Markdown** — pipe-delimited table suitable for documentation or PR
descriptions.

### SPDX Support

The license engine validates against 52 common SPDX license identifiers
and parses compound SPDX expressions with `AND`, `OR`, `WITH` operators
and parentheses. Examples:

- `MIT` — simple identifier
- `Apache-2.0 OR MIT` — dual-licensed
- `GPL-3.0-only WITH Classpath-exception-2.0` — license with exception
- `(MIT AND BSD-2-Clause) OR Apache-2.0` — grouped expression

### Heuristic Detection

When `--detect` is specified, the scanner examines LICENSE, LICENCE,
COPYING, and similar files in each dependency and uses pattern matching
to identify the license when the `shard.yml` doesn't declare one.

### Example

```sh
# Generate a license inventory for legal review
shards licenses --format=csv > licenses.csv

# CI check: fail if policy violations are found
shards licenses --check --policy=.shards-license-policy.yml
```

---

## 4. Dependency Policy

Define and enforce rules about what dependencies are allowed in your
project. Policies are automatically checked during `shards install`
and `shards update` when a `.shards-policy.yml` file exists.

### Usage

```sh
shards policy init                  # Create a starter policy file
shards policy check                 # Check current dependencies
shards policy check --strict        # Treat warnings as errors
shards policy check --format=json   # JSON output
shards policy show                  # Display policy summary
```

### Policy File Format

The policy file is `.shards-policy.yml` in your project root:

```yaml
version: 1

rules:
  sources:
    # Only allow dependencies from these Git hosts
    allowed_hosts:
      - github.com
      - gitlab.com

    # Restrict which organizations are allowed per host
    allowed_orgs:
      github.com:
        - my-company
        - trusted-org

    # Block path dependencies (local file paths)
    deny_path_dependencies: false

  dependencies:
    # Completely block specific dependencies
    blocked:
      - name: unsafe-shard
        reason: "Known security issues, use safe-shard instead"

    # Require minimum versions
    minimum_versions:
      openssl: "1.0.0"
      http-client: "2.0.0"

  security:
    # Require all dependencies to declare a license
    require_license: false

    # Block dependencies that run postinstall scripts
    block_postinstall: false

    # Log a warning for dependencies with postinstall scripts
    audit_postinstall: false

  # Custom regex rules to match dependency names
  custom: []
  # - pattern: "^internal-.*"
  #   action: allow
  #   reason: "Internal packages are always allowed"
```

### Policy Enforcement Behavior

- **During install/update**: If `.shards-policy.yml` exists, the policy
  is checked after dependency resolution but before installation. Error
  violations block the install. Warning violations are displayed but
  don't block.
- **No policy file**: Install and update proceed normally with no checks.
  The policy is fully opt-in.
- **Standalone check**: `shards policy check` evaluates the policy
  against the current `shard.lock` without installing anything.

### Violation Severities

- **Error** — blocks installation (blocked dependencies, denied sources)
- **Warning** — displayed but doesn't block (missing licenses, postinstall
  script auditing)

---

## 5. Change Audit Trail

Compare dependency states between two lockfile versions. Useful for
reviewing what changed in a PR, tracking dependency drift, and
maintaining an audit history.

### Usage

```sh
shards diff [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--from=REF` | Starting state (default: `HEAD`). Can be a git ref, file path, or `current` |
| `--to=REF` | Ending state (default: `current`). Same ref types as `--from` |
| `--format=FORMAT` | Output format: `terminal` (default), `json`, `markdown` |

### Reference Types

- `current` — reads the current `shard.lock` from disk
- A git ref (`HEAD`, `main`, `v1.0.0`, commit SHA) — extracts `shard.lock`
  from that point in git history via `git show`
- A file path ending in `.lock` — reads from an arbitrary lockfile

### Output Formats

**Terminal** — human-readable with status icons:

```
Dependency Changes (from HEAD to current):

  + new_shard            -> 1.2.0  git:/path/to/new_shard
  ^ existing_shard       1.0.0 -> 1.1.0
  x removed_shard        0.5.0 -> removed

Summary: 1 added, 1 updated, 1 removed
```

**JSON** — structured output with changes grouped by status:

```json
{
  "from": "HEAD",
  "to": "current",
  "changes": {
    "added": [{"name": "new_shard", "to_version": "1.2.0", ...}],
    "removed": [{"name": "removed_shard", "from_version": "0.5.0", ...}],
    "updated": [{"name": "existing_shard", "from_version": "1.0.0", "to_version": "1.1.0", ...}]
  },
  "summary": {"added": 1, "removed": 1, "updated": 1}
}
```

**Markdown** — table format for PR descriptions.

### Automatic Audit Log

Every `shards install` and `shards update` that modifies `shard.lock`
appends an entry to `.shards/audit/changelog.json`:

```json
{
  "entries": [
    {
      "timestamp": "2026-02-15T10:30:00Z",
      "action": "install",
      "user": "developer@company.com",
      "changes": {
        "added": [{"name": "web", "to_version": "1.0.0", ...}],
        "removed": [],
        "updated": []
      },
      "lockfile_checksum": "a1b2c3..."
    }
  ]
}
```

The user is detected from `git config user.email`, falling back to the
`USER` environment variable.

### Examples

```sh
# What changed since the last release tag?
shards diff --from=v1.0.0

# Save current state, make changes, then compare
cp shard.lock before.lock
# ... modify shard.yml, run shards install ...
shards diff --from=before.lock --to=current

# Generate a markdown summary for a PR
shards diff --from=main --format=markdown
```

---

## 6. Compliance Report

Generate a unified compliance report combining all available data into a
single document. The report is designed for SOC2 and ISO 27001 auditors
and includes an executive summary with an overall pass/fail status.

### Usage

```sh
shards compliance-report [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--format=FORMAT` | Output format: `json` (default), `html`, `markdown` |
| `--output=PATH` | Output file path (default: `{project}-compliance-report.{ext}`) |
| `--sections=LIST` | Comma-separated sections to include (default: `all`) |
| `--reviewer=EMAIL` | Add reviewer attestation to the report |
| `--since=DATE` | Filter change history to entries after this date |
| `--sign` | Create a detached GPG signature (`.sig` file) |

### Available Sections

| Section | Data Source | SOC2 | ISO 27001 |
|---------|-----------|------|-----------|
| `sbom` | SPDX 2.3 dependency inventory | CC3.2 | A.8.9, A.8.30 |
| `audit` | OSV vulnerability scan | CC7.1 | A.8.8 |
| `licenses` | License inventory | CC3.2 | A.5.19 |
| `policy` | Policy rule evaluation | CC6.1 | A.8.28 |
| `integrity` | Checksum verification | CC6.1 | A.8.9 |
| `changelog` | Dependency change history | CC8.1 | A.8.9 |

### Report Structure

Every report includes:

- **Project metadata** — name, version, Crystal version, generator info
- **Executive summary** — dependency counts, vulnerability tallies,
  overall compliance status
- **Section data** — detailed findings for each requested section
- **Attestation** (optional) — reviewer name and timestamp

### Overall Status

The report computes an aggregate status:

- **PASS** — no vulnerabilities, no policy violations, integrity verified
- **ACTION_REQUIRED** — medium-severity findings or warnings present
- **FAIL** — critical/high vulnerabilities, or policy/license failures

### Output Formats

**JSON** — machine-parseable with this top-level structure:

```json
{
  "report": {
    "version": "1.0",
    "generated_at": "2026-02-15T10:30:00Z",
    "generator": "shards-alpha 0.18.0",
    "project": {"name": "my-app", "version": "1.0.0", ...},
    "summary": {
      "total_dependencies": 12,
      "direct_dependencies": 4,
      "overall_status": "pass",
      ...
    },
    "sections": {
      "sbom": {...},
      "integrity": {...},
      ...
    },
    "attestation": {
      "reviewer": "security@company.com",
      "reviewed_at": "2026-02-15T10:30:00Z"
    }
  }
}
```

**HTML** — professional, print-ready report with:
- Color-coded status badges (green/yellow/red)
- Expandable/collapsible sections
- Print-optimized CSS with page breaks
- Dependency and integrity tables

**Markdown** — headings, tables, and summary suitable for documentation
systems or PR descriptions.

### Report Archiving

Every generated report is automatically copied to
`.shards/audit/reports/` with a timestamp in the filename, creating
a historical record of compliance checks.

### Examples

```sh
# Full compliance report for auditors
shards compliance-report --format=html --reviewer=security@company.com

# Minimal report with just SBOM and integrity for a quick check
shards compliance-report --sections=sbom,integrity

# CI: generate JSON report and archive it as a build artifact
shards compliance-report --output=compliance-report.json
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Compliance
on: [push, pull_request]
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: crystal-lang/install-crystal@v1

      - name: Install dependencies
        run: shards install

      - name: Vulnerability audit
        run: shards audit --format=sarif --fail-above=high > audit.sarif

      - name: License check
        run: shards licenses --check

      - name: Policy check
        run: shards policy check

      - name: Compliance report
        run: shards compliance-report --output=compliance-report.json

      - name: Upload SARIF
        if: always()
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: audit.sarif

      - name: Upload compliance report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: compliance-report
          path: compliance-report.json
```

### PR Description Generation

Add dependency change summaries to pull request descriptions:

```sh
shards diff --from=main --format=markdown >> pr-body.md
```

---

## Auditor FAQ

**Q: What third-party dependencies do you use?**
A: Run `shards compliance-report` — the SBOM section lists every
dependency with name, version, license, and source URL in SPDX 2.3
format.

**Q: Are any of them vulnerable?**
A: The vulnerability audit section scans all dependencies against
the OSV database. Run `shards audit --format=json` for detailed
findings.

**Q: Are they all properly licensed?**
A: Run `shards licenses --format=json` for a complete license
inventory. Use `--check` with a policy file for automated compliance
verification.

**Q: How do you control what enters the codebase?**
A: The `.shards-policy.yml` file defines allowed sources, blocked
dependencies, and other constraints. Policies are enforced
automatically during `shards install` and `shards update`.

**Q: How do you track dependency changes?**
A: Every install/update is recorded in `.shards/audit/changelog.json`
with timestamp, user, and detailed change list. Run `shards diff`
to compare any two lockfile states.

**Q: Can you prove dependency integrity?**
A: SHA-256 checksums in `shard.lock` are verified on every install.
The compliance report's integrity section shows verification status
for each dependency.

**Q: When was this last reviewed?**
A: Use `shards compliance-report --reviewer=NAME` to add a timestamped
attestation to the report.
