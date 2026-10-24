require "./spec_helper"

private SHA256_CHECKSUM   = /checksum: sha256:[0-9a-f]{64}/
private GIT_TREE_CHECKSUM = /checksum: git-tree:[0-9a-f]+/

private def reset_install(name)
  Shards::Helpers.rm_rf(install_path(name))
  {".shards.info", ".shards.postinstall"}.each do |state_file|
    File.delete(install_path(state_file)) if File.exists?(install_path(state_file))
  end
end

describe "checksum pinning" do
  it "fresh install records sha256 checksums in shard.lock" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards install"
      assert_installed "web", "2.1.0"

      lock_content = File.read("shard.lock")
      lock_content.should match(SHA256_CHECKSUM)
      lock_content.should_not contain("git-tree:")
    end
  end

  it "records the sha256 of the installed files" do
    with_shard({dependencies: {web: "2.1.0"}}) do
      run "shards install --no-color"
      File.read("shard.lock").should contain("checksum: #{Shards::Checksum.compute(install_path("web"))}")
    end
  end

  it "subsequent install passes when checksums match" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards install"
      run "shards install"
      assert_installed "web", "2.1.0"
    end
  end

  it "a mismatched sha256 checksum fails verification" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards install"
      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256:#{"0" * 64}"))
      reset_install("web")

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
    end
  end

  it "--frozen rejects a mismatched sha256 checksum" do
    with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}) do
      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256:#{"0" * 64}"))

      ex = expect_raises(FailedCommand) { run "shards install --frozen --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
    end
  end

  it "does not accept a checksum verification bypass" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards install"

      ex = expect_raises(FailedCommand) { run "shards install --skip-verify --no-color" }
      (ex.stdout + ex.stderr).should contain("--skip-verify")
    end
  end

  # Ordering matters more than the check itself. `made.txt` is the marker that
  # the `post` fixture's postinstall script ran, so its ABSENCE is the assertion.
  it "fails BEFORE running a dependency's postinstall script when the checksum does not match" do
    with_shard({dependencies: {post: "*"}}) do
      run "shards install"
      File.exists?(install_path("post", "made.txt")).should be_true

      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256:#{"0" * 64}"))
      reset_install("post")

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed")
      File.exists?(install_path("post", "made.txt")).should be_false
    end
  end

  it "records the checksum before the postinstall script changes the directory" do
    with_shard({dependencies: {post: "*"}}) do
      run "shards install"
      File.exists?(install_path("post", "made.txt")).should be_true
      reset_install("post")

      run "shards install --frozen --no-color"
      File.exists?(install_path("post", "made.txt")).should be_true
    end
  end

  it "does not accept a checksum warning bypass" do
    with_shard({dependencies: {post: "*"}}) do
      run "shards install"

      ex = expect_raises(FailedCommand) { run "shards install --checksum-warn --no-color" }
      (ex.stdout + ex.stderr).should contain("--checksum-warn")
    end
  end

  describe "trust on first use" do
    it "records a brand-new dependency and prints a warning" do
      with_shard({dependencies: {web: "*"}}) do
        output = run "shards install --no-color"
        output.should contain("TRUST ON FIRST USE: web")
        File.read("shard.lock").should match(SHA256_CHECKSUM)
      end
    end

    it "records only the dependency that is new to an existing lock" do
      with_shard({dependencies: {web: "*", pg: "*"}}, {web: "2.1.0"}) do
        output = run "shards install --no-color"
        output.should contain("TRUST ON FIRST USE: pg")
        output.should_not contain("TRUST ON FIRST USE: web")
        assert_installed "pg"
        File.read("shard.lock").scan(SHA256_CHECKSUM).size.should eq(2)
      end
    end
  end

  describe "lock entries without a checksum" do
    it "fail a non-frozen install" do
      with_shard({dependencies: {web: "*"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        ex = expect_raises(FailedCommand) { run "shards install --no-color" }
        (ex.stdout + ex.stderr).should contain("shard.lock has no checksum for: web")
        (ex.stdout + ex.stderr).should contain("minecart update web")
        Dir.exists?(install_path("web")).should be_false
        File.read("shard.lock").should_not contain("checksum:")
      end
    end

    it "fail --frozen before anything is installed" do
      with_shard({dependencies: {web: "2.1.0", pg: "0.2.1"}}, {web: "2.1.0", pg: "0.2.1"}) do
        lock_content = File.read("shard.lock")
        File.write("shard.lock", lock_content.sub(/(  pg:\n(?:    .*\n)*?)    checksum: .*\n/) { $1 })
        File.read("shard.lock").scan(/checksum:/).size.should eq(1)

        ex = expect_raises(FailedCommand) { run "shards install --frozen --no-color" }
        (ex.stdout + ex.stderr).should contain("shard.lock has no checksum for: pg")
        Dir.exists?(install_path("web")).should be_false
        Dir.exists?(install_path("pg")).should be_false
      end
    end

    it "fail --production the same way" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        ex = expect_raises(FailedCommand) { run "shards install --production --no-color" }
        (ex.stdout + ex.stderr).should contain("shard.lock has no checksum for: web")
      end
    end

    it "install with --allow-missing-checksums, which says so and records sha256" do
      with_shard({dependencies: {web: "*"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        output = run "shards install --allow-missing-checksums --no-color"
        output.should contain("--allow-missing-checksums: shard.lock has no sha256 checksum for web")
        assert_installed "web", "2.1.0"
        File.read("shard.lock").should match(SHA256_CHECKSUM)
      end
    end

    it "install with --frozen --allow-missing-checksums and leave the lock unchanged" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        lock_before = File.read("shard.lock")

        output = run "shards install --frozen --allow-missing-checksums --no-color"
        output.should contain("--allow-missing-checksums: shard.lock has no sha256 checksum for web")
        output.should contain("TRUST ON FIRST USE: web")
        output.should contain("for this install only")
        assert_installed "web", "2.1.0"
        File.read("shard.lock").should eq(lock_before)
      end
    end

    it "are recorded by `update`" do
      with_shard({dependencies: {web: "~> 1.0"}}, {web: "1.2.0"}, lock_checksum_kind: :none) do
        run "shards update --no-color"
        File.read("shard.lock").should match(SHA256_CHECKSUM)
        run "shards install --frozen --no-color"
      end
    end
  end

  it "--allow-missing-checksums never accepts a mismatched checksum" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards install"
      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256:#{"0" * 64}"))
      reset_install("web")

      ex = expect_raises(FailedCommand) { run "shards install --allow-missing-checksums --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed")
    end
  end

  describe "legacy git-tree (SHA-1) lock entries" do
    it "still verify in a normal install, with a notice to upgrade" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        output = run "shards install --no-color"
        output.should contain("legacy git-tree (SHA-1) checksums for web")
        output.should contain("minecart lock --update-checksums")
        assert_installed "web", "2.1.0"
      end
    end

    it "fail verification when the tree id does not match" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        File.write("shard.lock", File.read("shard.lock").gsub(GIT_TREE_CHECKSUM, "checksum: git-tree:#{"0" * 40}"))

        ex = expect_raises(FailedCommand) { run "shards install --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
      end
    end

    it "fail --frozen, which accepts only sha256" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        ex = expect_raises(FailedCommand) { run "shards install --frozen --no-color" }
        (ex.stdout + ex.stderr).should contain("only a legacy git-tree (SHA-1) checksum for: web")
        (ex.stdout + ex.stderr).should contain("minecart lock --update-checksums")
        Dir.exists?(install_path("web")).should be_false
      end
    end

    it "install with --frozen --allow-missing-checksums after verifying the tree id" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        output = run "shards install --frozen --allow-missing-checksums --no-color"
        output.should contain("no sha256 checksum for web")
        assert_installed "web", "2.1.0"

        File.write("shard.lock", File.read("shard.lock").gsub(GIT_TREE_CHECKSUM, "checksum: git-tree:#{"0" * 40}"))
        reset_install("web")
        ex = expect_raises(FailedCommand) { run "shards install --frozen --allow-missing-checksums --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
      end
    end

    it "upgrade to sha256 with `lock --update-checksums`, then pass --frozen" do
      with_shard({dependencies: {web: "2.1.0", pg: "0.2.1"}}, {web: "2.1.0", pg: "0.2.1"}, lock_checksum_kind: :git_tree) do
        output = run "shards lock --update-checksums --no-color"
        output.should contain("Upgraded git-tree checksums to sha256 for:")

        lock_content = File.read("shard.lock")
        lock_content.should_not contain("git-tree:")
        lock_content.scan(SHA256_CHECKSUM).size.should eq(2)
        lock_content.should contain("checksum: #{fixture_lock_checksum(git_url(:web), "2.1.0")}")

        run "shards install --frozen --no-color"
        assert_installed "web", "2.1.0"
        assert_installed "pg", "0.2.1"
      end
    end

    it "are not upgraded when the recorded tree id does not match" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        File.write("shard.lock", File.read("shard.lock").gsub(GIT_TREE_CHECKSUM, "checksum: git-tree:#{"0" * 40}"))
        lock_before = File.read("shard.lock")

        ex = expect_raises(FailedCommand) { run "shards lock --update-checksums --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
        File.read("shard.lock").should eq(lock_before)
      end
    end

    it "are upgraded to sha256 by `update`" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        run "shards update --no-color"
        File.read("shard.lock").should match(SHA256_CHECKSUM)
        File.read("shard.lock").should_not contain("git-tree:")
      end
    end

    it "upgraded by `update` exclude postinstall output from the checksum" do
      with_shard({dependencies: {post: "*"}}) do
        run "shards install --no-color"
        File.exists?(install_path("post", "made.txt")).should be_true
        sha256_lock = File.read("shard.lock")

        tree = fixture_lock_checksum(git_url(:post), Shards::Lock.from_file("shard.lock").shards.first.version.value, :git_tree)
        File.write("shard.lock", sha256_lock.gsub(SHA256_CHECKSUM, "checksum: #{tree}"))

        run "shards update --no-color"
        File.read("shard.lock").should eq(sha256_lock)
      end
    end
  end

  it "keeps recorded checksums when `lock` rewrites the lock file" do
    with_shard({dependencies: {web: "2.1.0"}}) do
      run "shards install --no-color"
      lock_before = File.read("shard.lock")

      run "shards lock --no-color"
      File.read("shard.lock").should eq(lock_before)
    end
  end

  it "path dependencies install without errors" do
    with_shard({dependencies: {foo: {path: rel_path(:foo)}}}) do
      run "shards install"
      assert_installed "foo", "0.1.0"
    end
  end

  it "--frozen installs a path dependency without a recorded checksum" do
    with_shard({dependencies: {foo: {path: rel_path(:foo)}}}) do
      run "shards install --no-color"
      File.read("shard.lock").should_not contain("checksum:")

      run "shards install --frozen --no-color"
      assert_installed "foo", "0.1.0"
    end
  end

  describe "with the require_checksum policy" do
    require_checksum_policy = <<-YAML
    version: 1
    rules:
      security:
        require_checksum: true
    YAML

    it "fails when a lock entry has no checksum, even with --allow-missing-checksums" do
      with_shard({dependencies: {web: "*"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        File.write ".minecart-policy.yml", require_checksum_policy

        ex = expect_raises(FailedCommand) { run "shards install --allow-missing-checksums --no-color" }
        (ex.stdout + ex.stderr).should contain("require_checksum")
        (ex.stdout + ex.stderr).should contain("Policy violations found")
        Dir.exists?(install_path("web")).should be_false
      end
    end

    it "installs a fresh project and records every checksum" do
      with_shard({dependencies: {web: "*"}}) do
        File.write ".minecart-policy.yml", require_checksum_policy

        run "shards install --no-color"
        assert_installed "web"
        File.read("shard.lock").should match(SHA256_CHECKSUM)
        run "shards install --frozen --no-color"
      end
    end

    it "lets `update` record the missing checksums" do
      with_shard({dependencies: {web: "*"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        File.write ".minecart-policy.yml", require_checksum_policy

        run "shards update web --no-color"
        File.read("shard.lock").should match(SHA256_CHECKSUM)
        run "shards install --frozen --no-color"
      end
    end

    it "is reported by `policy check`" do
      with_shard({dependencies: {web: "*"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        File.write ".minecart-policy.yml", require_checksum_policy

        ex = expect_raises(FailedCommand) { run "shards policy check --no-color" }
        (ex.stdout + ex.stderr).should contain("require_checksum")
      end
    end
  end
end
