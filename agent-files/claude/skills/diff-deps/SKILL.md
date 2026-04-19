---
name: diff-deps
description: Show dependency changes between lockfile states. Use when reviewing what changed after updates.
allowed-tools: Bash, Read, Grep
user-invocable: true
argument-hint: [--from=HEAD --to=current]
---

# Show Dependency Changes Between Lockfile States

Compare two states of shard.lock to see what dependencies were added, removed, or updated.

## Steps

1. Verify that `shard.lock` exists in the project root. If it does not, inform the user there is nothing to diff.

2. Run the diff command with the user's requested options:
   ```sh
   shards-alpha diff [OPTIONS]
   ```

   Available options:
   - `--from=REF` — Starting state (default: `HEAD`). Can be a git ref, file path ending in `.lock`, or `current`
   - `--to=REF` — Ending state (default: `current`). Same ref types as `--from`
   - `--format=FORMAT` — Output format: `terminal` (default), `json`, `markdown`

3. Interpret the reference types:
   - `current` — Reads the current `shard.lock` from disk
   - A git ref (`HEAD`, `main`, `v1.0.0`, a commit SHA) — Extracts `shard.lock` from that point in git history via `git show`
   - A file path ending in `.lock` — Reads from an arbitrary lockfile on disk

4. Summarize the changes:
   - **Added dependencies**: New dependencies not present in the "from" state. Report name, version, and source.
   - **Removed dependencies**: Dependencies present in "from" but absent in "to". Report name and previous version.
   - **Updated dependencies**: Dependencies present in both states but with different versions. Report name, old version, new version, and whether it was an upgrade or downgrade.
   - **Unchanged count**: How many dependencies remained the same.

5. Provide context for the changes:
   - For major version bumps, warn about potential breaking changes
   - For added dependencies, note if they are transitive (pulled in by another dependency)
   - For removed dependencies, note if the removal might affect other parts of the project

6. For markdown output (`--format=markdown`), mention this format is useful for including in PR descriptions to document dependency changes.

## Example Invocations

```sh
# What changed since the last commit?
shards-alpha diff

# What changed since a release tag?
shards-alpha diff --from=v1.0.0

# Compare two specific lockfiles
shards-alpha diff --from=before.lock --to=after.lock

# Generate markdown for a PR description
shards-alpha diff --from=main --format=markdown

# JSON output for tooling
shards-alpha diff --format=json
```
