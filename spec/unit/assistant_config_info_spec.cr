require "./spec_helper"
require "../../src/assistant_config_info"

module Shards
  describe AssistantConfigInfo do
    describe "#save and #load" do
      it "round-trips YAML correctly" do
        path = File.tempname("assistant_config", "test")
        Dir.mkdir_p(File.dirname(path))
        begin
          info = AssistantConfigInfo.new(path)
          info.installed_version = "2025.11.25.2"
          info.assistant = "claude-code"
          info.installed_at = "2026-02-15T10:30:00Z"
          info.components = {"mcp" => true, "skills" => true, "agents" => false, "settings" => true}
          info.files = {
            ".claude/CLAUDE.md"     => "sha256:abc123",
            ".claude/settings.json" => "sha256:def456",
          }
          info.save

          loaded = AssistantConfigInfo.new(path)
          loaded.installed_version.should eq("2025.11.25.2")
          loaded.assistant.should eq("claude-code")
          loaded.installed_at.should eq("2026-02-15T10:30:00Z")
          loaded.components["mcp"].should be_true
          loaded.components["agents"].should be_false
          loaded.files[".claude/CLAUDE.md"].should eq("sha256:abc123")
          loaded.files[".claude/settings.json"].should eq("sha256:def456")
        ensure
          File.delete(path) if File.exists?(path)
        end
      end
    end

    describe "#installed?" do
      it "returns false when no version is set" do
        path = File.tempname("assistant_config", "empty")
        info = AssistantConfigInfo.new(path)
        info.installed?.should be_false
      end

      it "returns true when version is set" do
        path = File.tempname("assistant_config", "set")
        info = AssistantConfigInfo.new(path)
        info.installed_version = "2025.11.25.2"
        info.installed?.should be_true
      end
    end
  end
end
