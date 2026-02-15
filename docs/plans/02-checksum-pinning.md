## Implementation Plan: Checksum Pinning for shard.lock

### 1. Architecture Overview

The checksum pinning feature adds a content-based SHA-256 hash to each dependency entry in `shard.lock`. This hash is computed from the installed source content (not from git metadata), ensuring that even if a git tag is force-pushed, the mismatch is detected. The system follows these principles:

- **Compute on lock write**: Checksums are generated when `shard.lock` is written (during `install`, `update`, or `lock`).
- **Verify on install**: When `shard.lock` already has checksums, `shards install` verifies them after downloading sources.
- **Backward compatible**: Old lock files without checksums are accepted gracefully; the first install upgrades them.
- **Resolver-agnostic hashing**: Each resolver type provides a way to produce checksummable content, but the hashing algorithm itself lives in a central module.

### 2. Checksum Algorithm Design

**Algorithm**: SHA-256, stored as `sha256:<64-char-hex>` (consistent with the existing convention in `PostinstallInfo` and `AIDocsInfo`).

**Determinism Requirements**:
- Files are sorted lexicographically by relative path before hashing.
- For each file, the hash input is: `<relative-path>\0<file-size>\0<file-content>`. This Merkle-like construction ensures that file renames are detected and that the hash is path-sensitive.
- Binary files are included as-is (no line ending normalization). Line ending normalization would be risky because Crystal source may intentionally contain specific line endings, and binary files (executables, images) must not be modified.
- Symlinks within the source tree are resolved to their target content.
- Directories named `.git`, `.hg`, `.fossil`, `.fslckout` are excluded from hashing, as they are VCS metadata not part of the source content.

**Rationale for not using git tree hashes**: Git tree SHA-1 hashes are VCS-specific, unavailable for path/fossil/hg resolvers, and use SHA-1 (weaker). Computing from file content is universal across all resolver types.

### 3. File-by-File Implementation Details

#### 3.1 New File: `src/checksum.cr`

```crystal
# Location: /Users/crimsonknight/open_source_coding_projects/shards/src/checksum.cr

require "digest/sha256"

module Shards
  module Checksum
    ALGORITHM_PREFIX = "sha256"
    EXCLUDED_DIRS = {".git", ".hg", ".fossil", ".fslckout", "_FOSSIL_"}

    # Compute a deterministic SHA-256 checksum for a directory of source files.
    # Returns a string like "sha256:abcdef1234..."
    def self.compute(path : String) : String
      digest = Digest::SHA256.new
      files = collect_files(path)
      files.sort!  # lexicographic sort for determinism

      files.each do |relative_path|
        full_path = File.join(path, relative_path)
        content = File.read(full_path)
        # Hash: relative_path + NUL + file_size + NUL + content
        digest.update(relative_path)
        digest.update("\0")
        digest.update(content.bytesize.to_s)
        digest.update("\0")
        digest.update(content)
      end

      "#{ALGORITHM_PREFIX}:#{digest.final.hexstring}"
    end

    # Verify a checksum against a directory.
    # Returns true if match, false if mismatch.
    def self.verify(path : String, expected : String) : Bool
      compute(path) == expected
    end

    # Collect all files recursively, returning relative paths.
    # Excludes VCS metadata directories.
    private def self.collect_files(base_path : String, prefix : String = "") : Array(String)
      files = [] of String

      Dir.each_child(base_path) do |entry|
        relative = prefix.empty? ? entry : File.join(prefix, entry)
        full = File.join(base_path, entry)

        if File.directory?(full) && !File.symlink?(full)
          next if EXCLUDED_DIRS.includes?(entry)
          # Skip the lib symlink that shards creates inside installed packages
          next if entry == "lib" && prefix.empty?
          files.concat(collect_files(full, relative))
        elsif File.file?(full) || File.symlink?(full)
          files << relative
        end
      end

      files
    end
  end
end
```

