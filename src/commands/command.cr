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

    protected def check_policy(packages : Array(Package))
      policy_path = Shards.config_file_path(path, MINECART_POLICY_FILENAME, POLICY_FILENAME)
      return unless File.exists?(policy_path)

      Log.info { "Checking dependency policies" }

      policy = Shards::Policy.from_file(policy_path)
      checker = PolicyChecker.new(policy)
      report = checker.check(packages)

      unless report.clean?
        report.to_terminal(STDERR)
      end

      if report.has_errors?
        raise Error.new("Policy violations found. Use 'minecart policy check' for details.")
      end
    end

    protected def check_pinning
      PinningChecker.new(path, spec, Shards.strict_pinning?).check
    end

    protected def copy_matching_locked_checksums(packages : Array(Package))
      return unless lockfile?

      previous_packages = locks.shards.to_h { |package| {package.name, package} }
      packages.each do |package|
        previous = previous_packages[package.name]?
        next unless previous
        next unless previous.resolver == package.resolver && previous.version == package.version

        package.checksum = previous.checksum
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
        if Shards.frozen?
          Log.warn { "Dependency '#{package.name}' has no checksum in shard.lock; re-run minecart update (this will become an error next release)" }
        end
        if computed = package.computed_checksum
          package.checksum = computed
          Log.debug { "Computed checksum for #{package.name}: #{computed}" }
        end
      end
    end

    protected def verify_or_compute_checksums(packages : Array(Package), already_verified = Set(String).new)
      packages.each do |package|
        next unless package.installed?
        next if already_verified.includes?(package.name)

        if Shards.frozen? && package.checksum.nil?
          Log.warn { "Dependency '#{package.name}' has no checksum in shard.lock; re-run minecart update (this will become an error next release)" }
        end

        next if !package.spec.scripts["postinstall"]?.nil?
        next if package.resolver.is_a?(PathResolver) && !Shards.frozen?

        if expected = package.checksum
          actual = package.compute_checksum
          unless actual && actual == expected
            raise ChecksumMismatch.new(package.name, expected, actual || "unavailable")
          end
          Log.debug { "Checksum verified for #{package.name}" }
        elsif computed = package.computed_checksum
          package.checksum = computed
          Log.debug { "Computed checksum for #{package.name}: #{computed}" }
        end
      end
    end
  end
end
