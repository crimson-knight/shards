require "./spec_helper"

describe "checksum pinning" do
  it "fresh install generates checksums in shard.lock" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      assert_installed "web", "2.1.0"

      lock_content = File.read("shard.lock")
      lock_content.should contain("checksum: git-tree:")
    end
  end

  it "subsequent install passes when checksums match" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      assert_installed "web", "2.1.0"

      # Second install should succeed (checksums match)
      run "shards install"
      assert_installed "web", "2.1.0"
    end
  end

  it "tampered checksum fails verification" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      assert_installed "web", "2.1.0"

      # Tamper with the checksum in shard.lock
      lock_content = File.read("shard.lock")
      tampered = lock_content.gsub(/checksum: git-tree:[0-9a-f]+/, "checksum: git-tree:#{"0" * 40}")
      File.write("shard.lock", tampered)

      # Delete lib/web and lib/.shards.info so it gets reinstalled
      Shards::Helpers.rm_rf(File.join("lib", "web"))
      File.delete(File.join("lib", ".shards.info")) if File.exists?(File.join("lib", ".shards.info"))

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed")
    end
  end

  it "does not accept a checksum verification bypass" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      assert_installed "web", "2.1.0"

      ex = expect_raises(FailedCommand) { run "shards install --skip-verify --no-color" }
      (ex.stdout + ex.stderr).should contain("--skip-verify")
    end
  end

  # Ordering matters more than the check itself. Verification used to run after
  # `install(packages)`, which is the loop that executes every dependency's
  # postinstall script. A mismatch was therefore reported only after the
  # attacker's code had already run. These specs pin the ordering, not just the
  # outcome: `made.txt` is the marker that the `post` fixture's script ran, so
  # its ABSENCE is the actual assertion.
  it "fails BEFORE running a dependency's postinstall script when the checksum does not match" do
    with_shard({dependencies: {post: "*"}}) do
      run "shards install"
      File.exists?(install_path("post", "made.txt")).should be_true

      # Force a mismatch and a reinstall.
      lock_content = File.read("shard.lock")
      File.write("shard.lock", lock_content.gsub(/checksum: git-tree:[0-9a-f]+/,
        "checksum: git-tree:#{"0" * 40}"))
      Shards::Helpers.rm_rf(File.join("lib", "post"))
      File.delete(File.join("lib", ".shards.info")) if File.exists?(File.join("lib", ".shards.info"))

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed")

      # The whole point: the script must NOT have run.
      File.exists?(install_path("post", "made.txt")).should be_false
    end
  end

  it "does not accept a checksum warning bypass" do
    with_shard({dependencies: {post: "*"}}) do
      run "shards install"

      ex = expect_raises(FailedCommand) { run "shards install --checksum-warn --no-color" }
      (ex.stdout + ex.stderr).should contain("--checksum-warn")
    end
  end

  it "old lockfile without checksums gets upgraded" do
    metadata = {
      dependencies: {web: "*"},
    }
    lock = {web: "2.1.0"}
    with_shard(metadata, lock) do
      # The lock was written without checksums (old format)
      lock_before = File.read("shard.lock")
      lock_before.should_not contain("checksum:")

      run "shards install"
      assert_installed "web", "2.1.0"

      # After install, lock file should be upgraded with checksums
      lock_after = File.read("shard.lock")
      lock_after.should contain("checksum: git-tree:")
    end
  end

  it "update regenerates checksums" do
    metadata = {
      dependencies: {web: "~> 1.0"},
    }
    with_shard(metadata) do
      run "shards install"
      assert_installed "web", "1.2.0"

      lock_after_install = File.read("shard.lock")
      directory_checksum = Shards::Checksum.compute(install_path("web"))
      legacy_lock = lock_after_install.sub(/checksum: git-tree:[0-9a-f]+/, "checksum: #{directory_checksum}")
      File.write("shard.lock", legacy_lock)
      legacy_lock.should contain("checksum: sha256:")

      run "shards update"

      lock_after_update = File.read("shard.lock")
      lock_after_update.should contain("checksum: git-tree:")
      lock_after_update.should_not contain("checksum: sha256:")
    end
  end

  it "path dependencies install without errors" do
    metadata = {
      dependencies: {foo: {path: rel_path(:foo)}},
    }
    with_shard(metadata) do
      run "shards install"
      assert_installed "foo", "0.1.0"
    end
  end

  it "installs a legacy directory checksum lock" do
    with_shard({dependencies: {web: "2.1.0"}}) do
      run "shards install --no-color"
      checksum = Shards::Checksum.compute(install_path("web"))
      lock_content = File.read("shard.lock").sub(/checksum: git-tree:[0-9a-f]+/, "checksum: #{checksum}")
      File.write("shard.lock", lock_content)
      lock_content.should contain("checksum: sha256:")

      Shards::Helpers.rm_rf(install_path("web"))
      File.delete(install_path(".shards.info")) if File.exists?(install_path(".shards.info"))

      run "shards install --frozen --no-color"
      assert_installed "web", "2.1.0"
      File.read("shard.lock").should contain("checksum: sha256:")
    end
  end

  it "installs a mixed lock containing directory and Git tree checksums" do
    with_shard({dependencies: {pg: "0.2.1", web: "2.1.0"}}) do
      run "shards install --no-color"
      checksum = Shards::Checksum.compute(install_path("pg"))
      lock_content = File.read("shard.lock").sub(/checksum: git-tree:[0-9a-f]+/, "checksum: #{checksum}")
      File.write("shard.lock", lock_content)

      lock_content.should contain("checksum: sha256:")
      lock_content.should contain("checksum: git-tree:")
      run "shards install --frozen --no-color"
    end
  end

  it "warns about missing frozen checksums for already installed dependencies" do
    with_shard({dependencies: {web: "2.1.0"}}) do
      run "shards install --no-color"
      File.write("shard.lock", File.read("shard.lock").gsub(/    checksum: .*\n/, ""))

      output = run "shards install --frozen --no-color"
      output.should contain("has no checksum in shard.lock")
      output.should contain("this will become an error next release")
    end
  end
end