**Key design decisions**:
- The `lib` symlink inside installed packages (created by `Package#install_lib_path`) is excluded because it points back to the project's lib directory and is not part of the shard's source content.
- Symlinked files are read (content resolved), but symlinked directories are not recursed into (to avoid infinite loops from the `lib` symlink).
- The `\0` separator between path, size, and content prevents collision attacks where file boundaries are ambiguous.

#### 3.2 New File: `src/errors.cr` (additions)

Add a new error class for checksum verification failures:

```crystal
# Add to: /Users/crimsonknight/open_source_coding_projects/shards/src/errors.cr

class ChecksumMismatch < Error
  def initialize(package_name : String, expected : String, actual : String)
    super "Checksum verification failed for #{package_name}.\n" \
          "  Expected: #{expected}\n" \
          "  Got:      #{actual}\n" \
          "This may indicate the source has been tampered with or force-pushed.\n" \
          "Run `shards update #{package_name}` to re-resolve, or use `--skip-verify` to bypass."
  end
end
```

#### 3.3 Modified File: `src/lock.cr`

The lock file writer must emit the `checksum` field. The lock file reader must parse it. The `Package` class needs a `checksum` property.

**Changes to `Lock.write`** (lines 67-87 of `/Users/crimsonknight/open_source_coding_projects/shards/src/lock.cr`):

Add a `checksum` line after the `version` line in the YAML output:

```crystal
def self.write(packages : Array(Package), override_path : String?, io : IO)
  # ... existing header code ...
  packages.sort_by!(&.name).each do |package|
    key = package.resolver.class.key

    io << "  " << package.name << ":#{package.is_override ? " # Overridden" : nil}\n"
    io << "    " << key << ": " << package.resolver.source << '\n'
    io << "    version: " << package.version.value << '\n'
    if checksum = package.checksum
      io << "    checksum: " << checksum << '\n'
    end
    io << '\n'
  end
end
```

**Changes to `Lock.from_yaml`** (lines 20-58):

The lock parsing uses `Dependency.from_yaml` which reads key-value pairs. The `checksum` key is currently unknown to resolvers and would be stored in `params`. We need to extract it before passing to the resolver. This is handled in `Dependency.from_yaml`.

#### 3.4 Modified File: `src/dependency.cr`

In the `Dependency.from_yaml` method, the parser reads all key-value pairs in a mapping. Keys that match a resolver class are used for resolver construction; remaining keys go to `params` for `parse_requirement`. The `checksum` key needs to be extracted separately and stored.

**Changes to `Dependency.from_yaml`** (around line 14-44 of `/Users/crimsonknight/open_source_coding_projects/shards/src/dependency.cr`):

```crystal
def self.from_yaml(pull : YAML::PullParser)
  mapping_start = pull.location
  name = pull.read_scalar
  pull.read_mapping do
    resolver_data = nil
    params = Hash(String, String).new
    checksum : String? = nil

    until pull.kind.mapping_end?
      location = pull.location
      key, value = pull.read_scalar, pull.read_scalar

      if key == "checksum"
        checksum = value
      elsif type = Resolver.find_class(key)
        if resolver_data
          raise YAML::ParseException.new("Duplicate resolver mapping ...", *location)
        else
          resolver_data = {type: type, key: key, source: value}
        end
      else
        params[key] = value
      end
    end

    # ... existing resolver construction ...

    dep = Dependency.new(name, resolver, requirement)
    dep.checksum = checksum
    dep
  end
end
```

Add a `checksum` property to `Dependency`:

```crystal
property checksum : String?
```

#### 3.5 Modified File: `src/package.cr`

Add a `checksum` property to `Package`:

```crystal
# In: /Users/crimsonknight/open_source_coding_projects/shards/src/package.cr

property checksum : String?

