# Shards CLI Commands Reference

## shards install

Install dependencies from `shard.yml`. Creates `shard.lock` if it doesn't exist, otherwise uses locked versions.

```
shards install [options]
```

Behavior:
- Conservative: prefers locked versions when possible
- Installs in reverse topological order (transitive deps first)
- Runs postinstall scripts after installation
- Creates `shard.lock` on first run
- Raises `LockConflict` if dependencies changed in frozen mode

## shards update

Update dependencies to latest compatible versions.

```
shards update [shard_names...] [options]
```

- `shards update` -- update all dependencies
- `shards update kemal pg` -- update only kemal and pg
- Always rewrites `shard.lock`

## shards build

Build targets defined in `shard.yml`.

```
shards build [targets...] [-- build_options...]
```

- `shards build` -- build all targets
- `shards build my_app -- --release` -- build with Crystal flags
- Auto-runs `shards install` if dependencies missing

## shards run

Build and run a target.

```
shards run [target] [-- run_options...]
```

## shards check

Verify all dependencies are installed and match `shard.lock`.

```
shards check
```

## shards list

List installed dependencies.

```
shards list [--tree]
```

## shards lock

Lock dependencies without installing.

```
shards lock [--print] [--update [shards...]]
```

## shards outdated

Show outdated dependencies.

```
shards outdated [--pre]
```

## shards prune

Remove unused dependencies from `lib/`. Also cleans up AI docs for removed shards.

```
shards prune
```

## shards init

Generate a new `shard.yml`.

```
shards init
```

## shards version

Print the shard version from `shard.yml`.

```
shards version [path]
```

## shards run-script

Run postinstall scripts that are pending or changed.

```
shards run-script [shard_names...]
```

- `shards run-script` -- run all pending scripts
- `shards run-script my_shard` -- run for specific shard

Postinstall scripts only auto-run on first install. If the script changes in an update, you'll see a warning and must run it manually.

## shards ai-docs

Manage AI documentation installed from dependencies.

```
shards ai-docs [subcommand] [args...]
```

### Subcommands

| Subcommand | Description |
|------------|-------------|
| `status` (default) | Show installed AI docs status |
| `diff <shard>` | Show differences between local and upstream |
| `reset <shard> [file]` | Reset to upstream version |
| `update [shard]` | Force re-install (overwrite local changes) |
| `merge-mcp` | Merge `.mcp-shards.json` into `.mcp.json` |

## shards docs

Generate project documentation with theming and AI assistant integration.

```
shards docs [options]
```

Wraps `crystal docs` and post-processes the output:
- Injects CSS custom properties for theming
- Applies `docs-theme/style.css` if present
- Adds "Open in Claude/ChatGPT/Gemini" buttons to each page
- Generates parallel `.md` files for AI consumption

### Options

All `crystal docs` options are passed through. Additional options:

| Option | Description |
|--------|-------------|
| `--skip-ai-buttons` | Don't inject AI assistant buttons |

### Theming

Create `docs-theme/style.css` in your project root to override CSS variables:

```css
:root {
  --sidebar-bg: #1a1a2e;
  --accent-primary: #e94560;
  --type-name-color: #e94560;
  --link-color: #0f3460;
}
```

## shards sbom

Generate a Software Bill of Materials (SBOM) for compliance auditing.

```
shards sbom [options]
```

Reads `shard.lock` and each dependency's `shard.yml` to produce a machine-readable SBOM in SPDX 2.3 or CycloneDX 1.6 JSON format.

### Options

| Option | Description |
|--------|-------------|
| `--format=spdx` | SPDX 2.3 JSON output (default) |
| `--format=cyclonedx` | CycloneDX 1.6 JSON output |
| `--output=FILE` | Override default output path |
| `--include-dev` | Include development dependencies |

### Default output filenames

- SPDX: `<name>.spdx.json`
- CycloneDX: `<name>.cdx.json`

Package URLs (purls) are generated from resolver sources: GitHub, GitLab, Bitbucket, and Codeberg sources use their respective purl types; other git sources use `pkg:generic`.
