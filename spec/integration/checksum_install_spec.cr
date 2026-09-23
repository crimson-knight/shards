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
      lock_content.should contain("checksum: sha256:")
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
      tampered = lock_content.gsub(/checksum: sha256:[0-9a-f]+/, "checksum: sha256:0000000000000000000000000000000000000000000000000000000000000000")
      File.write("shard.lock", tampered)

      # Delete lib/web and lib/.shards.info so it gets reinstalled
      Shards::Helpers.rm_rf(File.join("lib", "web"))
      File.delete(File.join("lib", ".shards.info")) if File.exists?(File.join("lib", ".shards.info"))

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed")
    end
  end

  it "--skip-verify bypasses checksum verification" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      assert_installed "web", "2.1.0"

      # Tamper with the checksum in shard.lock
      lock_content = File.read("shard.lock")
      tampered = lock_content.gsub(/checksum: sha256:[0-9a-f]+/, "checksum: sha256:0000000000000000000000000000000000000000000000000000000000000000")
      File.write("shard.lock", tampered)

      # Delete lib/web and lib/.shards.info so it gets reinstalled
      Shards::Helpers.rm_rf(File.join("lib", "web"))
      File.delete(File.join("lib", ".shards.info")) if File.exists?(File.join("lib", ".shards.info"))

      # With --skip-verify, should succeed despite tampered checksum
      run "shards install --skip-verify"
      assert_installed "web", "2.1.0"
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
      File.write("shard.lock", lock_content.gsub(/checksum: sha256:[0-9a-f]+/,
        "checksum: sha256:#{"0" * 64}"))
      Shards::Helpers.rm_rf(File.join("lib", "post"))
      File.delete(File.join("lib", ".shards.info")) if File.exists?(File.join("lib", ".shards.info"))

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed")

      # The whole point: the script must NOT have run.
      File.exists?(install_path("post", "made.txt")).should be_false
    end
  end

  it "--checksum-warn downgrades a mismatch to a warning and proceeds" do
    with_shard({dependencies: {post: "*"}}) do
      run "shards install"

      lock_content = File.read("shard.lock")
      File.write("shard.lock", lock_content.gsub(/checksum: sha256:[0-9a-f]+/,
        "checksum: sha256:#{"0" * 64}"))
      Shards::Helpers.rm_rf(File.join("lib", "post"))
      File.delete(File.join("lib", ".shards.info")) if File.exists?(File.join("lib", ".shards.info"))
      # `.shards.postinstall` records that this script already ran for this
      # package; without clearing it the reinstall skips the script and the
      # marker below would be missing for a reason unrelated to checksums.
      postinstall_info = File.join("lib", ".shards.postinstall")
      File.delete(postinstall_info) if File.exists?(postinstall_info)

      output = run "shards install --no-color --checksum-warn"
      output.should contain("Checksum mismatch for post")
      assert_installed "post", "0.1.0"
      File.exists?(install_path("post", "made.txt")).should be_true
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
      lock_after.should contain("checksum: sha256:")
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
      lock_after_install.should contain("checksum: sha256:")

      run "shards update"

      lock_after_update = File.read("shard.lock")
      lock_after_update.should contain("checksum: sha256:")
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
end