def initialize(@name, @resolver, @version, @is_override = false, @checksum = nil)
end
```

Update `def_equals` to include checksum:

```crystal
def_equals @name, @resolver, @version
# Note: checksum is intentionally NOT part of equality.
# Two packages are "equal" if they have the same name, resolver, and version.
# Checksum is metadata for verification, not identity.
```

Update `as_package?` in `Dependency` to propagate checksum:

```crystal
def as_package?
  # ... existing version resolution ...
  pkg = Package.new(@name, @resolver, version)
  pkg.checksum = @checksum
  pkg
end
```

**Checksum computation during install** -- add a method to `Package`:

```crystal
def compute_checksum : String?
  return nil unless File.exists?(install_path)
  Checksum.compute(install_path)
end
```

#### 3.6 Modified File: `src/commands/install.cr`

This is the core integration point. After installing packages, compute or verify checksums.

**Changes to `Install#run`** (line 8-46 of `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/install.cr`):

```crystal
def run
  # ... existing setup through install(packages) ...
  install(packages)

  # Checksum verification/computation
  unless Shards.skip_verify?
    verify_or_compute_checksums(packages)
  else
    Log.warn { "Checksum verification skipped (--skip-verify)" }
  end

  AIDocsInstaller.new(path).install(packages)

  if generate_lockfile?(packages)
    write_lockfile(packages)
  elsif !Shards.frozen?
    File.touch(lockfile_path)
  end

  touch_install_path
  check_crystal_version(packages)
end
```

Add the verification method:

```crystal
private def verify_or_compute_checksums(packages : Array(Package))
  packages.each do |package|
    next unless package.installed?
    next if package.resolver.is_a?(PathResolver) && !Shards.frozen?
    # Path dependencies in non-frozen mode are symlinks, skip verification
    # but in frozen mode they should still be verified

    if expected = package.checksum
      # Verify against locked checksum
      actual = package.compute_checksum
      if actual && actual != expected
        raise ChecksumMismatch.new(package.name, expected, actual)
      end
      Log.debug { "Checksum verified for #{package.name}" }
    else
      # No checksum in lock file yet (migration case) -- compute and store
      if computed = package.compute_checksum
        package.checksum = computed
        Log.debug { "Computed checksum for #{package.name}: #{computed}" }
      end
    end
  end
end
```

**Important consideration for path resolver**: Path dependencies are installed as symlinks (see `PathResolver#install_sources` line 38-42 of `path.cr`). Since the symlink points to the original directory, the checksum would reflect the current state of that directory, which may change between installs. In non-frozen mode, this is expected behavior for path dependencies (they are local development deps). In frozen mode, verification should still apply.

The `outdated_lockfile?` method should also consider missing checksums:

```crystal
private def outdated_lockfile?(packages)
  return true if locks.version != Shards::Lock::CURRENT_VERSION
  return true if packages.size != locks.shards.size
  # Trigger lockfile rewrite if any locked package is missing a checksum
  return true if locks.shards.any? { |pkg| pkg.checksum.nil? }
  packages.index_by(&.name) != locks.shards.index_by(&.name)
end
```

#### 3.7 Modified File: `src/commands/update.cr`

Update always regenerates the lock file. Checksums should be computed for all packages after installation.

**Changes** (around line 24-38 of `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/update.cr`):

```crystal
def run(shards : Array(String))
  # ... existing setup through install(packages) ...
  install(packages)

  # Compute checksums for all packages (update always regenerates)
  compute_checksums(packages)

  AIDocsInstaller.new(path).install(packages)

  if generate_lockfile?(packages)
    write_lockfile(packages)
  else
    File.touch(lockfile_path)
  end

  touch_install_path
  check_crystal_version(packages)
end

private def compute_checksums(packages : Array(Package))
  packages.each do |package|
    next unless package.installed?
    if computed = package.compute_checksum
      package.checksum = computed
    end
  end
end
```

#### 3.8 Modified File: `src/commands/lock.cr`

The `lock` command resolves dependencies without installing them. Since sources are not downloaded to `lib/`, we cannot compute checksums from the install path. Two approaches:

