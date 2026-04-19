---
name: audit
description: Scan project dependencies for known security vulnerabilities using the OSV database. Use when reviewing dependencies for security issues.
allowed-tools: Bash, Read, Grep
user-invocable: true
argument-hint: [--severity=high] [--offline]
---

# Audit Dependencies for Vulnerabilities

Run a vulnerability scan against all locked dependencies using the OSV database.

## Steps

1. Verify that `shard.lock` exists in the project root. If it does not, inform the user they need to run `shards-alpha install` first.

2. Run the audit command with the user's requested options:
   ```sh
   shards-alpha audit [OPTIONS]
   ```

   Common options to pass through from user arguments:
   - `--severity=LEVEL` — Filter results to only show vulnerabilities at or above this severity (low, medium, high, critical)
   - `--format=FORMAT` — Output format: `terminal` (default), `json`, `sarif`
   - `--fail-above=LEVEL` — Only exit non-zero for vulnerabilities at or above this severity
   - `--ignore=ID[,ID]` — Comma-separated advisory IDs to suppress
   - `--ignore-file=PATH` — Path to ignore file (default: `.shards-audit-ignore`)
   - `--offline` — Use cached vulnerability data only, no network requests
   - `--update-db` — Force a cache refresh before scanning

3. Interpret the exit code:
   - Exit 0: No vulnerabilities found (or all filtered/ignored). Report this as a clean scan.
   - Exit 1: Vulnerabilities found matching the severity threshold.

4. If vulnerabilities are found, summarize the results:
   - Group findings by severity (critical, high, medium, low)
   - For each vulnerability, report: advisory ID, affected dependency, affected versions, severity, and summary
   - Highlight any critical or high severity issues first

5. Provide remediation advice:
   - Check if newer versions of affected dependencies are available that fix the vulnerability
   - Suggest specific version bumps in `shard.yml` where applicable
   - If a vulnerability cannot be fixed by upgrading, suggest adding it to `.shards-audit-ignore` with a reason and expiry date
   - Mention the `--fail-above` flag for CI pipelines that should only block on critical issues

6. For JSON output (`--format=json`), parse the structured data to provide a more detailed breakdown. For SARIF output (`--format=sarif`), note that this is designed for GitHub Code Scanning integration.

## Example Invocations

```sh
# Basic scan
shards-alpha audit

# Only show high and critical vulnerabilities
shards-alpha audit --severity=high

# CI-friendly: fail only on critical, output SARIF for GitHub
shards-alpha audit --format=sarif --fail-above=critical

# Offline scan with cached data
shards-alpha audit --offline
```
