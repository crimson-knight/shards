## Implementation Plan: `shards diff` Change Audit Trail

### 1. Architecture Overview

The feature spans six new files and three modified files. The architecture follows the existing shards conventions: a `Command` subclass for the CLI entry point, separate modules for core logic, and both unit and integration test files mirroring the existing `spec/unit/` and `spec/integration/` directories.

**Data flow:**
1. User runs `shards diff [options]`
2. `Commands::Diff` parses args, resolves `--from` and `--to` into two `Lock` objects (arrays of `Package`)
3. `LockfileDiffer` compares the two `Lock` states and produces an `Array(DiffReport::Change)`
4. `DiffReport` formats the changes into the selected output format (terminal, JSON, markdown)
5. For the audit trail: `ChangeLogger` is called from `Commands::Install#run` and `Commands::Update#run` after `write_lockfile`, recording the diff plus metadata to `.shards/audit/changelog.json`

---

### 2. New File: `src/lockfile_differ.cr`

This is the core diffing engine. It takes two collections of `Package` (from/to) and computes the set of changes.

**Module structure:**

```crystal
# src/lockfile_differ.cr
require "./lock"
require "./package"

module Shards
  class LockfileDiffer
    # Represents a single dependency change
    record Change,
      name : String,
      status : Status,
      from_version : String?,
      to_version : String?,
      from_commit : String?,
      to_commit : String?,
      from_source : String?,
      to_source : String?,
      from_license : String?,
      to_license : String?,
      from_resolver_key : String?,
      to_resolver_key : String?

    enum Status
      Added
      Removed
      Updated
      Unchanged
    end

    # Compare two package sets and produce changes
    def self.diff(from_packages : Array(Package), to_packages : Array(Package)) : Array(Change)
      # ... algorithm described below
    end

    # Extract version string without commit metadata
    private def self.extract_version(version : Version) : String
    
    # Extract commit hash from version metadata (if git+commit format)
    private def self.extract_commit(version : Version) : String?

    # Try to read the license from the shard's spec
    # Safely returns nil if spec is unavailable
    private def self.safe_license(package : Package) : String?
  end
end
```

**Key algorithm for `diff`:**

```
1. Build a Hash(String, Package) keyed by name for both from_packages and to_packages
2. Collect all unique names from both sets: all_names = (from_map.keys + to_map.keys).uniq
3. For each name:
   a. If only in to_map -> Status::Added
   b. If only in from_map -> Status::Removed
   c. If in both:
      - Extract version/commit/source/license from each Package
      - If version, commit, source, and resolver all match -> Status::Unchanged (skip by default)
      - Otherwise -> Status::Updated
4. Return the array of Change records, sorted by status (Added, Updated, Removed) then by name
```

**Version/commit extraction** follows the existing `VERSION_AT_GIT_COMMIT` regex in `/Users/crimsonknight/open_source_coding_projects/shards/src/config.cr` (line 18): `^(\d+[-.][-.a-zA-Z\d]+)\+git\.commit\.([0-9a-f]+)$`. The `extract_commit` method parses this to separate the semantic version from the commit hash. Similarly for hg and fossil commit formats.

**License extraction** uses `package.spec.license` guarded by a rescue block, since loading a spec for a removed package may fail if the install directory no longer exists.

---

### 3. New File: `src/diff_report.cr`

Handles formatting the diff output in three modes.

**Module structure:**

```crystal
# src/diff_report.cr
require "json"
require "colorize"
require "./lockfile_differ"

module Shards
  class DiffReport
    getter changes : Array(LockfileDiffer::Change)
    getter from_label : String
    getter to_label : String

    def initialize(@changes, @from_label = "HEAD", @to_label = "working tree")
    end

    # Produce terminal-colored output
    def to_terminal(io : IO = STDOUT, colors : Bool = Shards.colors?) : Nil

    # Produce machine-readable JSON
    def to_json(io : IO = STDOUT) : Nil

    # Produce markdown for PR descriptions
    def to_markdown(io : IO = STDOUT) : Nil

    # Convenience: are there any actual changes?
    def any_changes? : Bool

    # Count of license changes (for the warning summary)
    def license_change_count : Int32

    private def status_icon(status : LockfileDiffer::Status) : String
    private def version_arrow(from : String?, to : String?) : String
    private def source_display(change : LockfileDiffer::Change) : String
  end
end
```

