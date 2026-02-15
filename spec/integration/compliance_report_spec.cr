require "./spec_helper"
require "json"

describe "compliance-report" do
  it "generates JSON report with all sections" do
    with_shard({dependencies: {web: "*", pg: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --no-color"

      File.exists?("test-compliance-report.json").should be_true
      json = JSON.parse(File.read("test-compliance-report.json"))

      json["report"]["version"].as_s.should eq("1.0")
      json["report"]["generator"].as_s.should contain("shards-alpha")
      json["report"]["project"]["name"].as_s.should eq("test")
      json["report"]["summary"]["total_dependencies"].as_i.should be >= 2
      json["report"]["summary"]["direct_dependencies"].as_i.should eq(2)
      json["report"]["summary"]["overall_status"].as_s.should_not be_empty
      json["report"]["sections"]["sbom"]?.should_not be_nil
    end
  end

  it "generates HTML report" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --format=html --no-color"

      File.exists?("test-compliance-report.html").should be_true
      content = File.read("test-compliance-report.html")
      content.should contain("<!DOCTYPE html>")
      content.should contain("Supply Chain Compliance Report")
    end
  end

  it "generates Markdown report" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --format=markdown --no-color"

      File.exists?("test-compliance-report.md").should be_true
      content = File.read("test-compliance-report.md")
      content.should contain("# Compliance Report: test")
      content.should contain("Executive Summary")
    end
  end

  it "writes to custom output path" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --output=custom-report.json --no-color"

      File.exists?("custom-report.json").should be_true
    end
  end

  it "includes only selected sections" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --sections=sbom --no-color"

      json = JSON.parse(File.read("test-compliance-report.json"))
      json["report"]["sections"]["sbom"]?.should_not be_nil
    end
  end

  it "includes reviewer in attestation" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --reviewer=security@company.com --no-color"

      json = JSON.parse(File.read("test-compliance-report.json"))
      json["report"]["attestation"]["reviewer"].as_s.should eq("security@company.com")
      json["report"]["attestation"]["reviewed_at"]?.should_not be_nil
    end
  end

  it "archives report to .shards/audit/reports/" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --no-color"

      Dir.exists?(".shards/audit/reports").should be_true
      archived = Dir.glob(".shards/audit/reports/*.json")
      archived.size.should be >= 1
    end
  end

  it "fails without lock file" do
    with_shard({dependencies: {web: "*"}}) do
      ex = expect_raises(FailedCommand) { run "shards-alpha compliance-report --no-color" }
      (ex.stdout + ex.stderr).should contain("Missing shard.lock")
    end
  end

  it "fails with unknown format" do
    with_shard({dependencies: {web: "*"}}) do
      run "shards-alpha install --no-color"
      ex = expect_raises(FailedCommand) { run "shards-alpha compliance-report --format=pdf --no-color" }
      (ex.stdout + ex.stderr).should contain("Unknown report format")
    end
  end

  it "produces valid parseable JSON" do
    with_shard({dependencies: {web: "*", orm: "*"}}) do
      run "shards-alpha install --no-color"
      run "shards-alpha compliance-report --no-color"

      content = File.read("test-compliance-report.json")
      json = JSON.parse(content)

      json["report"]?.should_not be_nil
      json["report"]["version"]?.should_not be_nil
      json["report"]["generated_at"]?.should_not be_nil
      json["report"]["generator"]?.should_not be_nil
      json["report"]["project"]?.should_not be_nil
      json["report"]["summary"]?.should_not be_nil
      json["report"]["sections"]?.should_not be_nil
    end
  end
end
