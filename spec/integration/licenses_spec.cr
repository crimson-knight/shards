require "./spec_helper"
require "json"

# Helper to extract JSON from combined stdout+stderr
private def extract_json(output : String) : String
  start_idx = output.index('{')
  end_idx = output.rindex('}')
  if start_idx && end_idx && end_idx > start_idx
    output[start_idx..end_idx]
  else
    output
  end
end

describe "licenses" do
  it "lists dependency licenses" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --no-color"
      output.should contain("License Report")
      output.should contain("web")
    end
  end

  it "outputs valid JSON with --format=json" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --format=json"
      json = JSON.parse(extract_json(output))
      json["project"].should eq("test")
      json["dependencies"].as_a.size.should be >= 1
    end
  end

  it "outputs CSV with --format=csv" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --format=csv --no-color"
      output.should contain("Name,Version")
      output.should contain("web")
    end
  end

  it "outputs markdown with --format=markdown" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --format=markdown --no-color"
      output.should contain("# License Report")
      output.should contain("| Dependency |")
    end
  end

  it "fails without lock file" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      ex = expect_raises(FailedCommand) { run "shards licenses --no-color" }
      ex.stdout.should contain("Missing shard.lock")
    end
  end

  it "fails with unknown format" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      ex = expect_raises(FailedCommand) { run "shards licenses --format=xml --no-color" }
      ex.stdout.should contain("Unknown format")
    end
  end

  it "handles --check with policy violations" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"
      # Test repos don't have license fields in shard.yml, so they are unlicensed.
      # Use require_license: true to flag unlicensed deps as policy violations.
      File.write ".shards-license-policy.yml", "policy:\n  require_license: true\n"
      ex = expect_raises(FailedCommand) { run "shards licenses --check --no-color" }
      (ex.stdout + ex.stderr).should contain("License policy violations")
    end
  end

  it "handles projects with multiple dependencies" do
    metadata = {dependencies: {web: "*", orm: "*"}}
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --format=json"
      json = JSON.parse(extract_json(output))
      # orm depends on pg, so at least 3 packages: web, orm, pg
      json["dependencies"].as_a.size.should be >= 3
    end
  end
end
