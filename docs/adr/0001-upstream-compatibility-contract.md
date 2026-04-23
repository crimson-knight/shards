# 0001. Upstream Compatibility Contract

- Status: Accepted
- Date: 2026-04-19

## Context

This repository serves two jobs at once:

- `master` is expected to track `crystal-lang/shards` without local product
  changes.
- `alpha` carries additive tooling for compliance workflows, assistant setup,
  and related developer experience improvements.

That split only works if downstream tools can continue to treat the fork as a
drop-in replacement for core dependency management behavior. `amber_cli` is the
most important downstream consumer in this workspace, so it is our standing
compatibility canary.

The repo already had CI, release automation, and an upstream sync workflow, but
it did not yet enforce Amber-focused compatibility before pushing rebased code
or publishing updates.

## Decision

We treat compatibility as a release gate, not a best-effort guideline.

1. `master` remains an upstream mirror. If it diverges, that is a workflow
   failure that must be corrected.
2. `alpha` may add tooling, but it must not intentionally break the default
   `shards` dependency-management workflow.
3. Compatibility validation must compare the resolved Amber dependency graph
   using upstream Shards and this fork, while ignoring additive lockfile
   metadata such as checksums.
4. Compatibility validation must also prove that `amber_cli` can scaffold a new
   app and that the generated app installs dependencies and compiles
   successfully with this fork.
5. Upstream sync and release-facing changes must document the rationale,
   verification, and rollback story in the PR itself.
6. `shards-alpha` remains a working distribution name until we choose a final
   public name. Naming can change later, but compatibility expectations do not.

## Consequences

- Compatibility checks now take longer, especially on CI, because they build
  both upstream Shards and the additive fork, then exercise Amber workflows.
- Upstream sync can now fail because of downstream compatibility regressions,
  not just git conflicts. That is intentional.
- The public story becomes clearer: additive features are welcome, but they do
  not get to silently redefine core Shards behavior.
