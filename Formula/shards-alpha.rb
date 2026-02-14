class ShardsAlpha < Formula
  desc "Fork of Crystal's Shards with alpha features: AI docs, SBOM, MCP distribution"
  homepage "https://github.com/crimson-knight/shards"
  url "https://github.com/crimson-knight/shards.git", tag: "v0.21.0-alpha.1"
  license "Apache-2.0"
  head "https://github.com/crimson-knight/shards.git", branch: "master"

  depends_on "crystal" => :build

  # Does not conflict with crystal-lang/shards -- installs as shards-alpha
  def install
    system "make", "bin/shards-alpha", "release=1"
    bin.install "bin/shards-alpha"

    # Install man pages alongside the binary
    man1.install "man/shards.1" if File.exist?("man/shards.1")
    man5.install "man/shard.yml.5" if File.exist?("man/shard.yml.5")
  end

  test do
    assert_match "Shards Alpha", shell_output("#{bin}/shards-alpha --version")
  end
end
