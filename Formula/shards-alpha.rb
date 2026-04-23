class ShardsAlpha < Formula
  desc "Crystal Shards fork with supply chain compliance, MCP server, and AI docs"
  homepage "https://github.com/crimson-knight/shards"
  url "https://github.com/crimson-knight/shards/archive/refs/tags/v2025.11.25.4.tar.gz"
  version "2025.11.25.4"
  sha256 "13a347c8b5462ef70f7c30770e13e694dd0e00fad4954d06d3d288ad52657b9b"
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
