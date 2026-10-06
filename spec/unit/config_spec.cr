require "./spec_helper"

describe Shards do
  it "prefers Minecart config and state paths when both names exist" do
    directory = File.join(tmp_path, "config-path-precedence")
    Dir.mkdir_p(directory)
    File.write(File.join(directory, ".minecart-policy.yml"), "version: 1\n")
    File.write(File.join(directory, ".shards-policy.yml"), "version: 1\n")
    Dir.mkdir_p(File.join(directory, ".minecart"))
    Dir.mkdir_p(File.join(directory, ".shards"))

    Shards.config_file_path(directory, ".minecart-policy.yml", ".shards-policy.yml")
      .should eq(File.join(directory, ".minecart-policy.yml"))
    Shards.state_directory_path(directory).should eq(File.join(directory, ".minecart"))
  end

  it "falls back to legacy config and state paths" do
    directory = File.join(tmp_path, "legacy-path-fallback")
    Dir.mkdir_p(directory)
    File.write(File.join(directory, ".shards-policy.yml"), "version: 1\n")
    Dir.mkdir_p(File.join(directory, ".shards"))

    Shards.config_file_path(directory, ".minecart-policy.yml", ".shards-policy.yml")
      .should eq(File.join(directory, ".shards-policy.yml"))
    Shards.state_directory_path(directory).should eq(File.join(directory, ".shards"))
  end

  it "uses Minecart state for a new project" do
    directory = File.join(tmp_path, "new-state-path")
    Dir.mkdir_p(directory)

    Shards.state_directory_path(directory).should eq(File.join(directory, ".minecart"))
  end
end
