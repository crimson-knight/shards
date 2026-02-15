class ShardsAlpha < Formula
  desc "Crystal Shards fork with supply chain compliance, MCP server, and AI docs"
  homepage "https://github.com/crimson-knight/shards"
  url "https://github.com/crimson-knight/shards/archive/refs/tags/v2025.11.25.1.tar.gz"
  sha256 "4756c8b006552b2fa2b702f86a6dd9c78cd69f49dfdb0dc13e06b34c8f270430"
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