**Option A (Recommended)**: For the `lock` command, compute checksums from the resolver's local cache. For git-based resolvers, we can checkout to a temp directory, hash, and clean up. This is expensive and may not be necessary for a lock-only operation.

**Option B (Simpler)**: The `lock` command does not compute checksums. Checksums are populated on the first `shards install`. The lock file will have `checksum: ~` or simply omit the field.

**Recommendation**: Option B. The `lock` command is rarely used and is primarily for CI environments where `install` follows immediately. Checksums are populated on install.

No changes to lock.cr are required if we take Option B. The lock writer already handles `nil` checksums by omitting the line.

#### 3.9 Modified File: `src/cli.cr`

Add `--skip-verify` flag.

**Changes** (around line 60-85 of `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr`):

```crystal
opts.on("--skip-verify", "Skip checksum verification during install") do
  self.skip_verify = true
end
```

#### 3.10 Modified File: `src/config.cr`

Add the `skip_verify` class property.

```crystal
# Add to: /Users/crimsonknight/open_source_coding_projects/shards/src/config.cr
class_property? skip_verify = false
```

#### 3.11 Modified File: `src/commands/command.cr`

The `write_lockfile` method calls `Lock.write`. No changes needed since `Lock.write` already receives packages which will now carry checksum data.

However, `Lock.write` currently writes to `LOCK_FILENAME` (a constant, "shard.lock"). Looking at line 73:

```crystal
Shards::Lock.write(packages, override_path, LOCK_FILENAME)
```

This calls the `write(packages, override_path, path)` overload which opens a File. The lock writer iterates packages and accesses `package.checksum`. No changes needed here.

#### 3.12 Lock file format changes

**New format** (backward compatible):

```yaml
version: 2.0
shards:
  some_shard:
    git: https://github.com/user/repo.git
    version: 1.2.3
    checksum: sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890

  path_dep:
    path: ../local/dep
    version: 0.1.0
    checksum: sha256:fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321
```

**Backward compatibility**: When parsing an old lock file without `checksum` keys, `package.checksum` will be `nil`. The install command treats this as "no checksum available yet" and computes + stores one on the next lock write. This means upgrading is transparent: run `shards install` once, and the lock file gets checksums.

**Version**: We keep `version: 2.0` for the lock file. The checksum field is purely additive (an old shards will simply ignore unknown keys during parsing because `Dependency.from_yaml` puts unknown keys into `params`, and `parse_requirement` ignores unknown keys). So this is backward compatible without a version bump.

Actually, reviewing the code more carefully: in `Dependency.from_yaml`, unknown keys go to `params`, which is then passed to `resolver.parse_requirement(params)`. The base `Resolver#parse_requirement` only checks for `"version"` and ignores everything else. Git resolver checks for `"branch"`, `"tag"`, `"commit"`, and falls through to `super`. So a `"checksum"` key in params would simply be ignored by older versions. However, we should still extract it explicitly to avoid it being passed to `parse_requirement` at all (cleaner design, and some future resolver might choke on unexpected keys).

### 4. Testing Strategy

#### 4.1 New File: `spec/unit/checksum_spec.cr`

```crystal
# Tests for the Checksum module

require "./spec_helper"
require "../../src/checksum"

module Shards
  describe Checksum do
    it "computes deterministic checksum for directory" do
      # Create a temp directory with known files
      # Compute checksum twice, verify identical
    end

    it "detects file content changes" do
      # Create dir, compute checksum, modify a file, compute again
      # Checksums should differ
    end

    it "detects file addition" do
      # Create dir, compute, add file, compute again
    end

    it "detects file deletion" do
      # Create dir, compute, delete file, compute again
    end

    it "detects file rename" do
      # Rename a file (same content, different path)
    end

    it "is order-independent (files sorted)" do
      # Create files in different orders, checksums should be identical
    end

    it "excludes .git directory" do
      # Add a .git/ dir with content, verify it doesn't affect checksum
    end

    it "excludes lib symlink" do
      # Add a lib/ entry, verify it doesn't affect checksum
    end

    it "handles empty directory" do
      # Empty dir should produce a consistent (empty) hash
    end

    it "handles nested directories" do
      # Deeply nested structure
    end

    it "verifies matching checksum" do
      # compute then verify returns true
    end

    it "rejects mismatched checksum" do
      # compute, modify, verify returns false
    end
  end
end
```

