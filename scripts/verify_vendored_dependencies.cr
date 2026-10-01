require "yaml"
require "../src/checksum"

module Shards::Release
  struct DependencyPin
    include YAML::Serializable

    getter version : String = ""
    getter checksum : String = ""
  end

  struct DependencyLock
    include YAML::Serializable

    getter shards : Hash(String, DependencyPin) = {} of String => DependencyPin
  end
end

root_path = File.expand_path(ARGV[0]? || ".")
lock = Shards::Release::DependencyLock.from_yaml(File.read(File.join(root_path, "shard.lock")))
raise "The build dependency lock is empty" if lock.shards.empty?

lock.shards.each do |dependency_name, pin|
  unless /\+git\.commit\.[0-9a-f]{40}$/.matches?(pin.version)
    raise "#{dependency_name} is not pinned to a full commit"
  end
  unless /^sha256:[0-9a-f]{64}$/.matches?(pin.checksum)
    raise "#{dependency_name} is missing its SHA-256 checksum"
  end
  source_path = File.join(root_path, "lib", dependency_name)
  unless Shards::Checksum.verify(source_path, pin.checksum)
    raise "Vendored checksum mismatch for #{dependency_name}"
  end
  STDOUT << "Verified " << dependency_name << " " << pin.version << '\n'
end
