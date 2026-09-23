require "./spec_helper"

describe "root dependency pinning" do
  it "warns about unpinned runtime dependencies during install and update" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      install_output = run "shards install --no-color"
      install_output.should contain("W: dependency 'web' is not pinned (no version/tag/commit)")

      update_output = run "shards update --no-color"
      update_output.should contain("W: dependency 'web' is not pinned (no version/tag/commit)")
    end
  end

  it "warns when a library has no lockfile" do
    metadata = {dependencies: {web: "~> 1.0.0"}}
    with_shard(metadata) do
      File.write("shard.yml", File.read("shard.yml") + "pinning: library\n")

      output = run "shards install --no-color"
      output.should contain("W: pinning: library requires a committed shard.lock; shard.lock is missing")
      output.should_not contain("dependency 'web' is not pinned")

      next_output = run "shards install --no-color"
      next_output.should match(/shard\.lock is (not committed|gitignored)/)
    end
  end

  it "skips development, path, and transitive dependencies and advises on exact versions" do
    metadata = {
      dependencies:             {mock: "0.1.0", foo: {path: rel_path(:foo)}},
      development_dependencies: {pg: "*"},
    }
    with_shard(metadata) do
      output = run "shards install --no-color"
      output.should contain("dependency 'mock' uses an exact version")
      output.should contain("commit plus the lock checksum is stronger")
      output.should_not contain("dependency 'foo' is not pinned")
      output.should_not contain("dependency 'pg' is not pinned")
      output.should_not contain("dependency 'shoulda' is not pinned")
    end
  end

  it "errors on unpinned dependencies with strict mode" do
    with_shard({dependencies: {web: "*"}}) do
      ex = expect_raises(FailedCommand) { run "shards --strict-pinning install --no-color" }
      (ex.stdout + ex.stderr).should contain("E: dependency 'web' is not pinned")
    end
  end

  it "supports policy false and prefers the Minecart policy filename" do
    with_shard({dependencies: {web: "*"}}) do
      File.write(".minecart-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          require_exact: false
      YAML
      )
      File.write(".shards-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          require_exact: true
      YAML
      )

      output = run "shards install --no-color"
      output.should_not contain("dependency 'web' is not pinned")
    end
  end

  it "errors when policy requires exact root dependencies" do
    with_shard({dependencies: {web: "~> 1.0.0"}}) do
      File.write(".minecart-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          require_exact: true
      YAML
      )

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("E: dependency 'web' is not pinned")
    end
  end
end
