class ShardsAlpha < Formula
  desc "Fork of Crystal's Shards with alpha features: AI docs, SBOM, MCP distribution"
  homepage "https://github.com/crimson-knight/shards"
  license "Apache-2.0"
  version "0.21.0-alpha.1"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/crimson-knight/shards/releases/download/v0.21.0-alpha.1/shards-alpha-darwin-arm64.tar.gz"
      sha256 "784cbe62d94c81f1b54bbdfc15954e17a04eab45760017fcbe455b3629f8772c"
    else
      url "https://github.com/crimson-knight/shards/releases/download/v0.21.0-alpha.1/shards-alpha-darwin-x86_64.tar.gz"
      sha256 "2a796e0b566284c7fe53f62097f9b27100f73f24d7c94fcb72789a7116dbc188"
    end
  end

  on_linux do
    url "https://github.com/crimson-knight/shards/releases/download/v0.21.0-alpha.1/shards-alpha-linux-x86_64.tar.gz"
    sha256 "e22efb221ad6372198051dd0c6a1c262a6664454a257a1102013ca4d01c1e6c0"
  end

  # Does not conflict with crystal-lang/shards -- installs as shards-alpha
  def install
    bin.install "shards-alpha"
  end

  test do
    assert_match "Shards Alpha", shell_output("#{bin}/shards-alpha --version")
  end
end
