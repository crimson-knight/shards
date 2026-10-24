Spec.before_each do
  path = application_path

  if File.exists?(path)
    Shards::Helpers.rm_rf_children(path)
  else
    Dir.mkdir_p(path)
  end
end

# Fixture locks record each git fixture's `sha256:` checksum, as a lock written by
# `minecart install` would. *lock_checksum_kind* is `:sha256`, `:git_tree` (a lock
# from Minecart 2025.11.25.8 or earlier), or `:none` (a lock from before checksums).
def with_shard(metadata, lock = nil, override = nil, *, lock_checksum_kind = :sha256, &)
  Dir.cd(application_path) do
    File.write "shard.yml", to_shard_yaml(metadata)
    File.write "shard.lock", to_lock_yaml(lock, lock_checksum_kind) if lock
    File.write "shard.override.yml", to_override_yaml(override) if override
    yield
  end
end

def to_shard_yaml(metadata)
  String.build do |yml|
    yml << "name: " << (metadata[:name]? || "test").inspect << '\n'
    yml << "version: " << (metadata[:version]? || "0.0.0").inspect << '\n'

    metadata.each do |key, value|
      if key.to_s.ends_with?("dependencies")
        write_dependencies(yml, key, value)
      elsif key.to_s == "targets"
        yml << "targets:\n"
        if value.responds_to?(:each)
          value.each do |target, info|
            yml << "  " << target.to_s << ":\n"
            if info.responds_to?(:each)
              info.each do |main, src|
                yml << "    main: " << src.inspect << '\n'
              end
            end
          end
        end
      end
    end
  end
end

def to_override_yaml(metadata)
  String.build do |yml|
    metadata.each do |key, value|
      if key.to_s == "dependencies"
        write_dependencies(yml, key, value)
      end
    end
  end
end

# This is used for dependencies and development_dependencies
private def write_dependencies(yml, key, value)
  yml << key << ':'

  if value.responds_to?(:each)
    yml << '\n'
    value.each do |name, version|
      yml << "  " << name << ":\n"

      case version
      when String
        yml << "    git: " << git_url(name).inspect << '\n'
        yml << "    version: " << version.inspect << '\n' unless version == "*"
        # when Hash
        #  version.each do |k, v|
        #    yml << "    " << k << ": " << v.inspect << '\n'
        #  end
      when NamedTuple
        version.each do |k, v|
          yml << "    " << k.to_s << ": " << v.inspect << '\n'
        end
      else
        yml << "    git: " << git_url(name).inspect << '\n'
      end
    end
  else
    yml << value
  end
end

def to_lock_yaml(lock, lock_checksum_kind = :sha256)
  return unless lock

  YAML.dump({
    version: Shards::Lock::CURRENT_VERSION,
    shards:  lock.to_a.to_h do |name, data|
      if data.is_a?(NamedTuple)
        git = data[:git]
        version = data[:version]
      else
        git = git_url(name)
        version = data
      end

      checksum = fixture_lock_checksum(git, version, lock_checksum_kind)
      if checksum
        {name, {git: git, version: version, checksum: checksum}}
      else
        {name, {git: git, version: version}}
      end
    end,
  })
end

# The lock checksum of a local git fixture at *version*, or nil when the fixture
# or the version does not exist (specs that lock a missing version).
def fixture_lock_checksum(git : String, version : String, lock_checksum_kind = :sha256) : String?
  return if lock_checksum_kind == :none
  return unless git.starts_with?("file://")

  # `git_url` writes "file://" + a POSIX path ("C:/..." on Windows).
  repository_path = git.lchop("file://")
  return unless Dir.exists?(repository_path)

  ref = if commit = version.split("+git.commit.", 2)[1]?
          commit
        else
          "v#{version}"
        end
  tree_output = IO::Memory.new
  status = Process.run("git", ["-C", repository_path, "rev-parse", "--verify", "--quiet", "#{ref}^{tree}"], output: tree_output)
  return unless status.success?
  return "#{Shards::LEGACY_GIT_TREE_PREFIX}#{tree_output.to_s.strip}" if lock_checksum_kind == :git_tree

  fixture_source_sha256(repository_path, ref)
end

# Checks *ref* out into a scratch directory with a scratch index, the way the git
# resolver installs a dependency, and returns the sha256 of those files.
def fixture_source_sha256(repository_path : String, ref : String) : String
  scratch = File.tempname("fixture-checksum")
  source_directory = File.join(scratch, "source")
  Dir.mkdir_p(source_directory)
  begin
    env = {"GIT_INDEX_FILE" => File.join(scratch, "index")}
    args = ["-C", repository_path, "--work-tree=#{source_directory}", "checkout", ref, "--", "."]
    status = Process.run("git", args, env: env)
    raise "git checkout #{ref} failed in #{repository_path}" unless status.success?
    Shards::Checksum.compute(source_directory)
  ensure
    Shards::Helpers.rm_rf(scratch)
  end
end

module Shards::Specs
  @@application_path : String?

  def self.application_path
    @@application_path ||= File.expand_path("../../tmp/integration", __DIR__).tap do |path|
      if File.exists?(path)
        Shards::Helpers.rm_rf_children(path)
      else
        Dir.mkdir_p(path)
      end
    end
  end
end

def application_path
  Shards::Specs.application_path
end