**Terminal format** (following the design spec):

```
Dependency Changes (from HEAD to working tree):

  + new_shard           0.0.0 -> 1.2.0   MIT         github:user/new_shard
  ^ existing_shard      1.0.0 -> 1.1.0   MIT         (3 commits)
  ^ another_shard       2.0.0 -> 3.0.0   MIT -> LGPL  !! LICENSE CHANGED
  x removed_shard       0.5.0 -> removed

Summary: 1 added, 2 updated, 1 removed
!! 1 license change detected -- review required
```

Uses `Colorize` to color added (green), removed (red), updated (yellow), license warnings (red bold). Respects `Shards.colors?` flag (consistent with the existing `--no-color` option in `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` line 58).

The UTF-8 symbols from the spec (`\u271A`, `\u2191`, `\u2716`) will be used when `Shards.colors?` is true; ASCII fallbacks (`+`, `^`, `x`) will be used otherwise (matching the existing pattern where the formatter in `src/logger.cr` conditionally colorizes).

**JSON format** outputs a structure matching the audit log schema (making it consistent and machine-parseable):

```json
{
  "from": "HEAD",
  "to": "working tree",
  "changes": {
    "added": [...],
    "removed": [...],
    "updated": [...]
  },
  "summary": {
    "added": 1,
    "removed": 1,
    "updated": 2,
    "license_changes": 1
  }
}
```

**Markdown format** produces a table suitable for PR descriptions:

```markdown
## Dependency Changes

| Status | Dependency | Version | License | Notes |
|--------|-----------|---------|---------|-------|
| Added | new_shard | 1.2.0 | MIT | github:user/new_shard |
| Updated | existing_shard | 1.0.0 -> 1.1.0 | MIT | |
| Removed | removed_shard | 0.5.0 | | |

**Summary:** 1 added, 2 updated, 1 removed
```

---

### 4. New File: `src/change_logger.cr`

Manages the persistent audit trail at `.shards/audit/changelog.json`.

**Module structure:**

```crystal
# src/change_logger.cr
require "json"
require "digest/sha256"
require "./lockfile_differ"

module Shards
  class ChangeLogger
    AUDIT_DIR  = ".shards/audit"
    LOG_FILE   = "changelog.json"

    record Entry,
      timestamp : Time,
      action : String,          # "install" or "update"
      user : String,            # from git config or ENV
      changes : ChangeSet,
      lockfile_checksum : String

    record ChangeSet,
      added : Array(ChangeDetail),
      removed : Array(ChangeDetail),
      updated : Array(ChangeDetail)

    record ChangeDetail,
      name : String,
      from_version : String?,
      to_version : String?,
      from_commit : String?,
      to_commit : String?,
      license_changed : Bool,
      source_changed : Bool

    # Read the existing changelog, or create empty structure
    def self.load(project_path : String) : Array(Entry)

    # Append a new entry for a lockfile modification
    def self.record(
      project_path : String,
      action : String,
      old_packages : Array(Package),
      new_packages : Array(Package),
      lockfile_path : String
    ) : Nil

    # Detect the current user (git config user.email, or ENV["USER"])
    private def self.detect_user : String

    # Compute SHA-256 checksum of the lockfile contents
    private def self.lockfile_checksum(path : String) : String

    # Convert LockfileDiffer::Change array to ChangeSet
    private def self.changes_to_changeset(changes : Array(LockfileDiffer::Change)) : ChangeSet

    # Serialize entries array to JSON
    private def self.write_log(project_path : String, entries : Array(Entry)) : Nil
  end
end
```

**Key design decisions:**

