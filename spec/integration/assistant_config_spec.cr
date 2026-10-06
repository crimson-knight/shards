require "./spec_helper"
require "../../src/assistant_config"

module AssistantConfigSpecSupport
  def self.install_version(project : String, version : String)
    files = Shards::AssistantVersions::VERSIONS[version]
    info = Shards::AssistantConfigInfo.new(File.join(project, ".claude", Shards::ASSISTANT_CONFIG_FILENAME))
    info.installed_version = version
    info.installed_at = Time.utc.to_rfc3339
    info.components = {"mcp" => true, "skills" => true, "agents" => true, "settings" => true}

    files.each do |relative_path, content|
      next if relative_path == Shards::AssistantVersions::REMOVED_FILES_KEY

      full_path = File.join(project, relative_path)
      Dir.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
      info.files[relative_path] = Shards::AIDocsInfo.checksum(content)
    end

    info.save
  end
end

module Shards
  describe "versioned Minecart assistant config" do
    it "migrates pristine 2025.11.25.2 files from shards-cli to minecart-cli" do
      project = File.tempname("assistant_upgrade_pristine", "test")
      Dir.mkdir_p(project)
      AssistantConfigSpecSupport.install_version(project, "2025.11.25.2")

      output = Dir.cd(project) { run "minecart assistant update" }

      output.should contain("Updated")
      output.should contain("Removed 4 obsolete file(s).")
      File.exists?(File.join(project, ".claude/skills/shards-cli")).should be_false
      File.exists?(File.join(project, ".claude/skills/minecart-cli/SKILL.md")).should be_true
      File.exists?(File.join(project, ".claude/skills/minecart-cli/reference/commands.md")).should be_true
      File.exists?(File.join(project, ".claude/skills/minecart-cli/reference/shard-yml-format.md")).should be_true
      File.exists?(File.join(project, ".claude/skills/minecart-cli/reference/ai-docs-guide.md")).should be_true

      info = AssistantConfigInfo.new(File.join(project, ".claude", ASSISTANT_CONFIG_FILENAME))
      info.installed_version.should eq("2025.11.25.3")
      info.files.keys.any?(&.includes?("/skills/shards-cli/")).should be_false
      info.files.keys.any?(&.includes?("/skills/minecart-cli/")).should be_true
    ensure
      Shards::Helpers.rm_rf(project.not_nil!)
    end

    it "keeps a user-edited obsolete file and warns during migration" do
      project = File.tempname("assistant_upgrade_modified", "test")
      Dir.mkdir_p(project)
      AssistantConfigSpecSupport.install_version(project, "2025.11.25.2")
      edited_path = File.join(project, ".claude/skills/shards-cli/SKILL.md")
      File.write(edited_path, "User-owned assistant instructions\n")

      output = Dir.cd(project) { run "minecart assistant update" }

      output.should contain("Keeping locally modified obsolete assistant file")
      output.should contain(".claude/skills/shards-cli/SKILL.md")
      File.read(edited_path).should eq("User-owned assistant instructions\n")
      File.exists?(File.join(project, ".claude/skills/shards-cli/reference")).should be_false
      File.exists?(File.join(project, ".claude/skills/minecart-cli/SKILL.md")).should be_true

      info = AssistantConfigInfo.new(File.join(project, ".claude", ASSISTANT_CONFIG_FILENAME))
      info.installed_version.should eq("2025.11.25.3")
      info.files.has_key?("./.claude/skills/shards-cli/SKILL.md").should be_false
    ensure
      Shards::Helpers.rm_rf(project.not_nil!)
    end

    it "installs only Minecart CLI skill paths on a fresh init" do
      project = File.tempname("assistant_init_minecart", "test")
      Dir.mkdir_p(project)

      output = Dir.cd(project) { run "minecart assistant init" }

      output.should contain(".claude/skills/minecart-cli/SKILL.md")
      File.exists?(File.join(project, ".claude/skills/minecart-cli/SKILL.md")).should be_true
      File.exists?(File.join(project, ".claude/skills/shards-cli")).should be_false

      info = AssistantConfigInfo.new(File.join(project, ".claude", ASSISTANT_CONFIG_FILENAME))
      info.installed_version.should eq("2025.11.25.3")
    ensure
      Shards::Helpers.rm_rf(project.not_nil!)
    end
  end
end
