class ShardsAlpha < Formula
  desc "Crystal Shards fork with supply chain compliance, MCP server, and AI docs"
  homepage "https://github.com/crimson-knight/shards"
  url "https://github.com/crimson-knight/shards/archive/refs/tags/v2025.11.25.2.tar.gz"
  sha256 "8514e3cac54a07a8c8eeecf3af996bb5c81b65f266f2e4da4512d0d659a870c2"
  license "Apache-2.0"

  depends_on "crystal"

  def install
    system "make", "bin/shards-alpha", "release=1"
    bin.install "bin/shards-alpha"
  end

  test do
    assert_match "shards-alpha", shell_output("#{bin}/shards-alpha --version")
  end
end
