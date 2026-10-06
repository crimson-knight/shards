# 0003. Public Name: Minecart

- Status: Accepted
- Date: 2026-09-23
- Supersedes: [ADR 0002: Public Name: Ashard](0002-public-name-ashard.md)

## Context

The owner chose **Minecart** as the public name and `minecart` as the primary
command. The name is available in Homebrew core, crates.io, and shardbox. The
compatibility contract in ADR 0001 remains binding: this fork must keep the
normal upstream Shards dependency-management workflow usable.

## Decision

- Use **Minecart** in public-facing documentation, help, and version banners.
- Build the primary executable as `bin/minecart` and expose the `minecart`
  command.
- Keep `bin/shards-alpha` as a deprecated alias. It prints one line to stderr
  unless `MINECART_NO_DEPRECATION=1`, then runs Minecart with the same arguments.
- Keep the manifest's `name: shards-alpha` so existing shard references retain
  their identity. Add a `minecart` target and retain the old target name.
- Keep reading `.shards-policy.yml`, `.shards-audit-ignore`, `.shards/`, and
  `.shards-license-policy.yml`. Also read their `.minecart-*`/`.minecart/`
  counterparts; when both names exist, the Minecart name wins.
- Keep upstream names `shard.yml`, `shard.lock`, and `lib/` unchanged. Do not
  rename the GitHub repository or its GitHub Pages site.
- The repository's `Formula/minecart.rb` installs Minecart and the deprecated
  alias. The release step updates the Homebrew tap.

## Consequences

Existing `shards-alpha` commands continue to work during the transition, and
projects can adopt Minecart-owned configuration names without losing support
for legacy files. The stock `shards` compatibility contract remains unchanged.
