require "./spec_helper"
require "json"

# Extract JSON from combined stdout+stderr output
private def extract_json(output : String) : String
  start_idx = output.index('{')
  end_idx = output.rindex('}')
  if start_idx && end_idx && end_idx > start_idx
    output[start_idx..end_idx]
  else
    output
  end
end

describe "audit" do
  it "runs without error on an installed project" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      # The audit command may find vulnerabilities (exit 1) or not (exit 0).
      # With local test repos it should find none since OSV won't recognize file:// purls.
      output = run "shards audit --no-color"
      output.should contain("vulnerabilit")
    end
  end

  it "produces valid JSON output with --format=json" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      output = run "shards audit --format=json"
      json = JSON.parse(extract_json(output))

      json["schema_version"].should eq("1.0.0")
      json["tool"].should eq("shards-alpha")
      json["summary"]?.should_not be_nil
      json["summary"]["total_packages"].as_i.should be >= 1
      json["packages"]?.should_not be_nil
    end
  end

  it "produces valid SARIF output with --format=sarif" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      output = run "shards audit --format=sarif"
      json = JSON.parse(extract_json(output))

      json["version"].should eq("2.1.0")
      json["$schema"].as_s.should contain("sarif")
      json["runs"]?.should_not be_nil
      json["runs"].as_a.size.should eq(1)
      json["runs"].as_a.first["tool"]["driver"]["name"].should eq("shards-alpha audit")
    end
  end

  it "fails without a lock file" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      ex = expect_raises(FailedCommand) { run "shards audit --no-color" }
      ex.stdout.should contain("Missing shard.lock")
    end
  end

  it "fails with unknown format" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      ex = expect_raises(FailedCommand) { run "shards audit --format=unknown --no-color" }
      ex.stdout.should contain("Unknown audit format")
    end
  end

  it "handles projects with multiple dependencies" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      output = run "shards audit --format=json"
      json = JSON.parse(extract_json(output))

      # orm depends on pg, so at least 3 packages: web, orm, pg
      json["summary"]["total_packages"].as_i.should be >= 3
    end
  end
end