1. **File location**: `.shards/audit/changelog.json` lives inside the `.shards` directory (which is already the cache path used by the project, per `src/config.cr` line 39). However, for the audit trail we want it relative to the project root (not the global cache). So the path is `File.join(project_path, ".shards", "audit", "changelog.json")`.

2. **User detection**: First tries `git config user.email` (matching how the project is already git-aware). Falls back to `ENV["USER"]` or `ENV["USERNAME"]` on Windows. Falls back to `"unknown"`.

3. **Lockfile checksum**: Uses `Digest::SHA256.hexdigest(File.read(lockfile_path))` -- consistent with the existing pattern in `PostinstallInfo.hash_script` at `/Users/crimsonknight/open_source_coding_projects/shards/src/postinstall_info.cr` line 102.

4. **Atomic writes**: Write to a temporary file first, then rename, to prevent corruption if the process is interrupted.

5. **JSON structure** is append-only: load existing entries, append new one, write back. For very large projects this could be a concern, but lock file changes happen infrequently so the file stays small.

---

### 5. New File: `src/commands/diff.cr`

The CLI command that ties everything together.

**Module structure:**

```crystal
# src/commands/diff.cr
require "./command"
require "../lockfile_differ"
require "../diff_report"

module Shards
  module Commands
    class Diff < Command
      @from_ref : String = "HEAD"
      @to_ref : String = "current"
      @format : String = "terminal"
      @verbose : Bool = false

      def run(args : Array(String))
        parse_args(args)
        
        from_packages = resolve_ref(@from_ref)
        to_packages = resolve_ref(@to_ref)

        changes = LockfileDiffer.diff(from_packages, to_packages)
        
        report = DiffReport.new(changes, from_label: @from_ref, to_label: @to_ref)
        
        if report.any_changes?
          case @format
          when "terminal" then report.to_terminal
          when "json"     then report.to_json
          when "markdown" then report.to_markdown
          else
            raise Error.new("Unknown format: #{@format}. Use: terminal, json, markdown")
          end
        else
          Log.info { "No dependency changes between #{@from_ref} and #{@to_ref}." }
        end
      end

      private def parse_args(args : Array(String))
        args.each do |arg|
          case arg
          when .starts_with?("--from=")    then @from_ref = arg.split("=", 2).last
          when .starts_with?("--to=")      then @to_ref = arg.split("=", 2).last
          when .starts_with?("--format=")  then @format = arg.split("=", 2).last
          when "--verbose", "-V"           then @verbose = true
          end
        end
      end

      # Resolve a reference to an array of Packages from a lockfile state
      private def resolve_ref(ref : String) : Array(Package)
        case ref
        when "current"
          # Read the current working tree's shard.lock
          if lockfile?
            locks.shards
          else
            [] of Package
          end
        when "last-install"
          # Read from the .shards.info file (represents what's actually installed)
          Shards.info.installed.values.to_a
        else
          # Try as a file path first
          if File.exists?(ref) && !git_ref?(ref)
            Lock.from_file(ref).shards
          else
            # Try as a git ref (branch, tag, commit)
            read_lockfile_from_git_ref(ref)
          end
        end
      end

      # Check if ref looks like a git ref vs file path
      private def git_ref?(ref : String) : Bool
        # HEAD, branch names, tags, commit SHAs
        # Heuristic: if it's a valid file, we already handled it
        !File.exists?(ref)
      end

      # Read shard.lock content from a git ref using git show
      private def read_lockfile_from_git_ref(ref : String) : Array(Package)
        command = "git show #{Process.quote("#{ref}:#{LOCK_FILENAME}")}"
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run(command, shell: true, output: output, error: error, chdir: @path)

        unless status.success?
          raise Error.new("Could not read #{LOCK_FILENAME} from git ref '#{ref}': #{error.to_s.strip}")
        end

        Lock.from_yaml(output.to_s).shards
      end
    end
  end
end
```

**Arg parsing style** follows the existing pattern in `src/cli.cr` (e.g., the SBOM command at lines 153-164) where args are parsed inline with `starts_with?` and `split("=", 2)`.