#### 4.2 New File: `spec/integration/checksum_install_spec.cr`

```crystal
# Integration tests for checksum verification during install

require "./spec_helper"

describe "install with checksums" do
  it "generates checksums on first install" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      lock_content = File.read("shard.lock")
      lock_content.should contain("checksum: sha256:")
    end
  end

  it "verifies checksums on subsequent install" do
    metadata = {dependencies: {web: "1.0.0"}}
    with_shard(metadata) do
      run "shards install"
      # Second install should pass (checksums match)
      run "shards install"
      assert_installed "web", "1.0.0"
    end
  end

  it "fails on checksum mismatch" do
    metadata = {dependencies: {web: "1.0.0"}}
    with_shard(metadata) do
      run "shards install"
      # Tamper with the checksum in shard.lock
      lock = File.read("shard.lock")
      tampered = lock.gsub(/checksum: sha256:[a-f0-9]+/, "checksum: sha256:0000000000000000000000000000000000000000000000000000000000000000")
      File.write("shard.lock", tampered)
      # Remove installed to force re-download
      Shards::Helpers.rm_rf("lib/web")
      File.delete("lib/.shards.info")

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      ex.stdout.should contain("Checksum verification failed")
    end
  end

  it "skips verification with --skip-verify" do
    metadata = {dependencies: {web: "1.0.0"}}
    with_shard(metadata) do
      run "shards install"
      # Tamper with checksum
      lock = File.read("shard.lock")
      tampered = lock.gsub(/checksum: sha256:[a-f0-9]+/, "checksum: sha256:0000000000000000000000000000000000000000000000000000000000000000")
      File.write("shard.lock", tampered)
      Shards::Helpers.rm_rf("lib/web")
      File.delete("lib/.shards.info")

      output = run "shards install --skip-verify --no-color"
      output.should contain("Checksum verification skipped")
      assert_installed "web", "1.0.0"
    end
  end

  it "upgrades old lock file without checksums" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      # Write a lock file without checksums (old format)
      File.write "shard.lock", to_lock_yaml({web: "1.0.0"})
      run "shards install"
      # Lock file should now contain checksums
      lock_content = File.read("shard.lock")
      lock_content.should contain("checksum: sha256:")
    end
  end

  it "handles path dependencies" do
    metadata = {dependencies: {foo: {path: rel_path(:foo)}}}
    with_shard(metadata) do
      run "shards install"
      lock_content = File.read("shard.lock")
      # Path deps get checksums too
      lock_content.should contain("checksum: sha256:")
    end
  end

  it "regenerates checksums on update" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      old_lock = File.read("shard.lock")
      run "shards update"
      new_lock = File.read("shard.lock")
      # Both should have checksums
      old_lock.should contain("checksum: sha256:")
      new_lock.should contain("checksum: sha256:")
    end
  end
end
```

### 5. Data Flow Summary

**Install (first time, no lock file)**:
1. Solver resolves dependencies, produces `Array(Package)` (no checksums yet).
2. `install(packages)` downloads sources to `lib/`.
3. `verify_or_compute_checksums(packages)` computes checksums for each installed package.
4. `write_lockfile(packages)` writes lock file with checksums.

**Install (with existing lock file with checksums)**:
1. Lock file is parsed. Each `Package` in `locks.shards` has `checksum` populated.
2. Solver uses locks. Produces `Array(Package)`.
3. The packages from the solver do NOT have checksums (they come from resolution, not the lock file). We need to propagate checksums from the lock to the resolved packages.
4. **Important**: In the `Install#run` method, after solving, we need to copy checksums from `locks.shards` to the resolved packages. This is done by matching on name:

