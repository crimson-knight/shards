require "./spec_helper"
require "json"

private def extract_json(output : String) : JSON::Any
  # Find the first { or [ and parse from there
  start = output.index('{') || output.index('[')
  return JSON.parse("{}") unless start
  json_str = output[start..]
  # Find matching close bracket
  depth = 0
  json_str.each_char_with_index do |char, i|
    case char
    when '{', '[' then depth += 1
    when '}', ']' then depth -= 1
    end
    if depth == 0
      return JSON.parse(json_str[..i])
    end
  end
  JSON.parse("{}")
end

describe "diff command" do
  it "shows no changes for same lockfile" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      output = run "shards-alpha diff --from=current --to=current --no-color 2>&1"
      output.should contain("No dependency changes")
    end
  end

  it "shows added dependency via file path comparison" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      # Save a copy of the current lockfile
      File.copy("shard.lock", "old.lock")

      # Rewrite shard.yml to add pg
      File.write("shard.yml", to_shard_yaml({dependencies: {web: "*", pg: "*"}}))
      # Remove the lockfile so shards resolves fresh
      File.delete("shard.lock")
      run "shards-alpha install --no-color"

      output = run "shards-alpha diff --from=old.lock --to=current --format=terminal --no-color 2>&1"
      output.should contain("pg")
      output.should contain("+")
    end
  end

  it "produces valid JSON output" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      File.copy("shard.lock", "old.lock")

      File.write("shard.yml", to_shard_yaml({dependencies: {web: "*", pg: "*"}}))
      File.delete("shard.lock")
      run "shards-alpha install --no-color"

      output = run "shards-alpha diff --from=old.lock --to=current --format=json --no-color 2>&1"
      json = extract_json(output)

      json["from"]?.should_not be_nil
      json["to"]?.should_not be_nil
      json["changes"]?.should_not be_nil
      json["summary"]?.should_not be_nil

      json["changes"]["added"].as_a.size.should be > 0
      added_names = json["changes"]["added"].as_a.map { |c| c["name"].as_s }
      added_names.should contain("pg")
    end
  end

  it "produces markdown output with correct structure" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      File.copy("shard.lock", "old.lock")

      File.write("shard.yml", to_shard_yaml({dependencies: {web: "*", pg: "*"}}))
      File.delete("shard.lock")
      run "shards-alpha install --no-color"

      output = run "shards-alpha diff --from=old.lock --to=current --format=markdown --no-color 2>&1"
      output.should contain("## Dependency Changes")
      output.should contain("| Status |")
      output.should contain("**Summary:**")
      output.should contain("pg")
    end
  end

  it "fails gracefully with invalid git ref" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      # Initialize a git repo so the git show command has somewhere to look
      run "git init 2>&1"
      run "git config user.email test@test.com 2>&1"
      run "git config user.name Test 2>&1"
      ex = expect_raises(FailedCommand) do
        run "shards-alpha diff --from=nonexistent_ref_abc123 --to=current --no-color 2>&1"
      end
      (ex.stdout + ex.stderr).should contain("Could not read")
    end
  end

  it "diff against file path works for removed dependency" do
    with_shard({dependencies: {web: "*", pg: "*"}}) do
      run "shards-alpha install --no-color"
      # Save a copy with both deps
      File.copy("shard.lock", "old.lock")

      # Remove pg dependency
      File.write("shard.yml", to_shard_yaml({dependencies: {web: "*"}}))
      File.delete("shard.lock")
      run "shards-alpha install --no-color"

      output = run "shards-alpha diff --from=old.lock --to=current --format=terminal --no-color 2>&1"
      output.should contain("pg")
      output.should contain("x")
      output.should contain("removed")
    end
  end

  it "creates audit log on install" do
    with_shard({dependencies: {web: "*"}}) do
      # Clean up any leftover audit dir
      audit_dir = File.join(application_path, ".shards", "audit")
      FileUtils.rm_rf(audit_dir) if Dir.exists?(audit_dir)

      run "shards-alpha install --no-color"

      log_path = File.join(application_path, ".shards", "audit", "changelog.json")
      File.exists?(log_path).should be_true

      parsed = JSON.parse(File.read(log_path))
      entries = parsed["entries"].as_a
      entries.size.should eq(1)

      entry = entries[0]
      entry["action"].as_s.should eq("install")
      entry["timestamp"]?.should_not be_nil
      entry["lockfile_checksum"]?.should_not be_nil
      entry["changes"]["added"].as_a.size.should be > 0
    end
  end

  it "appends audit log on update" do
    with_shard({dependencies: {web: "~> 1.0"}}) do
      # Clean up any leftover audit dir
      audit_dir = File.join(application_path, ".shards", "audit")
      FileUtils.rm_rf(audit_dir) if Dir.exists?(audit_dir)

      run "shards-alpha install --no-color"

      log_path = File.join(application_path, ".shards", "audit", "changelog.json")
      File.exists?(log_path).should be_true
      parsed = JSON.parse(File.read(log_path))
      initial_count = parsed["entries"].as_a.size

      # Update to a broader range so update has something to resolve differently
      File.write("shard.yml", to_shard_yaml({dependencies: {web: ">= 2.0.0"}}))
      run "shards-alpha update --no-color"

      parsed = JSON.parse(File.read(log_path))
      entries = parsed["entries"].as_a
      entries.size.should be > initial_count

      last_entry = entries.last
      last_entry["action"].as_s.should eq("update")
    end
  end
end