**The `resolve_ref` method** is the heart of the command. It handles four cases:
1. `"current"` -- reads the current `shard.lock` from disk (using the inherited `locks` method from `Command`)
2. `"last-install"` -- reads from `.shards.info` (what's actually installed, vs what's in the lock)
3. A file path -- reads from an arbitrary lockfile (e.g., a backup or artifact)
4. A git ref -- uses `git show <ref>:shard.lock` to extract the lockfile at that point in history

---

### 6. Modifications to `src/cli.cr`

**Changes required:**

1. Add `"diff"` to the `BUILTIN_COMMANDS` array (line 5, between the existing entries -- alphabetically it goes between `check` and `init`)

2. Add a help line in `display_help_and_exit` (around line 34):
```
          diff [--from=REF] [--to=REF] [--format=FORMAT]  - Show dependency changes between lockfile states.
```

3. Add the `when "diff"` case in the command dispatch block (after `when "check"`, around line 105):
```crystal
when "diff"
  Commands::Diff.run(
    path,
    args[1..-1].reject(&.starts_with?("--"))
  )
```

Wait -- looking at the pattern more carefully, the `diff` command needs all args including the `--from=`, `--to=`, etc. flags. But the existing `reject(&.starts_with?("--"))` pattern strips flags. Looking at how `sbom` handles this at line 153: it passes `args[1..-1]` and parses the flags itself. The `diff` command should follow the same approach:

```crystal
when "diff"
  Commands::Diff.run(
    path,
    args[1..-1]
  )
```

This passes all remaining args (including `--from=HEAD` etc.) to the command, which parses them internally. This matches the `sbom`, `ai-docs`, and `mcp` patterns.

---

### 7. Modifications to `src/commands/install.cr`

After the lockfile is written (around line 36-41 in the current file), add a call to the change logger.

**Insertion point** -- after the `write_lockfile(packages)` call and before `touch_install_path`:

```crystal
if generate_lockfile?(packages)
  # Capture old packages before writing new lockfile
  old_packages = lockfile? ? locks.shards : [] of Package
  write_lockfile(packages)
  ChangeLogger.record(path, "install", old_packages, packages, lockfile_path)
elsif !Shards.frozen?
  File.touch(lockfile_path)
end
```

**Important ordering detail**: The `old_packages` must be captured *before* `write_lockfile` is called, because afterward the file on disk has the new content. The current code calls `locks` lazily (which reads from disk), so we need to force-read the old lock state first.

Actually, looking at the code flow more carefully: the `locks` method is memoized with `@locks`. If `lockfile?` is true and we access `locks.shards` before writing, `@locks` gets cached and won't be affected by the write. But we need the *new* packages too. The `packages` variable is the new set. So the approach is:

```crystal
if generate_lockfile?(packages)
  old_packages = if lockfile?
                   # Force read before we overwrite
                   Lock.from_file(lockfile_path).shards
                 else
                   [] of Package
                 end
  write_lockfile(packages)
  ChangeLogger.record(path, "install", old_packages, packages, lockfile_path)
elsif ...
```

This requires adding `require "../change_logger"` at the top.

---

### 8. Modifications to `src/commands/update.cr`

Same pattern as install. In the `run` method, around lines 28-33:

```crystal
if generate_lockfile?(packages)
  old_packages = if lockfile?
                   Lock.from_file(lockfile_path).shards
                 else
                   [] of Package
                 end
  write_lockfile(packages)
  ChangeLogger.record(path, "update", old_packages, packages, lockfile_path)
else
  File.touch(lockfile_path)
end
```

Requires `require "../change_logger"` at the top.

---

### 9. New File: `spec/unit/lockfile_differ_spec.cr`

**Structure:**

