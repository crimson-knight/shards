require "../lock"
require "../spec"
require "../override"
require "../policy"
require "../policy_checker"
require "../policy_report"
require "../pinning"

module Shards
  abstract class Command
    getter path : String
    getter spec_path : String
    getter lockfile_path : String
    getter override_path : String?

    @spec : Spec?
    @locks : Lock?
    @override : Override?
    @policy : Shards::Policy?

    def initialize(path)
      if File.directory?(path)
        @path = path
        @spec_path = File.join(path, SPEC_FILENAME)
      else
        @path = File.dirname(path)
        @spec_path = path
      end
      @lockfile_path = File.join(@path, LOCK_FILENAME)

      # If global override is defined via SHARDS_OVERRIDE env var we use that.
      # Otherwise we check if the is a shard.override.yml file next to the shard.yml
      @override_path = Shards.global_override_filename
      unless @override_path
        local_override = File.join(@path, OVERRIDE_FILENAME)
        @override_path = File.exists?(local_override) ? local_override : nil
      end
    end

    def self.run(path, *args, **kwargs)
      new(path).run(*args, **kwargs)
    end

    def spec
      @spec ||= if File.exists?(spec_path)
                  Spec.from_file(spec_path)
                else
                  raise Error.new("Missing #{spec_filename}. Please run 'shards init'")
                end
    end

    def spec_filename
      File.basename(spec_path)
    end

    def locks
      @locks ||= if lockfile?
                   Shards::Lock.from_file(lockfile_path)
                 else
                   raise Error.new("Missing #{LOCK_FILENAME}. Please run 'minecart install'")
                 end
    end

    def lockfile?
      File.exists?(lockfile_path)
    end

    def override
      @override ||= override_path.try { |p| Shards::Override.from_file(p) }
    end

    def write_lockfile(packages)
      Log.info { "Writing #{LOCK_FILENAME}" }

      override_path = @override_path
      override_path = File.basename(override_path) if override_path && File.dirname(override_path) == @path

      Shards::Lock.write(packages, override_path, LOCK_FILENAME)
    end

    def handle_resolver_errors(&)
      yield
    rescue e : Molinillo::ResolverError
      Log.error { e.message }
      raise Shards::Error.new("Failed to resolve dependencies")
    end

    def check_crystal_version(packages)
      crystal_version = Shards::Version.new Shards.crystal_version

      packages.each do |package|
        crystal_req = MolinilloSolver.crystal_version_req(package.spec)

        if !Shards::Versions.matches?(crystal_version, crystal_req)
          Log.warn { "Shard \"#{package.name}\" may be incompatible with Crystal #{Shards.crystal_version}" }
        end
      end
    end

    def check_symlink_privilege
      {% if flag?(:win32) %}
        return if Shards::Helpers.developer_mode?
        return if Shards::Helpers.privilege_enabled?("SeCreateSymbolicLinkPrivilege")

        raise Shards::Error.new(<<-EOS)
        Shards needs symlinks to work. Please enable Developer Mode, or run Shards with elevated rights:
            https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development
        EOS
      {% end %}
    end

    def touch_install_path
      Dir.mkdir_p(Shards.install_path)
      File.touch(Shards.install_path)
    end

    # Packages named in *checksum_exempt_names* are about to record their first
    # checksum (new dependencies, or every package during `update`), so the
    # `require_checksum` rule applies only to the lock entries being reused.
    protected def check_policy(packages : Array(Package), checksum_exempt_names = Set(String).new)
      current_policy = policy
      return unless current_policy

      Log.info { "Checking dependency policies" }

      checker = PolicyChecker.new(current_policy)
      report = checker.check(packages, checksum_exempt_names)

      unless report.clean?
        report.to_terminal(STDERR)
      end

      if report.has_errors?
        raise Error.new("Policy violations found. Use 'minecart policy check' for details.")
      end
    end

    protected def policy_path : String
      Shards.config_file_path(path, MINECART_POLICY_FILENAME, POLICY_FILENAME)
    end

    protected def policy : Shards::Policy?
      @policy ||= Shards::Policy.from_file(policy_path) if File.exists?(policy_path)
    end

    protected def check_pinning
      PinningChecker.new(path, spec, Shards.strict_pinning?).check
    end

    # Copies each recorded checksum onto the resolved package and returns the
    # lock entries this resolution reuses unchanged (same name, source and version).
    protected def copy_matching_locked_checksums(packages : Array(Package)) : Array(Package)
      list_of_locked_packages = [] of Package
      return list_of_locked_packages unless lockfile?

      previous_packages = locks.shards.to_h { |package| {package.name, package} }
      packages.each do |package|
        previous = previous_packages[package.name]?
        next unless previous
        next unless previous.resolver == package.resolver && previous.version == package.version

        package.checksum = previous.checksum
        list_of_locked_packages << package
      end
      list_of_locked_packages
    end

    # Every reused lock entry must carry a checksum; only dependencies that are new
    # to the lock are trusted on first use. `--frozen` also requires that checksum
    # to be sha256, so a legacy `git-tree:` (SHA-1) entry needs an upgrade first.
    # Path dependencies are local source and are governed by the
    # `deny_path_dependencies` policy instead.
    protected def require_locked_checksums(list_of_locked_packages : Array(Package))
      list_of_fetched_packages = list_of_locked_packages.reject(&.resolver.is_a?(PathResolver))
      list_of_unchecksummed_names = list_of_fetched_packages.select(&.checksum.nil?).map(&.name)
      list_of_legacy_checksum_names = list_of_fetched_packages
        .select(&.checksum.try(&.starts_with?(LEGACY_GIT_TREE_PREFIX)))
        .map(&.name)
      list_of_rejected_legacy_names = Shards.frozen? ? list_of_legacy_checksum_names : [] of String

      unless list_of_unchecksummed_names.empty? && list_of_rejected_legacy_names.empty?
        unless Shards.allow_missing_checksums?
          raise MissingLockChecksum.new(list_of_unchecksummed_names, list_of_rejected_legacy_names)
        end

        list_of_names = list_of_unchecksummed_names + list_of_rejected_legacy_names
        Log.warn { "--allow-missing-checksums: #{LOCK_FILENAME} has no sha256 checksum for #{list_of_names.join(", ")}; trusting the current source of each." }
      end

      unless list_of_legacy_checksum_names.empty?
        Log.warn { "#{LOCK_FILENAME} has legacy git-tree (SHA-1) checksums for #{list_of_legacy_checksum_names.join(", ")}. They are still verified; run `minecart lock --update-checksums` to upgrade them to sha256." }
      end
    end

    protected def verify_checksum_before_scripts(package : Package)
      return if package.resolver.is_a?(PathResolver) && !Shards.frozen?

      if expected = package.checksum
        actual = package.compute_checksum
        unless actual && actual == expected
          raise ChecksumMismatch.new(package.name, expected, actual || "unavailable")
        end
        Log.debug { "Checksum verified for #{package.name} before scripts" }
      else
        record_checksum_on_first_use(package)
      end
    end

    protected def verify_or_compute_checksums(packages : Array(Package), already_verified = Set(String).new)
      packages.each do |package|
        next unless package.installed?
        next if already_verified.includes?(package.name)

        # A postinstall script has already changed this installed copy, so the
        # lock is checked against a fresh checkout of the locked version.
        if package.spec.scripts["postinstall"]?
          verify_locked_source(package)
          next
        end

        next if package.resolver.is_a?(PathResolver) && !Shards.frozen?

        if expected = package.checksum
          actual = package.compute_checksum
          unless actual && actual == expected
            raise ChecksumMismatch.new(package.name, expected, actual || "unavailable")
          end
          Log.debug { "Checksum verified for #{package.name}" }
        else
          record_checksum_on_first_use(package)
        end
      end
    end

    # Verifies the lock entry of an installed package whose postinstall script
    # has already run. Its directory no longer matches its source, so the
    # locked version is checked out fresh (or, for a legacy `git-tree:` entry,
    # its tree id is read from the mirror) and must match the recorded checksum.
    # Without a recorded checksum, the fresh checkout's sha256 is trusted on
    # first use. Path dependencies are local source and are not checked here.
    protected def verify_locked_source(package : Package)
      return if package.resolver.is_a?(PathResolver)

      expected = package.checksum
      unless expected
        record_checksum_on_first_use(package, package.pristine_checksum)
        return
      end

      actual = if expected.starts_with?(LEGACY_GIT_TREE_PREFIX)
                 package.resolver.checksum_for(package.version)
               else
                 package.pristine_checksum
               end
      unless actual == expected
        raise ChecksumMismatch.new(package.name, expected, actual || "unavailable")
      end
      Log.debug { "Checksum verified for #{package.name} against a fresh checkout of #{package.report_version}" }
    end

    private def record_checksum_on_first_use(package : Package, computed : String? = package.computed_checksum)
      return unless computed

      package.checksum = computed
      if package.resolver.is_a?(PathResolver)
        Log.debug { "Computed checksum for path dependency #{package.name}: #{computed}" }
      elsif Shards.frozen?
        Log.warn { "TRUST ON FIRST USE: #{package.name} (#{package.report_version}) is trusted for this install only (#{computed}); #{LOCK_FILENAME} is not changed." }
      else
        Log.warn { "TRUST ON FIRST USE: #{package.name} (#{package.report_version}) has no recorded checksum; recording #{computed} in #{LOCK_FILENAME}. Review this dependency's source before you commit #{LOCK_FILENAME}." }
      end
    end
  end
end
