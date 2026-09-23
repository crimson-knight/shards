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

The selected public name is **Ashard**.

Why this name:

- It reads naturally to an English speaker as "a shard"
- It keeps the link to Shards obvious
- It leaves room for the "A" to imply additive, agent-oriented, and alpha-stage
  tooling without sounding like a separate language or ecosystem

For the transition period:

- The public docs, release narrative, and blog copy should say **Ashard**
- The current binary and package names can stay `shards-alpha` until we finish
  the packaging rename without breaking compatibility for existing users

We should avoid a binary name that starts with a numeral. While shells allow
digits in executable names, a leading-number command is awkward to read, easy to
mis-hear, and weaker for copy-pasteable installation docs.
