# Architecture Decision Records

This directory records the durable "why" behind changes that affect how this
fork tracks upstream Crystal Shards, how additive features are introduced, and
how releases are validated.

## When to add an ADR

Create or update an ADR when a change affects any of these:

- The compatibility contract with upstream `crystal-lang/shards`
- The branch model (`master` as upstream mirror, `alpha` as additive branch)
- Release or upstream-sync automation
- The public naming or distribution story
- How `amber_cli` or other downstream tools are validated against this fork

## Format

Use a short numbered file name and keep the structure lightweight:

1. Title
2. Status
3. Context
4. Decision
5. Consequences

Update an existing ADR when the decision still stands but the operating details
need to be refreshed. Add a new ADR when the decision itself changes.
