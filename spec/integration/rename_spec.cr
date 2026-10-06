require "./spec_helper"

describe "Minecart public command" do
  it "keeps the shards-alpha alias and prints its one-line deprecation notice" do
    with_shard({name: "test"}) do
      output = run "shards-alpha --version"

      output.should contain("Minecart ")
      output.lines.count(&.includes?("shards-alpha is now minecart")).should eq(1)
    end
  end

  it "allows suppressing the alias deprecation notice" do
    with_shard({name: "test"}) do
      output = run "MINECART_NO_DEPRECATION=1 shards-alpha --version"

      output.should contain("Minecart ")
      output.should_not contain("shards-alpha is now minecart")
    end
  end
end