```crystal
require "./spec_helper"
require "../../src/lockfile_differ"

module Shards
  describe LockfileDiffer do
    it "detects added dependencies" do
      # Create from_packages = [] and to_packages = [package_a]
      # Verify changes has one Change with status Added
    end

    it "detects removed dependencies" do
      # from_packages = [package_a], to_packages = []
    end

    it "detects updated versions" do
      # from_packages = [package_a v1.0.0], to_packages = [package_a v1.1.0]
    end

    it "detects unchanged dependencies" do
      # Same package in both -> no change emitted (or Unchanged status)
    end

    it "detects source URL changes" do
      # Same name, same version, different resolver source
    end

    it "handles commit-pinned versions" do
      # Version like "1.0.0+git.commit.abc123" vs "1.0.0+git.commit.def456"
    end

    it "handles empty from (fresh install)" do
      # from = [], to = [a, b, c] -> all Added
    end

    it "handles empty to (all removed)" do
      # from = [a, b, c], to = [] -> all Removed
    end

    it "sorts changes by status then name" do
      # Verify ordering: Added first, then Updated, then Removed, alphabetically within each
    end
  end
end
```

To create test packages without git repositories, use the existing pattern from `spec/unit/lock_spec.cr`: create git repos with `create_git_repository`, then construct `Package` objects with known resolvers. Alternatively, use `GitResolver.new(name, source)` and `PathResolver.new(name, source)` directly since the unit test spec_helper requires resolvers.

---

### 10. New File: `spec/integration/diff_spec.cr`

**Structure** follows the pattern of `spec/integration/sbom_spec.cr`:

```crystal
require "./spec_helper"
require "json"

describe "diff" do
  it "shows added dependency" do
    # 1. Install with {web: "*"}, record lockfile
    # 2. Modify shard.yml to add orm, run shards install
    # 3. Run shards diff --from=<old_lockfile_path> --to=current
    # 4. Verify output contains "added" for orm
  end

  it "shows removed dependency" do
    # Install with {web: "*", orm: "*"}, then remove orm and reinstall
    # Diff should show orm as removed
  end

  it "shows version update" do
    # Install web ~> 1.0, then update to ~> 2.0
    # Diff shows version change
  end

  it "shows no changes when lockfile unchanged" do
    # Install, then diff current vs current
    # Should say "No dependency changes"
  end

  it "compares against git refs" do
    # This requires a git-initialized project directory
    # 1. git init in application_path
    # 2. Install deps, git add shard.lock, git commit
    # 3. Update deps, run shards diff --from=HEAD
    # 4. Verify output shows changes
  end

  it "outputs valid JSON format" do
    # shards diff --format=json
    # Parse output with JSON.parse, verify structure
  end

  it "outputs markdown format" do
    # shards diff --format=markdown
    # Verify contains "## Dependency Changes" and table markers
  end

  it "detects license changes" do
    # Requires creating repos with different licenses at different versions
    # This is a more complex setup test
  end

  it "writes audit log on install" do
    # Run shards install
    # Check .shards/audit/changelog.json exists and has entry
  end

  it "appends to audit log on update" do
    # Run shards install, then shards update
    # changelog.json should have 2 entries
  end

  it "fails gracefully with invalid git ref" do
    # shards diff --from=nonexistent_ref
    # Should produce an error message, not crash
  end

  it "reads from file path" do
    # Save a copy of shard.lock, modify deps, diff against the saved file
  end
end
```

---

### 11. Detailed Data Flow

**`shards diff --from=HEAD --to=current --format=terminal`:**

```
1. cli.cr dispatch -> Commands::Diff.run(path, ["--from=HEAD", "--to=current", "--format=terminal"])
2. Diff#parse_args sets @from_ref="HEAD", @to_ref="current", @format="terminal"
3. Diff#resolve_ref("HEAD") -> read_lockfile_from_git_ref("HEAD")
   -> runs: git show HEAD:shard.lock
   -> parses YAML with Lock.from_yaml
   -> returns Array(Package)
4. Diff#resolve_ref("current") -> reads locks.shards from disk
   -> returns Array(Package)
5. LockfileDiffer.diff(from_packages, to_packages) -> Array(Change)
6. DiffReport.new(changes, "HEAD", "current").to_terminal(STDOUT)
```

