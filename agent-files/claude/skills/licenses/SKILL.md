---
name: licenses
description: List and check dependency licenses for SPDX compliance. Use when auditing license compatibility or checking policy.
allowed-tools: Bash, Read, Grep
user-invocable: true
argument-hint: [--check] [--detect]
---

# List and Check Dependency Licenses

Audit all locked dependency licenses for SPDX compliance and policy conformance.

## Steps

1. Verify that `shard.lock` exists in the project root. If it does not, inform the user they need to run `shards-alpha install` first.

2. Run the licenses command with the user's requested options:
   ```sh
   shards-alpha licenses [OPTIONS]
   ```

   Available options to pass through:
   - `--format=FORMAT` — Output format: `terminal` (default), `json`, `csv`, `markdown`
   - `--check` — Exit 1 if any license policy violations are found
   - `--detect` — Use heuristic detection to identify licenses from LICENSE/COPYING files when shard.yml does not declare one
   - `--include-dev` — Include development dependencies in the scan
   - `--policy=PATH` — Path to a license policy YAML file

3. Interpret the output:
   - Each dependency is listed with its name, version, declared license, and SPDX validity status
   - SPDX validation checks against 52 common SPDX identifiers and supports compound expressions (AND, OR, WITH operators)

4. Summarize the findings:
   - Total number of dependencies scanned
   - Count of dependencies with valid SPDX licenses
   - Count of dependencies with missing or invalid licenses
   - Any policy violations if `--check` was used

5. Flag potential issues:
   - Dependencies with no declared license (legal risk for commercial projects)
   - Dependencies with non-standard or unrecognized license identifiers
   - Copyleft licenses (GPL, AGPL) that may be incompatible with proprietary projects
   - If `--detect` was used, note which licenses were detected heuristically vs declared

6. Provide recommendations:
   - For missing licenses, suggest the user contact the dependency maintainer or check the repository directly
   - For policy violations, explain which rule was violated and how to resolve it
   - For CSV or markdown output, note these formats are useful for legal review or PR descriptions

## Example Invocations

```sh
# Basic license listing
shards-alpha licenses

# Check against policy, fail on violations
shards-alpha licenses --check

# Detect licenses from LICENSE files when not declared
shards-alpha licenses --detect

# Generate CSV for legal team review
shards-alpha licenses --format=csv

# Full scan including dev dependencies with detection
shards-alpha licenses --detect --include-dev --format=json
```
