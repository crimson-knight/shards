require "file_utils"
require "./checksum"
require "./helpers"

module Shards
  class Package
    getter name : String
    getter resolver : Resolver
    getter version : Version
    getter is_override : Bool
    property checksum : String?
    # The `sha256-v2:` digest of the installed copy when it was first verified
    # in this run; scripts may run only while the copy still matches it.
    property first_verified_digest : String?
    @spec : Spec?
    @installed_spec : Spec?

    def initialize(@name, @resolver, @version, @is_override = false, @checksum : String? = nil)
    end

    def_equals @name, @resolver, @version

    def report_version
      resolver.report_version(version)
    end

    # The manifest of this version as its source (the resolver) has it. An
    # installed copy can be edited, so whether a package has scripts, what it
    # depends on and what it installs are always read from here.
    def spec
      @spec ||= resolver.spec(version)
    end

    # The installed copy's manifest, for commands that only report on what is
    # installed (`list`, `check`, `licenses`, `sbom`, `compliance-report`).
    # Nothing that decides what runs or what is locked reads it.
    def installed_spec : Spec
      @installed_spec ||= installed? ? read_installed_spec : spec
    end

    private def read_installed_spec
      path = File.join(install_path, SPEC_FILENAME)
      unless File.exists?(path)
        return resolver.spec(version)
      end

      begin
        spec = Spec.from_file(path)
        spec.version = version
        spec
      rescue error : ParseError
        error.resolver = resolver
        raise error
      end
    end

    def installed?
      return false unless File.exists?(install_path)
      if installed = Shards.info.installed[name]?
        installed.resolver == resolver && installed.version == version
      else
        false
      end
    end

    def install_path
      File.join(Shards.install_path, name)
    end

    # The checksum of the installed copy, computed with the algorithm of the
    # recorded checksum so any lock entry can be compared with it. A legacy
    # `git-tree:` entry is checked against the Git mirror's tree id instead.
    def compute_checksum : String?
      return nil unless File.exists?(install_path)

      recorded = checksum
      if recorded && recorded.starts_with?(LEGACY_GIT_TREE_PREFIX)
        return resolver.checksum_for(version)
      end
      if recorded && Checksum.legacy_sha256?(recorded)
        return Checksum.compute_legacy_sha256(install_path)
      end

      Checksum.compute(install_path)
    end

    # The current (`sha256-v2:`) checksum over the installed files. Callers
    # record it right after installation, before any postinstall script can
    # change the directory.
    def computed_checksum : String?
      return nil unless File.exists?(install_path)

      Checksum.compute(install_path)
    end

    # The current (`sha256-v2:`) checksum of the files a fresh install of this
    # version writes. The sources are written to a temporary directory, so
    # postinstall output in the installed copy never enters the checksum. Path
    # dependencies are hashed where they are, because their source is the
    # directory itself.
    def pristine_checksum : String?
      return computed_checksum if resolver.is_a?(PathResolver)

      with_pristine_sources { |directory| Checksum.compute(directory) }
    end

    # The checksum of a fresh install of this version, computed with the
    # algorithm that produced *expected*, so a lock entry of any kind can be
    # compared with the source it names.
    def source_checksum_like(expected : String) : String?
      return resolver.checksum_for(version) if expected.starts_with?(LEGACY_GIT_TREE_PREFIX)
      return pristine_checksum unless Checksum.legacy_sha256?(expected)

      if resolver.is_a?(PathResolver)
        return nil unless File.exists?(install_path)
        return Checksum.compute_legacy_sha256(install_path)
      end

      with_pristine_sources(as_installed: true) { |directory| Checksum.compute_legacy_sha256(directory) }
    end

    # True when the installed copy matches a fresh checkout of this version
    # under the `sha256-v2:` entry rules (mode, bytes, symlinks by link text;
    # a real top-level `lib/` included). Callers first verify the lock entry
    # against that checkout under the entry's own rules. A package whose
    # source declares a postinstall script may also hold files the source
    # does not have (its script's output); every other installed copy is
    # compared against the whole checkout. VCS metadata directories and the
    # `lib` link Minecart writes are skipped on both sides. This is a
    # best-effort check: local write access is outside the threat model.
    def installed_copy_matches_source? : Bool
      return true if resolver.is_a?(PathResolver)
      return false unless File.exists?(install_path)

      list_of_paths, source = with_pristine_sources { |directory| {Checksum.entry_paths(directory), Checksum.compute(directory)} }
      installed = spec.scripts["postinstall"]? ? Checksum.compute_entries(install_path, list_of_paths) : computed_checksum
      installed == source
    end

    # Writes a fresh copy of this version to a temporary directory and yields
    # it. With *as_installed*, the copy also gets the `lib` link an install
    # writes (to the project install path), because a v1 `sha256:` entry was
    # computed over an installed copy and follows file links through it.
    private def with_pristine_sources(*, as_installed = false, & : String -> T) : T forall T
      directory = File.tempname("minecart-checksum-#{name}")
      begin
        resolver.install_sources(version, directory)
        if as_installed
          lib_path = File.join(directory, INSTALL_DIR)
          unless File.exists?(lib_path) || File.symlink?(lib_path)
            # A link to a missing directory would be hashed as a file by v1.
            Dir.mkdir_p(Shards.install_path)
            File.symlink(File.expand_path(Shards.install_path), lib_path)
          end
        end
        yield directory
      ensure
        Helpers.rm_rf(directory) if File.exists?(directory)
      end
    end

    def install
      Log.with_context do
        Log.context.set package: name

        cleanup_install_directory

        # install the shard:
        resolver.install_sources(version, install_path)

        # link the project's lib path as the shard's lib path, so the dependency
        # can access transitive dependencies:
        unless resolver.is_a?(PathResolver)
          install_lib_path
        end
      end

      Shards.info.installed[name] = self
      Shards.info.save
    end

    private def install_lib_path
      lib_path = File.join(install_path, Shards::INSTALL_DIR)
      # A shard may ship its own `lib` entry, even a link to a missing path.
      return if File.exists?(lib_path) || File.symlink?(lib_path)

      Log.debug { "Link #{Shards.install_path} to #{lib_path}" }
      Dir.mkdir_p(File.dirname(lib_path))
      target = Checksum::INSTALLED_LIB_LINK_TARGET
      File.symlink(target, lib_path)
    end

    protected def cleanup_install_directory
      Log.debug { "rm -rf #{Process.quote(install_path)}" }
      Shards::Helpers.rm_rf(install_path)
    end

    def postinstall
      return unless installed?
      return unless command = spec.scripts["postinstall"]?

      if Shards.skip_postinstall?
        Log.info { "Postinstall of #{name}: #{command} (skipped)" }
        return
      end

      script_hash = PostinstallInfo.hash_script(command)
      info = Shards.postinstall_info

      if entry = info.shards[name]?
        if entry.has_run && entry.script_hash == script_hash
          # Already run and unchanged, skip silently
          return
        elsif entry.has_run && entry.script_hash != script_hash
          Log.warn { "Postinstall script for #{name} has changed." }
          Log.warn { "  Run `minecart run-script #{name}` to execute it." }
          info.shards[name] = PostinstallInfo::Entry.new(script_hash, has_run: false)
          info.save
          return
        end
      end

      Log.info { "Postinstall of #{name}: #{command}" }
      Script.run(install_path, command, "postinstall", name)
      info.shards[name] = PostinstallInfo::Entry.new(script_hash, has_run: true)
      info.save
    rescue ex : Script::Error
      cleanup_install_directory
      raise ex
    end

    def run_script(name, skip)
      if installed? && (command = spec.scripts[name]?)
        if !skip
          Log.info { "#{name.capitalize} of #{self.name}: #{command}" }
          Script.run(install_path, command, name, self.name)
        else
          Log.info { "#{name.capitalize} of #{self.name}: #{command} (skipped)" }
        end
      end
    end

    def install_executables
      return if !installed? || spec.executables.empty? || Shards.skip_executables?

      Dir.mkdir_p(Shards.bin_path)

      Log.with_context do
        Log.context.set package: name
        spec.executables.each do |name|
          exe_name = find_executable_file(Path[install_path], name)
          unless exe_name
            raise Shards::Error.new("Could not find executable #{name.inspect} for #{@name.inspect}")
          end
          Log.debug { "Install #{exe_name}" }
          source = File.join(install_path, exe_name)
          destination = File.join(Shards.bin_path, File.basename(exe_name))

          if File.exists?(destination)
            next if File.same?(destination, source)
            File.delete(destination)
          end

          begin
            File.link(source, destination)
          rescue File::Error
            FileUtils.cp(source, destination)
          end
        end
      end
    end

    def find_executable_file(install_path, name)
      each_executable_path(name) do |path|
        return path if File.exists?(install_path.join(path))
      end
    end

    private def each_executable_path(name, &)
      exe = Shards::Helpers.exe(name)
      yield Path["bin", exe]
      yield Path["bin", name] unless name == exe
    end

    def to_yaml(builder)
      Dependency.new(name, resolver, version).to_yaml(builder)
    end

    def to_s(io)
      io << name << " (" << report_version << ")"
    end
  end
end