**`shards install` with audit logging:**

```
1. Install#run resolves and installs packages
2. Before write_lockfile: capture old_packages from current shard.lock
3. write_lockfile(packages) writes new shard.lock
4. ChangeLogger.record(path, "install", old_packages, packages, lockfile_path):
   a. LockfileDiffer.diff(old_packages, packages) -> changes
   b. Convert changes to ChangeSet
   c. Load existing changelog.json (or empty)
   d. Append new Entry with timestamp, user, action, changes, checksum
   e. Write changelog.json back
```

---

### 12. Error Handling Strategy

| Scenario | Handling |
|----------|----------|
| Git ref not found | Raise `Shards::Error` with message indicating the ref doesn't exist or doesn't contain shard.lock |
| No shard.lock at ref | Raise `Shards::Error` suggesting the lockfile didn't exist at that point |
| No shard.lock on disk (for `--to=current`) | Treat as empty package list (fresh state) |
| Spec unreadable for license check | Return `nil` for license (don't crash; license info is best-effort) |
| Audit directory not writable | Log a warning but don't fail the install/update operation |
| Invalid format argument | Raise `Shards::Error` listing valid formats |
| changelog.json is corrupted | Log warning, start with empty entries array (don't lose the lockfile operation) |

The error handling follows the existing pattern in `src/cli.cr` lines 221-232 where `Shards::Error` is caught and logged as fatal.

---

### 13. Success Criteria

1. **Diff shows added dependency**: Run `shards diff` after adding a new dependency -- output includes the dependency with "Added" status and its version.

2. **Diff shows removed dependency**: Run `shards diff` after removing a dependency -- output includes the dependency with "Removed" status.

3. **Diff shows version update**: Run `shards diff` after updating a dependency version -- output shows old version, new version, and "Updated" status.

4. **Diff detects license changes**: When a dependency's shard.yml license field changes between versions, the diff output flags it with a warning.

5. **Diff between git refs works**: Running `shards diff --from=<commit>` correctly reads the historical lockfile and compares against current.

6. **Diff with file path works**: Running `shards diff --from=/path/to/old/shard.lock` reads the lockfile from disk.

7. **JSON output is valid**: `shards diff --format=json` produces parseable JSON with the documented schema.

8. **Markdown output is valid**: `shards diff --format=markdown` produces a markdown table suitable for PR descriptions.

9. **No-changes case handled**: When there are no differences, the command outputs an informational message and exits 0.

10. **Audit log created on install**: After `shards install` modifies the lockfile, `.shards/audit/changelog.json` exists with a valid entry.

11. **Audit log appended on update**: After `shards update`, the changelog has an additional entry (not overwritten).

12. **Audit log entry structure correct**: Each entry has timestamp, action, user, changes (with added/removed/updated arrays), and lockfile_checksum.

13. **Error handling for invalid ref**: `shards diff --from=nonexistent` produces a clear error message and exits 1.

14. **All unit tests pass**: `crystal spec spec/unit/lockfile_differ_spec.cr`

15. **All integration tests pass**: `crystal spec spec/integration/diff_spec.cr`

---

### 14. Validation Steps

**Step 1: Basic diff after adding a dependency**
```sh
mkdir /tmp/test-diff && cd /tmp/test-diff
git init && git config user.email test@test.com && git config user.name Test
# Create shard.yml with one dependency
shards install
git add shard.lock && git commit -m "initial"
# Add a second dependency to shard.yml
shards install
shards diff --from=HEAD --to=current
# Expected: shows the new dependency as "Added"
```

**Step 2: Diff after removing a dependency**
```sh
# Remove the second dependency from shard.yml
shards install
shards diff --from=HEAD --to=current
# Expected: shows the removed dependency
```

**Step 3: Diff after version update**
```sh
# Change version constraint to allow newer version
shards update
shards diff --from=HEAD --to=current
# Expected: shows version change
```

**Step 4: JSON output validation**
```sh
shards diff --format=json | crystal eval 'require "json"; JSON.parse(STDIN.gets_to_end); puts "Valid JSON"'
```

**Step 5: Markdown output**
```sh
shards diff --format=markdown
# Verify contains "## Dependency Changes" and pipe-delimited table
```

**Step 6: Git ref comparison**
```sh
git log --oneline  # note two commits
shards diff --from=<first_commit> --to=<second_commit>
# Expected: shows changes between those lockfile states
```

**Step 7: Audit log**
```sh
cat .shards/audit/changelog.json | crystal eval 'require "json"; j = JSON.parse(STDIN.gets_to_end); puts j["entries"].as_a.size'
# Expected: prints the number of entries matching install/update operations performed
```

**Step 8: File path comparison**
```sh
cp shard.lock /tmp/old-shard.lock
# Make changes, shards install
shards diff --from=/tmp/old-shard.lock
# Expected: shows changes relative to saved lockfile
```

**Step 9: No changes**
```sh
shards diff --from=current --to=current
# Expected: "No dependency changes between current and current."
```

**Step 10: Invalid ref error**
```sh
shards diff --from=nonexistent_branch_xyz 2>&1
# Expected: error message about could not read shard.lock from git ref
echo $?
# Expected: 1
```

---

### 15. Implementation Sequencing

The recommended order of implementation:

1. **`src/lockfile_differ.cr`** -- Pure logic, no dependencies on other new files. Can be fully unit-tested in isolation.

2. **`spec/unit/lockfile_differ_spec.cr`** -- Write and run unit tests to verify the differ works correctly.

3. **`src/diff_report.cr`** -- Depends on `LockfileDiffer::Change`. Formatting logic only.

4. **`src/commands/diff.cr`** -- Depends on `LockfileDiffer` and `DiffReport`. The CLI entry point.

5. **`src/cli.cr` modifications** -- Register the `diff` command. Quick change.

6. **`src/change_logger.cr`** -- Independent of the diff command itself. Handles persistence.

7. **`src/commands/install.cr` and `src/commands/update.cr` modifications** -- Hook in the change logger. Requires `change_logger.cr` to exist.

8. **`spec/integration/diff_spec.cr`** -- End-to-end tests that exercise the full command and audit log.

---

### 16. Potential Challenges

1. **License detection reliability**: Reading `package.spec.license` requires the spec to be loadable, which may need the git cache to be populated. For the `--from` state, packages might not be installed. Mitigation: make license detection best-effort and gracefully return nil.

2. **Git ref resolution in non-git projects**: If the project directory is not a git repo, `--from=HEAD` will fail. Mitigation: detect whether the directory is a git repo first and provide a clear error message suggesting `--from=<file_path>` instead.

3. **Large changelog.json**: Over time, the audit log grows. Mitigation: consider adding a `--max-entries` config or rotation mechanism in a future iteration. For now, lockfile changes are infrequent enough that this is not a practical concern.

4. **Resolver cache interactions**: When comparing old vs new packages, the resolver cache may interfere. The unit tests already call `Resolver.clear_resolver_cache` in before_each hooks. The diff command should not need to update caches since it only reads lockfile YAML.

5. **Windows path compatibility**: The `git show` command path needs to use forward slashes for the git ref path (`:shard.lock`). Since `LOCK_FILENAME` is `"shard.lock"` (no directory prefix), this is fine.

### Critical Files for Implementation
- `/Users/crimsonknight/open_source_coding_projects/shards/src/lock.cr` - Core lockfile parsing logic that `LockfileDiffer` depends on; `Lock.from_yaml` is the primary entry point for reading lock states
- `/Users/crimsonknight/open_source_coding_projects/shards/src/package.cr` - The `Package` type that holds name, resolver, and version; the diff engine compares these fields
- `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` - Must be modified to register the `diff` command in `BUILTIN_COMMANDS` and the dispatch block
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/install.cr` - Must be modified to hook in `ChangeLogger.record` after `write_lockfile`
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` - Best pattern to follow for a command that reads lockfile packages, generates structured output in multiple formats, and has both unit and integration tests