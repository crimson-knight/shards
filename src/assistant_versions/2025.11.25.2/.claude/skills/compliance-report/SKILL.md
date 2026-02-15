---
name: compliance-report
description: Generate comprehensive supply-chain compliance reports. Use before releases or for audit documentation.
allowed-tools: Bash, Read, Grep, Write
user-invocable: true
argument-hint: [--sections=sbom,audit,licenses] [--reviewer=email]
---

# Generate Supply-Chain Compliance Report

Produce a unified compliance report combining SBOM, vulnerability audit, license compliance, policy evaluation, integrity verification, and change history into a single document suitable for SOC2 and ISO 27001 auditors.

## Steps

1. Verify prerequisites:
   - `shard.yml` must exist in the project root
   - `shard.lock` must exist (run `shards-alpha install` if missing)
   - For policy sections, `.shards-policy.yml` should exist (optional but recommended)

2. Run the compliance report command with the user's requested options:
   ```sh
   shards-alpha compliance-report [OPTIONS]
   ```

   Available options:
   - `--format=FORMAT` — Output format: `json` (default), `html`, `markdown`
   - `--output=PATH` — Output file path (default: `{project}-compliance-report.{ext}`)
   - `--sections=LIST` — Comma-separated sections to include (default: `all`)
   - `--reviewer=EMAIL` — Add reviewer attestation with timestamp to the report
   - `--since=DATE` — Filter change history to entries after this date
   - `--sign` — Create a detached GPG signature (`.sig` file)

3. Available sections:

   | Section | Description |
   |---------|-------------|
   | `sbom` | SPDX 2.3 dependency inventory |
   | `audit` | OSV vulnerability scan results |
   | `licenses` | License inventory and compliance |
   | `policy` | Policy rule evaluation results |
   | `integrity` | SHA-256 checksum verification |
   | `changelog` | Dependency change history |

4. Interpret the overall status:
   - **PASS** — No vulnerabilities, no policy violations, integrity verified
   - **ACTION_REQUIRED** — Medium-severity findings or warnings present
   - **FAIL** — Critical or high vulnerabilities, or policy/license failures

5. Summarize the report for the user:
   - Overall compliance status
   - Total dependency count (direct and transitive)
   - Vulnerability summary by severity
   - License compliance status
   - Policy evaluation results

## Example Invocations

```sh
# Full compliance report in HTML for auditors
shards-alpha compliance-report --format=html --reviewer=security@company.com

# Quick check with just SBOM and integrity sections
shards-alpha compliance-report --sections=sbom,integrity

# JSON report for CI artifact archival
shards-alpha compliance-report --output=compliance-report.json

# Markdown report for documentation
shards-alpha compliance-report --format=markdown
```
