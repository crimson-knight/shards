require "./spec_helper"

private SHA256_CHECKSUM        = /checksum: sha256-v2:[0-9a-f]{64}/
private LEGACY_SHA256_CHECKSUM = /checksum: sha256:[0-9a-f]{64}/
private GIT_TREE_CHECKSUM      = /checksum: git-tree:[0-9a-f]+/

private def reset_install(name)
  Shards::Helpers.rm_rf(install_path(name))
  {".shards.info", ".shards.postinstall"}.each do |state_file|
    File.delete(install_path(state_file)) if File.exists?(install_path(state_file))
  end
end

describe "checksum pinning" do
  it "fresh install records sha256-v2 checksums in shard.lock" do
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
      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256-v2:#{"0" * 64}"))
      reset_install("web")

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
    end
  end

  it "--frozen rejects a mismatched sha256 checksum" do
    with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}) do
      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256-v2:#{"0" * 64}"))

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

      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256-v2:#{"0" * 64}"))
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
        output.should contain("--allow-missing-checksums: shard.lock has no checksum for web")
        assert_installed "web", "2.1.0"
        File.read("shard.lock").should match(SHA256_CHECKSUM)
      end
    end

    it "install with --frozen --allow-missing-checksums and leave the lock unchanged" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
        lock_before = File.read("shard.lock")

        output = run "shards install --frozen --allow-missing-checksums --no-color"
        output.should contain("--allow-missing-checksums: shard.lock has no checksum for web")
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
      File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256-v2:#{"0" * 64}"))
      reset_install("web")

      ex = expect_raises(FailedCommand) { run "shards install --allow-missing-checksums --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed")
    end
  end

  describe "legacy git-tree (SHA-1) lock entries" do
    it "still verify in a normal install, with a notice to upgrade" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        output = run "shards install --no-color"
        output.should contain("legacy (git-tree or sha256 v1) checksums for web")
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

    it "still verify under --frozen, and a tree id that does not match fails" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :git_tree) do
        lock_before = File.read("shard.lock")
        run "shards install --frozen --no-color"
        assert_installed "web", "2.1.0"
        File.read("shard.lock").should eq(lock_before)

        File.write("shard.lock", lock_before.gsub(GIT_TREE_CHECKSUM, "checksum: git-tree:#{"0" * 40}"))
        reset_install("web")
        ex = expect_raises(FailedCommand) { run "shards install --frozen --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
      end
    end

    it "upgrade to sha256-v2 with `lock --update-checksums`, then pass --frozen" do
      with_shard({dependencies: {web: "2.1.0", pg: "0.2.1"}}, {web: "2.1.0", pg: "0.2.1"}, lock_checksum_kind: :git_tree) do
        output = run "shards lock --update-checksums --no-color"
        output.should contain("Upgraded legacy checksums to sha256-v2 for:")

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

    it "are upgraded to sha256-v2 by `update`" do
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

  # Lock entries written by Minecart 2025.11.25.8 and earlier record `sha256:`
  # (v1). They keep verifying with v1's rules and stay as written until the
  # dependency is re-resolved.
  describe "legacy sha256 (v1) lock entries" do
    it "verify under --frozen with their original rules, and a tampered one fails" do
      with_shard({dependencies: {web: "2.1.0", post: "*"}}, {web: "2.1.0", post: "0.1.0"}, lock_checksum_kind: :legacy_sha256) do
        lock_before = File.read("shard.lock")
        lock_before.scan(LEGACY_SHA256_CHECKSUM).size.should eq(2)

        run "shards install --frozen --no-color"
        assert_installed "web", "2.1.0"
        File.exists?(install_path("post", "made.txt")).should be_true
        run "shards install --frozen --no-color"
        File.read("shard.lock").should eq(lock_before)

        File.write("shard.lock", lock_before.sub(LEGACY_SHA256_CHECKSUM, "checksum: sha256:#{"0" * 64}"))
        reset_install("web")
        ex = expect_raises(FailedCommand) { run "shards install --frozen --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for")
      end
    end

    it "stay as written when `update` does not re-resolve them, and become sha256-v2 when it does" do
      with_shard({dependencies: {web: "2.1.0", pg: "0.2.1"}}, {web: "2.1.0", pg: "0.2.1"}, lock_checksum_kind: :legacy_sha256) do
        legacy_web = fixture_lock_checksum(git_url(:web), "2.1.0", :legacy_sha256)
        legacy_pg = fixture_lock_checksum(git_url(:pg), "0.2.1", :legacy_sha256)

        run "shards update pg --no-color"
        lock_content = File.read("shard.lock")
        lock_content.should contain("checksum: #{legacy_web}")
        lock_content.should_not contain("checksum: #{legacy_pg}")
        lock_content.should contain("checksum: #{fixture_lock_checksum(git_url(:pg), "0.2.1")}")

        run "shards update --no-color"
        lock_content = File.read("shard.lock")
        lock_content.should_not match(LEGACY_SHA256_CHECKSUM)
        lock_content.should contain("checksum: #{fixture_lock_checksum(git_url(:web), "2.1.0")}")
        run "shards install --frozen --no-color"
      end
    end

    it "upgrade to sha256-v2 with `lock --update-checksums`" do
      with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :legacy_sha256) do
        output = run "shards lock --update-checksums --no-color"
        output.should contain("Upgraded legacy checksums to sha256-v2 for: web")
        File.read("shard.lock").should contain("checksum: #{fixture_lock_checksum(git_url(:web), "2.1.0")}")
      end
    end
  end

  # `shifty` v0.1.0 is locked, then its tag is moved to a commit whose
  # shard.yml adds `sneaky`, a new dependency with a postinstall script. The
  # moved source must fail its lock checksum before sneaky's script runs.
  describe "a moved tag that adds a dependency" do
    it "fails before any postinstall script runs, installed or not, in install and update" do
      create_git_repository "sneaky"
      create_file "sneaky", "Makefile", "all:\n\ttouch made.txt\n"
      create_git_release "sneaky", "0.1.0", {scripts: {postinstall: "make"}}

      create_git_repository "shifty"
      create_git_release "shifty", "0.1.0"

      with_shard({dependencies: {shifty: "0.1.0"}}) do
        run "shards install --no-color"
        lock_before = File.read("shard.lock")

        create_shard "shifty", "0.1.0", {dependencies: {sneaky: {git: git_url(:sneaky), version: "0.1.0"}}}
        create_git_commit "shifty", "move v0.1.0 to add a dependency"
        Dir.cd(git_path("shifty")) { run "git tag --no-sign --force v0.1.0" }

        # shifty already installed: the installed copy still matches the lock.
        ex = expect_raises(FailedCommand) { run "shards install --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for shifty")
        File.exists?(install_path("sneaky", "made.txt")).should be_false

        ex = expect_raises(FailedCommand) { run "shards update --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for shifty")
        File.exists?(install_path("sneaky", "made.txt")).should be_false

        # A fresh checkout (as in CI): nothing is installed yet.
        Shards::Helpers.rm_rf(install_path)
        ex = expect_raises(FailedCommand) { run "shards install --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for shifty")
        File.exists?(install_path("sneaky", "made.txt")).should be_false

        Shards::Helpers.rm_rf(install_path)
        ex = expect_raises(FailedCommand) { run "shards update --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for shifty")
        File.exists?(install_path("sneaky", "made.txt")).should be_false

        expect_raises(FailedCommand) { run "shards install --frozen --no-color" }
        File.exists?(install_path("sneaky", "made.txt")).should be_false
        File.read("shard.lock").should eq(lock_before)
      end
    end
  end

  # asset_pipeline ships `samples/.../lib/asset_pipeline`, a symlink to an
  # absolute path on its author's machine. sha256-v2 records the link text.
  it "installs and verifies a package that ships a symlink to an absolute path" do
    outside = File.join(tmp_path, "abslink-outside")
    Dir.mkdir_p(outside)
    File.write(File.join(outside, "payload.cr"), "puts :outside\n")

    create_git_repository "abslink"
    Dir.mkdir_p(File.join(git_path("abslink"), "samples", "lib"))
    File.symlink(outside, File.join(git_path("abslink"), "samples", "lib", "abslink"))
    create_file "abslink", "Makefile", "all:\n\ttouch made.txt\n"
    create_git_release "abslink", "0.1.0", {scripts: {postinstall: "make"}}

    with_shard({dependencies: {abslink: "0.1.0"}}) do
      run "shards install --no-color"
      File.read("shard.lock").should contain("checksum: #{fixture_lock_checksum(git_url(:abslink), "0.1.0")}")
      File.readlink(install_path("abslink", "samples", "lib", "abslink")).should eq(outside)
      File.exists?(install_path("abslink", "made.txt")).should be_true

      # The link is never followed: what it points at is not part of the lock.
      File.write(File.join(outside, "payload.cr"), "puts :changed\n")
      run "shards install --frozen --no-color"

      reset_install("abslink")
      run "shards install --frozen --no-color"
      File.exists?(install_path("abslink", "made.txt")).should be_true

      # Moving the link elsewhere changes the source and fails verification.
      Dir.cd(git_path("abslink")) do
        File.delete(File.join("samples", "lib", "abslink"))
        File.symlink(File.join(outside, "elsewhere"), File.join("samples", "lib", "abslink"))
      end
      create_git_commit "abslink", "repoint the link"
      Dir.cd(git_path("abslink")) { run "git tag --no-sign --force v0.1.0" }
      reset_install("abslink")
      ex = expect_raises(FailedCommand) { run "shards install --frozen --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for abslink")
      File.exists?(install_path("abslink", "made.txt")).should be_false
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

  describe "an installed package whose postinstall script already ran" do
    it "is checked against a fresh checkout, so a tampered lock checksum fails install" do
      with_shard({dependencies: {post: "*"}}) do
        run "shards install"
        File.exists?(install_path("post", "made.txt")).should be_true

        File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256-v2:#{"0" * 64}"))

        ex = expect_raises(FailedCommand) { run "shards install --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for post")
      end
    end

    it "is checked against a fresh checkout, so a tampered lock checksum fails update" do
      with_shard({dependencies: {post: "*"}}) do
        run "shards install"
        File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256-v2:#{"0" * 64}"))

        ex = expect_raises(FailedCommand) { run "shards update --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for post")
      end
    end
  end

  # `tamper_b` depends on `tamper_a`, so `update` runs tamper_a's postinstall
  # first, and that script rewrites tamper_b's source through the shared `lib`.
  it "update verifies each copy again right before its own postinstall script" do
    create_git_repository "tamper_a"
    create_file "tamper_a", "Makefile", "all:\n\techo '# tampered' >> lib/tamper_b/src/tamper_b.cr\n"
    create_git_release "tamper_a", "0.1.0", {scripts: {postinstall: "make"}}

    create_git_repository "tamper_b"
    create_file "tamper_b", "Makefile", "all:\n\ttouch made.txt\n"
    create_git_release "tamper_b", "0.1.0", {
      dependencies: {tamper_a: {git: git_url(:tamper_a), version: "0.1.0"}},
      scripts:      {postinstall: "make"},
    }

    with_shard({dependencies: {tamper_b: "0.1.0"}}) do
      ex = expect_raises(FailedCommand) { run "shards update --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for tamper_b")
      File.exists?(install_path("tamper_b", "made.txt")).should be_false
    end
  end

  # Legacy entries leave parts of an installed copy unchecked, so the copy is
  # compared with a fresh checkout and must stay unchanged until its script runs.
  it "install verifies each copy again before its own script, whatever kind of checksum the lock holds" do
    create_git_repository "tamper_c"
    create_file "tamper_c", "Makefile", "all:\n\techo 'all:' > lib/tamper_d/Makefile\n\techo '\ttouch tampered.txt' >> lib/tamper_d/Makefile\n"
    create_git_release "tamper_c", "0.1.0", {scripts: {postinstall: "make"}}

    create_git_repository "tamper_d"
    create_file "tamper_d", "Makefile", "all:\n\ttouch made.txt\n"
    create_git_release "tamper_d", "0.1.0", {
      dependencies: {tamper_c: {git: git_url(:tamper_c), version: "0.1.0"}},
      scripts:      {postinstall: "make"},
    }

    {:sha256, :legacy_sha256, :git_tree}.each do |lock_checksum_kind|
      Shards::Helpers.rm_rf(install_path) if Dir.exists?(install_path)
      with_shard({dependencies: {tamper_d: "0.1.0"}}, {tamper_c: "0.1.0", tamper_d: "0.1.0"}, lock_checksum_kind: lock_checksum_kind) do
        ex = expect_raises(FailedCommand) { run "shards install --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for tamper_d")
        File.exists?(install_path("tamper_d", "made.txt")).should be_false
        File.exists?(install_path("tamper_d", "tampered.txt")).should be_false
      end
    end
  end

  it "`lock` records a sha256-v2 checksum for every new entry" do
    with_shard({dependencies: {web: "2.1.0", pg: "0.2.1"}}) do
      run "shards lock --no-color"
      lock_content = File.read("shard.lock")
      lock_content.should contain("checksum: #{fixture_lock_checksum(git_url(:web), "2.1.0")}")
      lock_content.should contain("checksum: #{fixture_lock_checksum(git_url(:pg), "0.2.1")}")

      run "shards install --frozen --no-color"
      assert_installed "web", "2.1.0"
    end
  end

  it "installs a package that ships a top-level lib link to a missing absolute path" do
    create_git_repository "deadlib"
    File.symlink("/nonexistent/minecart-spec-target", File.join(git_path("deadlib"), "lib"))
    create_git_release "deadlib", "0.1.0"

    with_shard({dependencies: {deadlib: "0.1.0"}}) do
      run "shards install --no-color"
      File.readlink(install_path("deadlib", "lib")).should eq("/nonexistent/minecart-spec-target")
      File.read("shard.lock").should contain("checksum: #{fixture_lock_checksum(git_url(:deadlib), "0.1.0")}")

      reset_install("deadlib")
      run "shards install --frozen --no-color"
      File.readlink(install_path("deadlib", "lib")).should eq("/nonexistent/minecart-spec-target")
    end
  end

  # `post` is already installed and its postinstall script has run. A local
  # edit to its source must stop install and update before any script runs,
  # here the script of `afterpost`, which is new to the lock.
  it "fails before any script when an installed package whose postinstall ran was edited" do
    create_git_repository "afterpost"
    create_file "afterpost", "Makefile", "all:\n\ttouch made.txt\n"
    create_git_release "afterpost", "0.1.0", {scripts: {postinstall: "make"}}

    with_shard({dependencies: {post: "*"}}) do
      run "shards install --no-color"
      File.exists?(install_path("post", "made.txt")).should be_true
      run "shards install --frozen --no-color"

      File.write(install_path("post", "Makefile"), "all:\n\ttouch tampered.txt\n")

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("installed copy in")
      (ex.stdout + ex.stderr).should contain("no longer matches its locked source")
    end

    with_shard({dependencies: {post: "*", afterpost: "0.1.0"}}) do
      {"shards install --no-color", "shards update --no-color"}.each do |command|
        ex = expect_raises(FailedCommand) { run command }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for post")
        File.exists?(install_path("afterpost", "made.txt")).should be_false
        File.exists?(install_path("post", "tampered.txt")).should be_false
      end
    end
  end

  # v1 skips a shard's top-level `lib/`, so after the v1 entry verifies, every
  # file of the fresh checkout (lib/ included) must be unchanged in the copy.
  it "fails before any script when a v1-locked package's own lib/ file was edited" do
    create_git_repository "v1lib"
    create_file "v1lib", "lib/tool.sh", "echo original\n"
    create_file "v1lib", "Makefile", "all:\n\tsh lib/tool.sh > made.txt\n"
    create_git_release "v1lib", "0.1.0", {scripts: {postinstall: "make"}}

    create_git_repository "after_v1lib"
    create_file "after_v1lib", "Makefile", "all:\n\ttouch made.txt\n"
    create_git_release "after_v1lib", "0.1.0", {scripts: {postinstall: "make"}}

    with_shard({dependencies: {v1lib: "0.1.0"}}, {v1lib: "0.1.0"}, lock_checksum_kind: :legacy_sha256) do
      run "shards install --frozen --no-color"
      File.exists?(install_path("v1lib", "made.txt")).should be_true
      run "shards install --frozen --no-color"

      File.write(install_path("v1lib", "lib", "tool.sh"), "touch tampered.txt\n")
    end

    with_shard({dependencies: {v1lib: "0.1.0", after_v1lib: "0.1.0"}}) do
      File.read("shard.lock").should match(LEGACY_SHA256_CHECKSUM)
      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for v1lib")
      (ex.stdout + ex.stderr).should contain("no longer matches its locked source")
      File.exists?(install_path("after_v1lib", "made.txt")).should be_false
    end
  end

  # A postinstalled package with no checksum to carry forward (the lock was
  # regenerated, or the entry has none under --allow-missing-checksums) is
  # trusted on first use from a fresh checkout, and its installed copy must
  # still match that checkout before any script runs.
  it "fails before any script when an edited postinstalled package has no checksum to carry forward" do
    create_git_repository "after_regen"
    create_file "after_regen", "Makefile", "all:\n\ttouch made.txt\n"
    create_git_release "after_regen", "0.1.0", {scripts: {postinstall: "make"}}

    with_shard({dependencies: {post: "*"}}) do
      run "shards install --no-color"
      File.write(install_path("post", "Makefile"), "all:\n\ttouch tampered.txt\n")
      lock_without_checksum = File.read("shard.lock").sub(/(  post:\n(?:    .*\n)*?)    checksum: .*\n/) { $1 }
      lock_without_checksum.should_not contain("checksum:")

      File.delete("shard.lock")
      File.write "shard.yml", to_shard_yaml({dependencies: {post: "*", after_regen: "0.1.0"}})
      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("no longer matches its locked source")
      File.exists?(install_path("after_regen", "made.txt")).should be_false
      File.exists?(install_path("post", "tampered.txt")).should be_false

      File.write("shard.lock", lock_without_checksum)
      ex = expect_raises(FailedCommand) { run "shards install --allow-missing-checksums --no-color" }
      (ex.stdout + ex.stderr).should contain("no longer matches its locked source")
      File.exists?(install_path("after_regen", "made.txt")).should be_false
      File.exists?(install_path("post", "tampered.txt")).should be_false
    end
  end

  # The installed copy is never a source of truth: removing `postinstall`
  # from the installed shard.yml must not turn off the comparison with a
  # fresh checkout, nor let the edited copy's checksum be recorded.
  it "fails before any script when the installed shard.yml drops postinstall and the Makefile is edited" do
    create_git_repository "after_manifest"
    create_file "after_manifest", "Makefile", "all:\n\ttouch made.txt\n"
    create_git_release "after_manifest", "0.1.0", {scripts: {postinstall: "make"}}

    with_shard({dependencies: {post: "*"}}) do
      run "shards install --no-color"
      lock_without_checksum = File.read("shard.lock").sub(/(  post:\n(?:    .*\n)*?)    checksum: .*\n/) { $1 }

      installed_manifest = install_path("post", "shard.yml")
      File.write(installed_manifest, "name: post\nversion: 0.1.0\n")
      File.read(installed_manifest).should_not contain("postinstall")
      File.write(install_path("post", "Makefile"), "all:\n\ttouch tampered.txt\n")

      File.write "shard.yml", to_shard_yaml({dependencies: {post: "*", after_manifest: "0.1.0"}})
      [
        {nil, "shards install --no-color"},
        {lock_without_checksum, "shards install --allow-missing-checksums --no-color"},
      ].each do |lock_content, command|
        if lock_content
          File.write("shard.lock", lock_content)
        else
          File.delete("shard.lock") if File.exists?("shard.lock")
        end

        ex = expect_raises(FailedCommand) { run command }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for post")
        (ex.stdout + ex.stderr).should contain("no longer matches its locked source")
        File.exists?(install_path("after_manifest", "made.txt")).should be_false
        File.exists?(install_path("post", "tampered.txt")).should be_false
        if lock_content
          File.read("shard.lock").should eq(lock_content)
        else
          File.exists?("shard.lock").should be_false
        end
      end
    end
  end

  # Minecart 2025.11.25.8 computed a v1 `sha256:` entry over the installed
  # copy, following a file link through the `lib` link Minecart writes. Such
  # an entry keeps verifying, fresh or already installed.
  it "verifies a v1 entry for a package whose file link points into lib/" do
    create_git_repository "linkdep"
    create_file "linkdep", "tool.sh", "echo linkdep tool\n"
    create_git_release "linkdep", "0.1.0"

    create_git_repository "linky"
    File.symlink("lib/linkdep/tool.sh", File.join(git_path("linky"), "tool.sh"))
    create_git_release "linky", "0.1.0", {dependencies: {linkdep: {git: git_url(:linkdep), version: "0.1.0"}}}

    with_shard({dependencies: {linky: "0.1.0"}}) do
      run "shards install --no-color"
      legacy_checksum = Shards::Checksum.compute_legacy_sha256(install_path("linky"))
      lock_content = File.read("shard.lock").sub(/(  linky:\n(?:    .*\n)*?)    checksum: .*\n/) { "#{$1}    checksum: #{legacy_checksum}\n" }
      lock_content.should contain("checksum: #{legacy_checksum}")
      File.write("shard.lock", lock_content)

      Shards::Helpers.rm_rf(install_path)
      run "shards install --frozen --no-color"
      run "shards install --frozen --no-color"
      File.read("shard.lock").should eq(lock_content)

      output = run "shards lock --update-checksums --no-color"
      output.should contain("Upgraded legacy checksums to sha256-v2 for: linky")
    end
  end

  it "update records the sha256 of the source, not of the installed copy" do
    with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
      run "shards install --frozen --allow-missing-checksums --no-color"
      File.read("shard.lock").should_not contain("checksum:")

      run "shards update --no-color"
      File.read("shard.lock").should contain("checksum: #{fixture_lock_checksum(git_url(:web), "2.1.0")}")
    end
  end

  it "update fails on a locally modified installed copy and leaves the lock unchanged" do
    with_shard({dependencies: {web: "2.1.0"}}, {web: "2.1.0"}, lock_checksum_kind: :none) do
      run "shards install --frozen --allow-missing-checksums --no-color"
      lock_before = File.read("shard.lock")
      File.write(install_path("web", "src/web.cr"), "# locally modified\n")

      ex = expect_raises(FailedCommand) { run "shards update --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for web")
      File.read("shard.lock").should eq(lock_before)
    end
  end

  describe "run-script" do
    it "runs a postinstall script whose lock entry matches its source" do
      with_shard({dependencies: {post: "*"}}) do
        run "shards install"
        File.delete(install_path("post", "made.txt"))

        run "shards run-script post --no-color"
        File.exists?(install_path("post", "made.txt")).should be_true
      end
    end

    it "runs the script from a fresh copy of the locked source, not an edited installed copy" do
      with_shard({dependencies: {post: "*"}}) do
        run "shards install"
        File.delete(install_path("post", "made.txt"))
        File.write(install_path("post", "Makefile"), "all:\n\ttouch tampered.txt\n")

        run "shards run-script post --no-color"
        File.exists?(install_path("post", "made.txt")).should be_true
        File.exists?(install_path("post", "tampered.txt")).should be_false
      end
    end

    it "refuses when the lock checksum does not match the source" do
      with_shard({dependencies: {post: "*"}}) do
        run "shards install"
        File.delete(install_path("post", "made.txt"))
        File.write("shard.lock", File.read("shard.lock").gsub(SHA256_CHECKSUM, "checksum: sha256-v2:#{"0" * 64}"))

        ex = expect_raises(FailedCommand) { run "shards run-script post --no-color" }
        (ex.stdout + ex.stderr).should contain("Checksum verification failed for post")
        File.exists?(install_path("post", "made.txt")).should be_false
      end
    end

    it "refuses under the block_postinstall policy" do
      with_shard({dependencies: {post: "*"}}) do
        run "shards install"
        File.delete(install_path("post", "made.txt"))
        File.write ".minecart-policy.yml", <<-YAML
        version: 1
        rules:
          security:
            block_postinstall: true
        YAML

        ex = expect_raises(FailedCommand) { run "shards run-script post --no-color" }
        (ex.stdout + ex.stderr).should contain("block_postinstall")
        File.exists?(install_path("post", "made.txt")).should be_false
      end
    end
  end
end
