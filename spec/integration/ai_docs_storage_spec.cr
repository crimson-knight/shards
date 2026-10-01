require "./spec_helper"
require "../../src/ai_docs_info"

private def with_docs_storage_fixture(&)
  create_path_repository "storage_docs", "1.0.0"
  source = create_file("storage_docs", ".claude/skills/probe/payload.png", "upstream payload")
  metadata = {dependencies: {storage_docs: {path: rel_path(:storage_docs)}}}

  with_shard(metadata) do
    run "shards install --local --skip-ai-assistant"
    destination = File.join(application_path, ".claude/skills/storage_docs--probe/payload.png")
    yield source, destination
  end
end

describe "AI documentation storage" do
  it "installs dependency documentation and records its checksum" do
    with_docs_storage_fixture do |source, destination|
      File.read(destination).should eq(File.read(source))
      tracker = Shards::AIDocsInfo.new(File.join(application_path, ".claude/.ai-docs-info.yml"))
      tracker.shards["storage_docs"].files[".claude/skills/storage_docs--probe/payload.png"].installed_checksum.should eq(Shards::AIDocsInfo.checksum_file(source))
    end
  end

  it "preserves unchanged documentation timestamps on a frozen install" do
    with_docs_storage_fixture do |source, destination|
      File.touch(destination, Time.unix(1_700_000_000))
      before = File.info(destination).modification_time
      run "shards install --frozen --local --skip-ai-assistant"
      File.info(destination).modification_time.should eq(before)
      File.read(destination).should eq(File.read(source))
    end
  end

  it "preserves identical documentation when a forced update resets its tracker" do
    with_docs_storage_fixture do |source, destination|
      File.touch(destination, Time.unix(1_700_000_000))
      before = File.info(destination).modification_time
      run "shards ai-docs update storage_docs"
      File.info(destination).modification_time.should eq(before)
      File.read(destination).should eq(File.read(source))
    end
  end

  it "updates untouched documentation when upstream bytes change" do
    with_docs_storage_fixture do |source, destination|
      File.write(source, "new upstream payload")
      run "shards install --frozen --local --skip-ai-assistant"
      File.read(destination).should eq("new upstream payload")
    end
  end

  it "preserves local modifications across repeated installs" do
    with_docs_storage_fixture do |source, destination|
      File.write(destination, "local customization")
      File.write(source, "new upstream payload")
      run "shards install --frozen --local --skip-ai-assistant"
      File.read(destination).should eq("local customization")
      File.read("#{destination}.upstream").should eq("new upstream payload")
      run "shards install --frozen --local --skip-ai-assistant"
      File.read(destination).should eq("local customization")
    end
  end

  it "preserves an unchanged upstream comparison file across repeated installs" do
    with_docs_storage_fixture do |source, destination|
      File.write(destination, "local customization")
      run "shards install --frozen --local --skip-ai-assistant"
      comparison = "#{destination}.upstream"
      File.touch(comparison, Time.unix(1_700_000_000))
      before = File.info(comparison).modification_time
      run "shards install --frozen --local --skip-ai-assistant"
      File.read(destination).should eq("local customization")
      File.info(comparison).modification_time.should eq(before)
      File.read(comparison).should eq(File.read(source))
    end
  end

  it "overwrites customized documentation only when an update is explicitly forced" do
    with_docs_storage_fixture do |source, destination|
      File.write(destination, "local customization")
      run "shards ai-docs update storage_docs"
      File.read(destination).should eq(File.read(source))
    end
  end
end
