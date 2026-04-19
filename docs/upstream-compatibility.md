# Upstream Compatibility Workflow

This fork is only useful if it stays compatible with upstream
`crystal-lang/shards` for ordinary dependency-management work while adding new
tools on top.

## Branch roles

- `master` tracks upstream and should fast-forward cleanly.
- `alpha` is the additive branch that carries compliance and assistant tooling.

That means "feature complete" is not enough. Changes on `alpha` must also prove
they preserve the dependency graph behavior that Amber and other Crystal
projects rely on.

## Compatibility promise

We validate two things before calling a change safe:

1. The resolved dependency graph for `amber_cli` and a freshly scaffolded Amber
   app matches upstream Shards once additive lockfile metadata is normalized.
2. `amber_cli` can still scaffold a new app, install dependencies, and compile
   successfully with this fork in the toolchain.

The normalized comparison intentionally ignores additive lockfile metadata such
as checksum lines, because those are value-added features rather than a
dependency-resolution change.

## Local validation

Run the compatibility check from this repo:

```bash
make compatibility
```

When working in this shared workspace, point the check at the local Amber CLI
checkout so you validate in-flight changes too:

```bash
AMBER_CLI_PATH=../amber_cli make compatibility
```

Useful environment overrides:

- `AMBER_CLI_PATH` to use a local Amber CLI checkout instead of cloning from GitHub
- `AMBER_CLI_REF` to test a specific remote Amber CLI branch or tag
- `KEEP_WORKDIR=1` to preserve the temporary work directory for debugging
- `WORK_DIR=/path/to/tmp` to control where the temporary workspace is created

## CI expectations

Compatibility is enforced in two places:

- Pull request and branch CI on macOS and Linux
- The upstream sync workflow before rebased changes are pushed and before the
  Homebrew formula is updated

If the compatibility gate fails, the sync must stop. We do not publish a new
rebased `alpha` branch and then investigate afterward.

## Naming guidance

`shards-alpha` is still a working distribution name, not a finalized product
name. Before renaming, the replacement should satisfy all of these:

- It clearly signals additive tooling rather than a hard fork of core behavior
- It preserves a clean install story for `shards`-compatible workflows
- It works consistently across repo names, release assets, and package managers
- It does not force Amber or Crystal users to learn a different basic command
  sequence just to install dependencies
