require "./spec_helper"

describe "policy" do
  it "installs without policy file (no-op)" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      assert_installed "web"
    end
  end

  it "blocks install for blocked dependency" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      File.write ".shards-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          blocked:
            - name: web
              reason: "Test block"
      YAML
      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      (ex.stdout + ex.stderr).should contain("Policy violations found")
    end
  end

  it "passes with compliant dependencies" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      File.write ".shards-policy.yml", "version: 1\n"
      run "shards install"
      assert_installed "web"
    end
  end

  it "policy check works against lockfile" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      File.write ".shards-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          blocked:
            - name: web
              reason: "Test block"
      YAML
      ex = expect_raises(FailedCommand) { run "shards policy check --no-color" }
      (ex.stdout + ex.stderr).should contain("blocked")
    end
  end

  it "policy init creates starter file" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards policy init"
      File.exists?(".shards-policy.yml").should be_true
    end
  end

  it "policy init fails if file exists" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      File.write ".shards-policy.yml", "version: 1\n"
      ex = expect_raises(FailedCommand) { run "shards policy init --no-color" }
      (ex.stdout + ex.stderr).should contain("already exists")
    end
  end

  it "blocks update for blocked dependency" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      File.write ".shards-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          blocked:
            - name: web
              reason: "Test block"
      YAML
      ex = expect_raises(FailedCommand) { run "shards update --no-color" }
      (ex.stdout + ex.stderr).should contain("Policy violations found")
    end
  end
end
