require "./spec_helper"

describe "Git tree lock checksums" do
  it "writes a git-tree checksum for a Git dependency" do
    metadata = {dependencies: {web: "1.2.0"}}
    with_shard(metadata) do
      run "shards install --no-color"

      File.read("shard.lock").should contain("checksum: git-tree:")
    end
  end

  it "rekeys a directory checksum without installing dependencies" do
    metadata = {dependencies: {web: "1.2.0"}}
    with_shard(metadata) do
      run "shards install --no-color"
      fake_sha = "a" * 64
      lock_before = File.read("shard.lock").gsub(/checksum: git-tree:[0-9a-f]+/, "checksum: sha256:#{fake_sha}")
      File.write("shard.lock", lock_before)
      lock_before.should contain("checksum: sha256:")

      run "shards lock --rekey --no-color"

      lock_after = File.read("shard.lock")
      lock_after.should contain("checksum: git-tree:")
      lock_after.should_not contain("checksum: sha256:")
    end
  end

  it "writes the same tree hash from two independent Git clones and installs" do
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

    first_checksum = /checksum: (git-tree:[0-9a-f]+)/.match(File.read(File.join(first_project, "shard.lock"))).not_nil![1]
    second_checksum = /checksum: (git-tree:[0-9a-f]+)/.match(File.read(File.join(second_project, "shard.lock"))).not_nil![1]
    first_checksum.should eq(second_checksum)
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
end
