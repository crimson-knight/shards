---
name: policy-check
description: Check dependencies against policy rules in .shards-policy.yml. Use when verifying compliance before releases.
allowed-tools: Bash, Read, Grep, Write
user-invocable: true
argument-hint: [--strict]
---

# Check Dependencies Against Policy Rules

Evaluate all locked dependencies against the rules defined in `.shards-policy.yml`.

## Steps

1. Check if `.shards-policy.yml` exists in the project root:
   - If it exists, read it to understand the active policy rules before running the check.
   - If it does not exist, ask the user if they want to create one with `shards-alpha policy init`, which generates a starter policy file.

2. Run the policy check with the user's requested options:
   ```sh
   shards-alpha policy check [OPTIONS]
   ```

   Available options:
   - `--strict` — Treat warnings as errors (useful for CI gates)
   - `--format=FORMAT` — Output format: `terminal` (default), `json`

   Other policy subcommands:
   - `shards-alpha policy init` — Create a starter `.shards-policy.yml`
   - `shards-alpha policy show` — Display a summary of the current policy

3. Interpret the results:
   - **Error violations** block installation: blocked dependencies, denied sources, minimum version failures
   - **Warning violations** are displayed but do not block: missing licenses, postinstall script auditing

4. Summarize the findings:
   - Total rules evaluated
   - Number of errors (blocking violations)
   - Number of warnings (non-blocking violations)
   - List each violation with the dependency name, rule that was violated, and the reason

5. For each violation, suggest a fix:
   - **Blocked dependency**: Remove it from shard.yml or update the policy to allow it with a documented reason
   - **Disallowed source host**: Move the dependency to an allowed host or add the host to `rules.sources.allowed_hosts`
   - **Disallowed organization**: Add the org to `rules.sources.allowed_orgs` for that host
   - **Minimum version failure**: Update the dependency version in shard.yml to meet the minimum
   - **Missing license**: Add a license to the dependency's shard.yml or set `rules.security.require_license: false`
   - **Postinstall script warning**: Review the script for safety, then either allow it or set `rules.security.block_postinstall: true` to block

6. If the user wants to modify the policy, offer to edit `.shards-policy.yml` directly with the needed changes.

## Policy File Structure

The policy file `.shards-policy.yml` supports these rule categories:
- `rules.sources` — Allowed hosts, allowed organizations, deny path dependencies
- `rules.dependencies` — Blocked dependencies with reasons, minimum version requirements
- `rules.security` — Require licenses, block/audit postinstall scripts
- `rules.custom` — Regex patterns to allow or block dependency names

## Example Invocations

```sh
# Basic policy check
shards-alpha policy check

# Strict mode for CI (warnings become errors)
shards-alpha policy check --strict

# JSON output for tooling
shards-alpha policy check --format=json

# Create a starter policy
shards-alpha policy init

# View current policy summary
shards-alpha policy show
```