```crystal
# After solver.solve, propagate checksums from lock
if lockfile?
  lock_checksums = locks.shards.to_h { |p| {p.name, p.checksum} }
  packages.each do |pkg|
    pkg.checksum = lock_checksums[pkg.name]?
  end
end
```

5. `install(packages)` downloads sources.
6. `verify_or_compute_checksums(packages)` verifies against locked checksum.
7. Lock file is written (with same checksums, or new ones if packages changed).

**Update**:
1. Solver resolves without locks (or with partial locks).
2. Sources are installed.
3. Checksums are computed fresh for all packages.
4. Lock file is written with new checksums.

### 6. Edge Cases and Error Handling

| Scenario | Behavior |
|----------|----------|
| Old lock file without checksums | Treated as migration: checksums computed, lock file rewritten |
| Checksum mismatch | `ChecksumMismatch` error raised, install aborted |
| `--skip-verify` flag | Warning logged, verification skipped, install proceeds |
| Path dependency (symlink) | Checksum computed from target directory contents |
| Package already installed (cache hit) | Checksum still verified against installed content |
| `--frozen` mode with mismatch | Error raised (no way to bypass without `--skip-verify`) |
| `shards lock` (no install) | Checksums not computed (no sources available) |
| Empty package (no files) | Empty hash is still deterministic |
| Platform differences | No line ending normalization (files hashed as-is) |

### 7. Implementation Sequence

The implementation should be done in this order to maintain a compilable project at each step:

1. **Step 1**: Create `src/checksum.cr` with the `Checksum` module. No other files depend on it yet.
2. **Step 2**: Add `ChecksumMismatch` to `src/errors.cr`.
3. **Step 3**: Add `checksum` property to `Package` in `src/package.cr`, add `compute_checksum` method.
4. **Step 4**: Add `checksum` property to `Dependency` in `src/dependency.cr`, update `from_yaml` to parse the `checksum` key, update `as_package?` to propagate it.
5. **Step 5**: Update `Lock.write` in `src/lock.cr` to emit the `checksum` field.
6. **Step 6**: Add `skip_verify` class property to `src/config.cr`.
7. **Step 7**: Add `--skip-verify` option to `src/cli.cr`.
8. **Step 8**: Update `src/commands/install.cr` with verification logic and checksum propagation from locks.
9. **Step 9**: Update `src/commands/update.cr` with checksum computation.
10. **Step 10**: Create `spec/unit/checksum_spec.cr` with unit tests.
11. **Step 11**: Create `spec/integration/checksum_install_spec.cr` with integration tests.
12. **Step 12**: Update `spec/unit/lock_spec.cr` to test checksum parsing and writing.

### 8. Success Criteria

1. **SC-1**: Running `shards install` on a project with no lock file produces a `shard.lock` where every dependency entry has a `checksum: sha256:...` line.
2. **SC-2**: Running `shards install` again (with existing lock file and installed deps) completes successfully without errors (checksums match).
3. **SC-3**: Tampering with a checksum value in `shard.lock` and running `shards install` (after removing the installed dependency from `lib/`) produces a `ChecksumMismatch` error with a clear message naming the affected package.
4. **SC-4**: Running `shards install --skip-verify` with a tampered checksum succeeds but prints a warning.
5. **SC-5**: An old `shard.lock` (without checksum fields) is accepted; after `shards install`, the lock file is rewritten with checksums.
6. **SC-6**: `shards update` produces a lock file with fresh checksums for all dependencies.
7. **SC-7**: Path dependencies receive checksums based on their directory contents.
8. **SC-8**: The checksum for a given set of files is identical regardless of the order in which files are enumerated by the filesystem (determinism).
9. **SC-9**: All existing tests continue to pass (backward compatibility).
10. **SC-10**: The `checksum` field in `shard.lock` is silently ignored by older versions of shards (verified by code analysis of `Dependency.from_yaml`).

