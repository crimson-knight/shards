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
