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
    # to the lock are trusted on first use. Legacy entries (`git-tree:` and the
    # v1 `sha256:`) are verified with their original rules, `--frozen` included,
    # so existing lock files keep installing. Path dependencies are local source
    # and are governed by the `deny_path_dependencies` policy instead.
    protected def require_locked_checksums(list_of_locked_packages : Array(Package))
      list_of_fetched_packages = list_of_locked_packages.reject(&.resolver.is_a?(PathResolver))
      list_of_unchecksummed_names = list_of_fetched_packages.select(&.checksum.nil?).map(&.name)

      unless list_of_unchecksummed_names.empty?
        raise MissingLockChecksum.new(list_of_unchecksummed_names) unless Shards.allow_missing_checksums?

        Log.warn { "--allow-missing-checksums: #{LOCK_FILENAME} has no checksum for #{list_of_unchecksummed_names.join(", ")}; trusting the current source of each." }
      end

      list_of_legacy_names = list_of_fetched_packages
        .select { |package| (recorded = package.checksum) && Checksum.legacy?(recorded) }
        .map(&.name)
      unless list_of_legacy_names.empty?
        Log.info { "#{LOCK_FILENAME} has legacy (git-tree or sha256 v1) checksums for #{list_of_legacy_names.join(", ")}. They are still verified; `minecart lock --update-checksums` upgrades them to #{Checksum::PREFIX.rchop(':')}." }
      end
    end

    # Verifies an installed copy against its lock entry before any script can
    # run. The first check also records the copy's full `sha256-v2:` digest;
    # every later check (right before the package's own postinstall script)
    # requires that digest unchanged, so an earlier script cannot rewrite the
    # files this one runs, whatever kind of checksum the lock holds.
    protected def verify_checksum_before_scripts(package : Package)
      return if package.resolver.is_a?(PathResolver) && !Shards.frozen?

      if first_digest = package.first_verified_digest
        actual = package.computed_checksum
        unless actual == first_digest
          raise ChecksumMismatch.new(package.name, first_digest, actual || "unavailable")
        end
        Log.debug { "Installed copy of #{package.name} unchanged since it was verified" }
        return
      end

      if expected = package.checksum
        actual = package.compute_checksum
        unless actual && actual == expected
          raise ChecksumMismatch.new(package.name, expected, actual || "unavailable")
        end
        verify_installed_copy_matches_source(package) if Checksum.legacy?(expected)
        Log.debug { "Checksum verified for #{package.name} before scripts" }
      else
        record_checksum_on_first_use(package)
      end
      package.first_verified_digest = package.computed_checksum
    end

    # A legacy entry leaves parts of the installed copy unchecked (`git-tree:`
    # is read from the Git mirror; v1 `sha256:` skips `lib/` and symlinked
    # directories). Once the entry has verified the locked version, the
    # installed copy must equal a fresh checkout of that version file for file.
    private def verify_installed_copy_matches_source(package : Package)
      return if package.resolver.is_a?(PathResolver)

      installed = package.computed_checksum
      source = package.pristine_checksum
      unless installed && installed == source
        raise ChecksumMismatch.new(package.name, source || "unavailable", installed || "unavailable")
      end
    end

    protected def verify_or_compute_checksums(packages : Array(Package), already_verified = Set(String).new, verified_sources = Set(String).new)
      packages.each do |package|
        next unless package.installed?
        next if already_verified.includes?(package.name)

        # A reused copy is never trusted as it stands: it is compared with a
        # fresh checkout that is verified against the lock (or, with no lock
        # entry, trusted on first use), whatever its installed manifest says.
        unless package.resolver.is_a?(PathResolver)
          verify_locked_source(package) unless verified_sources.includes?(package.name)
          next
        end

        # Path dependencies are their own source; `--frozen` checks them.
        next unless Shards.frozen?

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

    # Before anything is installed or any script runs, checks that the source
    # of every reused lock entry that is already installed still matches its
    # recorded checksum. The solver has read these sources (for example to find
    # their dependencies), so a moved tag must fail here, before a new
    # transitive package's script could run, even though the installed copy
    # still matches. Entries that are not installed yet are verified as they
    # are installed, which also happens before any script runs. Returns the
    # names it verified.
    protected def verify_reused_sources(list_of_locked_packages : Array(Package)) : Set(String)
      verified_names = Set(String).new
      list_of_locked_packages.each do |package|
        next if package.resolver.is_a?(PathResolver)
        next unless package.checksum
        next unless package.installed?

        verify_locked_source(package)
        verified_names << package.name
      end
      verified_names
    end

    # Verifies the lock entry of a reused installed package. The locked
    # version is checked out fresh (or, for a legacy `git-tree:` entry, its
    # tree id is read from the mirror) and must match the recorded checksum.
    # Without a recorded checksum, the fresh checkout's checksum is trusted on
    # first use. Either way, the installed copy may hold postinstall output,
    # but every file of the fresh checkout must still be unchanged in it.
    # Path dependencies are local source and are not checked here.
    protected def verify_locked_source(package : Package)
      return if package.resolver.is_a?(PathResolver)

      if expected = package.checksum
        actual = package.source_checksum_like(expected)
        unless actual == expected
          raise ChecksumMismatch.new(package.name, expected, actual || "unavailable")
        end
      else
        record_checksum_on_first_use(package, package.pristine_checksum)
      end

      if File.exists?(package.install_path) && !package.installed_copy_matches_source?
        raise InstalledCopyModified.new(package.name, package.install_path)
      end
      Log.debug { "Checksum verified for #{package.name} against a fresh checkout of #{package.report_version}" }
    end

    # Runs the postinstall script of each newly installed package (with access
    # to all transitive dependencies) and yields each package after its turn.
    # Each copy is verified again right before its own script, because an
    # earlier script may have changed it. A script can also reach every other
    # installed tree through the shared `lib` link, so after each script that
    # ran, every other installed copy must still match the digest it had when
    # the scripts began, and the install directory may hold no new entry
    # outside the script's own copy. The script's own copy may change (that is
    # its build output). On a failure, the script's copy, every changed copy
    # and every new entry are removed, so no later install reuses them.
    protected def run_postinstall_scripts(packages : Array(Package), list_of_newly_installed : Array(Package), & : Package ->) : Nil
      trees_before_scripts = record_trees_scripts_can_reach(packages, list_of_newly_installed)

      list_of_newly_installed.each do |package|
        verify_checksum_before_scripts(package)
        if run_postinstall_script(package, packages, trees_before_scripts) && trees_before_scripts
          verify_trees_unchanged_by_script(package, packages, trees_before_scripts)
          verify_no_lib_entry_added_by_script(package, packages, trees_before_scripts)
          accept_own_output_of(package, trees_before_scripts)
        end
        yield package
      end
    end

    protected def run_postinstall_scripts(packages : Array(Package), list_of_newly_installed : Array(Package)) : Nil
      run_postinstall_scripts(packages, list_of_newly_installed) { }
    end

    # What a postinstall script could change, recorded after every installed
    # copy was verified and before any script runs: the `sha256-v2:` digest of
    # each guarded copy by package name, and the names of the entries in the
    # install directory.
    private record TreesBeforeScripts,
      digests_of_installed_trees : Hash(String, String),
      list_of_lib_entries : Set(String)

    # Returns nil when no newly installed package declares a postinstall
    # script, so no tree is hashed for nothing. Path dependencies are the
    # project's own source and are left out unless `--frozen` checks them.
    private def record_trees_scripts_can_reach(packages : Array(Package), list_of_newly_installed : Array(Package)) : TreesBeforeScripts?
      return nil if Shards.skip_postinstall?
      return nil unless list_of_newly_installed.any? { |package| package.spec.scripts["postinstall"]? }

      digests = {} of String => String
      packages.each do |package|
        next unless guards_installed_tree?(package)
        if digest = package.computed_checksum
          digests[package.name] = digest
        end
      end
      TreesBeforeScripts.new(digests, Helpers.list_install_entries(Shards.install_path))
    end

    # Runs one package's postinstall script and returns whether it ran. A script
    # that fails still ran: every copy it changed and every install-directory
    # entry it added are removed, with its own copy, before the failure is
    # raised again with the removed paths named. A `File::Error` gets the same
    # treatment, because the script ran and can make the records that follow it
    # fail to write.
    private def run_postinstall_script(script_owner : Package, packages : Array(Package), trees_before_scripts : TreesBeforeScripts?) : Bool
      script_ran = script_owner.postinstall(packages)
      if script_ran && !script_owner.installed_copy_in_place?
        raise Script::Error.new("The postinstall script of #{script_owner.name} removed its own copy, or replaced it with a link.")
      end
      script_ran
    rescue script_failure : Script::Error | File::Error
      raise script_failure unless trees_before_scripts

      list_of_changed = list_changed_by_script(script_owner, packages, trees_before_scripts)
      list_of_removed_paths = discard_what_script_touched(script_owner, list_of_changed, packages, trees_before_scripts)
      raise Script::Error.new("#{script_failure.message}\nRemoved #{list_of_removed_paths.join(", ")} so nothing the failed script wrote is reused.")
    end

    private def verify_trees_unchanged_by_script(script_owner : Package, packages : Array(Package), trees_before_scripts : TreesBeforeScripts) : Nil
      list_of_changed = list_changed_by_script(script_owner, packages, trees_before_scripts)
      return if list_of_changed.empty?

      first_changed = list_of_changed.first
      expected = trees_before_scripts.digests_of_installed_trees[first_changed.name]
      actual = digest_of_tree_or_nil(first_changed) || "missing or unreadable"
      list_of_removed_paths = discard_what_script_touched(script_owner, list_of_changed, packages, trees_before_scripts)
      raise InstalledCopyChangedByScript.new(first_changed.name, first_changed.install_path, script_owner.name, expected, actual, list_of_removed_paths)
    end

    # The guarded copies, other than the script owner, whose digest no longer
    # matches the one recorded before the scripts began.
    private def list_changed_by_script(script_owner : Package, packages : Array(Package), trees_before_scripts : TreesBeforeScripts) : Array(Package)
      digests = trees_before_scripts.digests_of_installed_trees
      packages.select do |package|
        next false if package.name == script_owner.name
        next false unless expected = digests[package.name]?
        digest_of_tree_or_nil(package) != expected
      end
    end

    private def verify_no_lib_entry_added_by_script(script_owner : Package, packages : Array(Package), trees_before_scripts : TreesBeforeScripts) : Nil
      list_of_new_entries = Helpers.list_install_entries(Shards.install_path) - trees_before_scripts.list_of_lib_entries
      list_of_new_entries.delete(script_owner.name)
      return if list_of_new_entries.empty?

      first_entry_path = File.join(Shards.install_path, list_of_new_entries.to_a.sort.first)
      list_of_removed_paths = discard_what_script_touched(script_owner, [] of Package, packages, trees_before_scripts)
      raise LibEntryAddedByScript.new(first_entry_path, script_owner.name, list_of_removed_paths)
    end

    # The script's own copy may hold its build output; later scripts must
    # leave that output alone, so its digest moves to what the script wrote.
    private def accept_own_output_of(script_owner : Package, trees_before_scripts : TreesBeforeScripts) : Nil
      return unless trees_before_scripts.digests_of_installed_trees.has_key?(script_owner.name)

      if digest = digest_of_tree_or_nil(script_owner)
        trees_before_scripts.digests_of_installed_trees[script_owner.name] = digest
      end
      Log.debug { "Postinstall script of #{script_owner.name} left every other installed copy unchanged" }
    end

    # Removes the script's own copy (its output was built from files that are
    # not the verified ones), every changed copy, and every install-directory
    # entry that appeared after the scripts began. Returns the removed paths, or
    # raises `ScriptLeftPathsBehind` naming any that are still there.
    private def discard_what_script_touched(script_owner : Package, list_of_changed : Array(Package), packages : Array(Package), trees_before_scripts : TreesBeforeScripts) : Array(String)
      Helpers.restore_owner_access(Shards.install_path)
      list_of_removed_paths = [] of String
      list_of_stuck_paths = [] of String

      ([script_owner] + list_of_changed).each do |package|
        begin
          package.discard_installation
          list_of_removed_paths << package.install_path
        rescue PathNotRemoved
          list_of_stuck_paths << package.install_path
        rescue ex : File::Error
          # The copy is gone; only its record could not be written, and a record
          # with no copy means reinstall.
          Log.warn { "Could not update the install records for #{package.name}: #{ex.message}" }
          list_of_removed_paths << package.install_path
        end
      end

      list_of_new_entries = Helpers.list_install_entries(Shards.install_path) - trees_before_scripts.list_of_lib_entries
      list_of_new_entries.to_a.sort.each do |entry_name|
        entry_path = File.join(Shards.install_path, entry_name)
        Shards.info.installed.delete(entry_name)
        begin
          Helpers.rm_rf!(entry_path)
          list_of_removed_paths << entry_path
        rescue PathNotRemoved
          list_of_stuck_paths << entry_path
        end
      end
      begin
        Shards.info.save unless list_of_new_entries.empty?
      rescue ex : File::Error
        Log.warn { "Could not update the install records: #{ex.message}" }
      end

      raise ScriptLeftPathsBehind.new(script_owner.name, list_of_stuck_paths, list_of_removed_paths) unless list_of_stuck_paths.empty?
      list_of_removed_paths
    end

    # The digest of an installed copy, or nil when the copy is gone or a script
    # made part of it unreadable. Either way it no longer matches its record.
    private def digest_of_tree_or_nil(package : Package) : String?
      package.computed_checksum
    rescue File::Error
      nil
    end

    private def guards_installed_tree?(package : Package) : Bool
      return false if package.resolver.is_a?(PathResolver) && !Shards.frozen?
      package.installed?
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