### 9. Validation Steps

**Test 1: Fresh install with checksum generation**
```bash
mkdir /tmp/test-checksums && cd /tmp/test-checksums
cat > shard.yml <<EOF
name: test
version: 0.1.0
dependencies:
  ameba:
    github: crystal-ameba/ameba
    version: ~> 1.6
EOF
shards install
grep "checksum: sha256:" shard.lock  # Should show checksum lines
```

**Test 2: Install with valid checksums (passes)**
```bash
# Run install again -- should succeed silently
shards install
echo $?  # Should be 0
```

**Test 3: Install with tampered content (fails)**
```bash
# Tamper with checksum in shard.lock
sed -i 's/checksum: sha256:.*/checksum: sha256:0000000000000000000000000000000000000000000000000000000000000000/' shard.lock
rm -rf lib/ameba lib/.shards.info
shards install 2>&1  # Should fail with ChecksumMismatch error
```

**Test 4: Skip verification**
```bash
shards install --skip-verify 2>&1  # Should succeed with warning
```

**Test 5: Upgrade from old lock file format**
```bash
# Remove checksum lines from shard.lock
sed -i '/checksum:/d' shard.lock
shards install
grep "checksum: sha256:" shard.lock  # Should show new checksums
```

**Test 6: Path dependency checksumming**
```bash
mkdir -p /tmp/test-path-dep/my_lib/src
cat > /tmp/test-path-dep/my_lib/shard.yml <<EOF
name: my_lib
version: 0.1.0
EOF
echo "module MyLib; end" > /tmp/test-path-dep/my_lib/src/my_lib.cr

cd /tmp/test-checksums
cat > shard.yml <<EOF
name: test
version: 0.1.0
dependencies:
  my_lib:
    path: /tmp/test-path-dep/my_lib
EOF
shards install
grep "checksum: sha256:" shard.lock  # Should have checksum for my_lib
```

**Test 7: Run the test suite**
```bash
cd /Users/crimsonknight/open_source_coding_projects/shards
crystal spec spec/unit/checksum_spec.cr
crystal spec spec/unit/lock_spec.cr
crystal spec spec/integration/checksum_install_spec.cr
crystal spec  # Full suite -- all existing tests must pass
```

### 10. Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Filesystem-dependent file ordering breaks determinism | Files are sorted lexicographically before hashing |
| Large repositories slow down checksumming | SHA-256 is fast; a 100MB repo takes <1s. If needed, consider parallel hashing later |
| Path dependencies change between installs | In non-frozen mode, path dep checksums are computed but verification is lenient (warn, don't fail). In frozen mode, verification is strict. |
| Symlink loops | The `lib` symlink is explicitly excluded. Other symlinks are read as files. |
| Binary files with platform-specific content | No normalization is applied; checksums are platform-specific. This matches the reality that compiled artifacts may differ. Source-only shards will hash identically. |
| Breaking old shards versions reading new lock files | The `checksum` key is ignored by old `Dependency.from_yaml` (goes to `params`, then ignored by `parse_requirement`). Verified by code analysis. |

---

### Critical Files for Implementation

- `/Users/crimsonknight/open_source_coding_projects/shards/src/lock.cr` - Lock file reader/writer where checksum serialization/deserialization must be added
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/install.cr` - Core install command where checksum verification logic integrates after package download
- `/Users/crimsonknight/open_source_coding_projects/shards/src/dependency.cr` - Dependency YAML parser where the `checksum` field must be extracted and propagated to Package
- `/Users/crimsonknight/open_source_coding_projects/shards/src/package.cr` - Package class that needs the `checksum` property and `compute_checksum` method
- `/Users/crimsonknight/open_source_coding_projects/shards/src/postinstall_info.cr` - Pattern reference for SHA-256 usage convention (`sha256:` prefix) already established in the codebase