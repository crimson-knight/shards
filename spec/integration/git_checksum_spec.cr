require "./spec_helper"

describe "Git dependency lock checksums" do
  it "writes a sha256 checksum for a Git dependency" do
    metadata = {dependencies: {web: "1.2.0"}}
    with_shard(metadata) do
      run "shards install --no-color"

      File.read("shard.lock").should contain("checksum: #{fixture_lock_checksum(git_url(:web), "1.2.0")}")
    end
  end

  it "rekeys every Git checksum to the sha256 of its current source" do
    metadata = {dependencies: {web: "1.2.0"}}
    with_shard(metadata, {web: "1.2.0"}, lock_checksum_kind: :git_tree) do
      fake_sha = "a" * 64
      lock_before = File.read("shard.lock").gsub(/checksum: git-tree:[0-9a-f]+/, "checksum: sha256-v2:#{fake_sha}")
      File.write("shard.lock", lock_before)

      run "shards lock --rekey --no-color"

      lock_after = File.read("shard.lock")
      lock_after.should contain("checksum: #{fixture_lock_checksum(git_url(:web), "1.2.0")}")
      lock_after.should_not contain(fake_sha)
    end
  end

  it "writes the same sha256 from two independent Git clones and installs" do
    first_project = File.join(application_path, "tree-install-one")
    second_project = File.join(application_path, "tree-install-two")
    second_clone = File.join(application_path, "web-independent-clone")
    Dir.mkdir_p(first_project)
    Dir.mkdir_p(second_project)
    run "git clone --quiet --no-hardlinks #{Process.quote(git_url(:web))} #{Process.quote(second_clone)}"

    first_tree = Dir.cd(git_path(:web)) { run("git rev-parse HEAD^{tree}").strip }
    second_tree = Dir.cd(second_clone) { run("git rev-parse HEAD^{tree}").strip }
    second_tree.should eq(first_tree)

    File.write(File.join(first_project, "shard.yml"), to_shard_yaml({dependencies: {web: "1.2.0"}}))
    File.write(File.join(second_project, "shard.yml"), to_shard_yaml({
      dependencies: {web: {git: "file://#{Path[second_clone].to_posix}", version: "1.2.0"}},
    }))

    first_output = Dir.cd(first_project) { run "minecart install --no-color" }
    second_output = Dir.cd(second_project) { run "minecart install --no-color" }
    first_output.should contain("Installing web")
    second_output.should contain("Installing web")

    first_match = /checksum: (sha256-v2:[0-9a-f]+)/.match(File.read(File.join(first_project, "shard.lock")))
    second_match = /checksum: (sha256-v2:[0-9a-f]+)/.match(File.read(File.join(second_project, "shard.lock")))
    first_match.should_not be_nil
    second_match.should_not be_nil
    if first_match && second_match
      first_match[1].should eq(second_match[1])
    end
  end

  it "rejects a force-pushed tag before running postinstall" do
    create_git_repository("moving")
    create_file("moving", "Makefile", "all:\n\ttouch made.txt\n")
    create_git_release("moving", "0.1.0", {scripts: {postinstall: "make"}})

    with_shard({dependencies: {moving: "0.1.0"}}) do
      run "shards install --no-color"
      File.exists?(install_path("moving", "made.txt")).should be_true

      create_file("moving", "src/moving.cr", "module Moving\n  VERSION = 2\nend\n")
      create_git_commit("moving", "replace v0.1.0 source")
      Dir.cd(git_path("moving")) { run "git tag --force v0.1.0" }

      Shards::Helpers.rm_rf(install_path("moving"))
      File.delete(install_path(".shards.info")) if File.exists?(install_path(".shards.info"))
      postinstall_info = install_path(".shards.postinstall")
      File.delete(postinstall_info) if File.exists?(postinstall_info)

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for moving")
      File.exists?(install_path("moving", "made.txt")).should be_false
    end
  end

  it "rejects a force-pushed tag that changes only a real top-level lib/ file" do
    create_git_repository("libmoving")
    create_file("libmoving", "lib/payload.sh", "echo original\n")
    create_file("libmoving", "Makefile", "all:\n\tsh lib/payload.sh > made.txt\n")
    create_git_release("libmoving", "0.1.0", {scripts: {postinstall: "make"}})

    with_shard({dependencies: {libmoving: "0.1.0"}}) do
      run "shards install --no-color"
      File.exists?(install_path("libmoving", "made.txt")).should be_true

      create_file("libmoving", "lib/payload.sh", "echo replaced\n")
      create_git_commit("libmoving", "replace v0.1.0 lib payload")
      Dir.cd(git_path("libmoving")) { run "git tag --force v0.1.0" }

      Shards::Helpers.rm_rf(install_path("libmoving"))
      File.delete(install_path(".shards.info")) if File.exists?(install_path(".shards.info"))
      postinstall_info = install_path(".shards.postinstall")
      File.delete(postinstall_info) if File.exists?(postinstall_info)

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for libmoving")
      File.exists?(install_path("libmoving", "made.txt")).should be_false
    end
  end

  it "rejects a moved tag that only makes a file executable" do
    create_git_repository("modeflip")
    create_file("modeflip", "tool.sh", "echo tool\n")
    create_git_release("modeflip", "0.1.0")

    with_shard({dependencies: {modeflip: "0.1.0"}}) do
      run "shards install --no-color"

      Dir.cd(git_path("modeflip")) do
        run "git update-index --chmod=+x tool.sh"
        run "git commit --no-gpg-sign -m #{Process.quote("make tool.sh executable")}"
        run "git tag --no-sign --force v0.1.0"
      end

      Shards::Helpers.rm_rf(install_path("modeflip"))
      File.delete(install_path(".shards.info")) if File.exists?(install_path(".shards.info"))

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Checksum verification failed for modeflip")
    end
  end
end
