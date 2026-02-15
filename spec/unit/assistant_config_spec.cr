require "./spec_helper"
require "../../src/assistant_config"

module Shards
  describe AssistantVersions do
    describe ".current_files" do
      it "returns a non-empty hash of files" do
        files = AssistantVersions.current_files
        files.size.should eq(14)
      end

      it "includes expected file paths" do
        files = AssistantVersions.current_files
        files.keys.any? { |k| k.includes?("CLAUDE.md") }.should be_true
        files.keys.any? { |k| k.includes?("settings.json") }.should be_true
        files.keys.any? { |k| k.includes?("skills/audit/SKILL.md") }.should be_true
        files.keys.any? { |k| k.includes?("agents/compliance-checker.md") }.should be_true
      end
    end

    describe ".latest_version" do
      it "returns a version string" do
        AssistantVersions.latest_version.should eq("2025.11.25.2")
      end
    end

    describe ".all_versions" do
      it "returns a sorted array" do
        versions = AssistantVersions.all_versions
        versions.size.should be >= 1
        versions.should eq(versions.sort)
      end
    end

    describe ".files_changed_since" do
      it "returns empty hash when at latest version" do
        latest = AssistantVersions.latest_version
        changed = AssistantVersions.files_changed_since(latest)
        changed.should be_empty
      end

      it "returns all files when given a version before all known versions" do
        changed = AssistantVersions.files_changed_since("0.0.0")
        changed.size.should eq(14)
      end
    end
  end

  describe AssistantConfig do
    describe ".component_for" do
      it "classifies skills paths" do
        AssistantConfig.component_for("./.claude/skills/audit/SKILL.md").should eq("skills")
        AssistantConfig.component_for(".claude/skills/sbom/SKILL.md").should eq("skills")
      end

      it "classifies agents paths" do
        AssistantConfig.component_for("./.claude/agents/compliance-checker.md").should eq("agents")
        AssistantConfig.component_for(".claude/agents/security-reviewer.md").should eq("agents")
      end

      it "classifies settings paths" do
        AssistantConfig.component_for("./.claude/settings.json").should eq("settings")
        AssistantConfig.component_for("./.claude/CLAUDE.md").should eq("settings")
        AssistantConfig.component_for(".claude/settings.json").should eq("settings")
      end
    end

    describe ".filter_by_components" do
      it "filters out disabled components" do
        files = {
          "./.claude/skills/audit/SKILL.md"        => "content1",
          "./.claude/agents/compliance-checker.md" => "content2",
          "./.claude/CLAUDE.md"                    => "content3",
          "./.claude/settings.json"                => "content4",
        }
        components = {"skills" => true, "agents" => false, "settings" => true, "mcp" => true}
        filtered = AssistantConfig.filter_by_components(files, components)
        filtered.size.should eq(3)
        filtered.has_key?("./.claude/agents/compliance-checker.md").should be_false
      end

      it "keeps all files when all components enabled" do
        files = {
          "./.claude/skills/audit/SKILL.md"        => "content1",
          "./.claude/agents/compliance-checker.md" => "content2",
          "./.claude/CLAUDE.md"                    => "content3",
        }
        components = {"skills" => true, "agents" => true, "settings" => true, "mcp" => true}
        filtered = AssistantConfig.filter_by_components(files, components)
        filtered.size.should eq(3)
      end
    end

    describe ".install" do
      it "creates all files in a fresh directory" do
        path = File.tempname("assistant_install", "test")
        Dir.mkdir_p(path)
        begin
          AssistantConfig.install(path)

          # Check tracking file was created
          tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
          File.exists?(tracking_path).should be_true

          # Check some key files exist
          File.exists?(File.join(path, ".claude", "CLAUDE.md")).should be_true
          File.exists?(File.join(path, ".claude", "settings.json")).should be_true

          # Check tracking info
          info = AssistantConfigInfo.new(tracking_path)
          info.installed?.should be_true
          info.installed_version.should eq(AssistantVersions.latest_version)
          info.files.size.should eq(14)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "skips components when requested" do
        path = File.tempname("assistant_install", "skip")
        Dir.mkdir_p(path)
        begin
          AssistantConfig.install(path, skip_components: ["agents"])

          Dir.exists?(File.join(path, ".claude", "agents")).should be_false
          File.exists?(File.join(path, ".claude", "CLAUDE.md")).should be_true

          tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
          info = AssistantConfigInfo.new(tracking_path)
          info.components["agents"].should be_false
          info.components["skills"].should be_true
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end

    describe ".status" do
      it "reports not installed for empty directory" do
        path = File.tempname("assistant_status", "test")
        Dir.mkdir_p(path)
        begin
          # Should just print "not installed" — no crash
          AssistantConfig.status(path)
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end

    describe ".remove" do
      it "removes all tracked files" do
        path = File.tempname("assistant_remove", "test")
        Dir.mkdir_p(path)
        begin
          AssistantConfig.install(path)
          File.exists?(File.join(path, ".claude", "CLAUDE.md")).should be_true

          AssistantConfig.remove(path)
          File.exists?(File.join(path, ".claude", "CLAUDE.md")).should be_false

          tracking_path = File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME)
          File.exists?(tracking_path).should be_false
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end

    describe ".legacy_install?" do
      it "detects legacy files without tracking YAML" do
        path = File.tempname("assistant_legacy", "test")
        Dir.mkdir_p(File.join(path, ".claude"))
        begin
          File.write(File.join(path, ".claude", "CLAUDE.md"), "# Test")
          AssistantConfig.legacy_install?(path).should be_true
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "returns false when tracking file exists" do
        path = File.tempname("assistant_legacy", "tracking")
        Dir.mkdir_p(File.join(path, ".claude"))
        begin
          File.write(File.join(path, ".claude", "CLAUDE.md"), "# Test")
          File.write(File.join(path, ".claude", ASSISTANT_CONFIG_FILENAME), "version: '1.0'")
          AssistantConfig.legacy_install?(path).should be_false
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end

      it "returns false for empty directory" do
        path = File.tempname("assistant_legacy", "empty")
        Dir.mkdir_p(path)
        begin
          AssistantConfig.legacy_install?(path).should be_false
        ensure
          Shards::Helpers.rm_rf(path)
        end
      end
    end
  end
end
