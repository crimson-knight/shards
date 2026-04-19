# 0002. Public Name: Ashard

- Status: Accepted
- Date: 2026-04-19

## Context

This fork needs a public name that does three things at once:

1. Make it obvious that the project remains Shards-compatible.
2. Signal that it adds agent-oriented and experimental tooling.
3. Read cleanly in install docs, release notes, and blog copy.

`shards-alpha` has been a useful working binary name, but it is not the best
public product name for the long-term story.

## Decision

The public name is **Ashard**.

During the transition period:

- Public-facing documentation should refer to the project as **Ashard**
- The current binary and package name can remain `shards-alpha`
- Release notes should make that distinction explicit

We are not choosing a leading-number binary name or a heavily stylized spelling.
The name needs to be memorable, grammatically readable, and easy to say out
loud in English.

The intended reading is literally "a shard."

That phrasing matters. The name is supposed to suggest a tool that wraps around
the familiar shard workflow and makes it more capable for agent-oriented and
Amber-v2-era work, not a hard break into a brand-new package ecosystem.

We may eventually personify the name more as the Amber v2 tooling family
develops, especially for people working inside the amberverse, but the current
public explanation should stay plain and readable to any English speaker.

## Consequences

- Docs, blog copy, and release notes can become clearer immediately without
  forcing an all-at-once binary rename.
- Packaging work still remains for the eventual command/formula transition.
- Compatibility remains the anchor: Ashard is a Shards-compatible fork with
  additive tooling, not a separate package ecosystem.
