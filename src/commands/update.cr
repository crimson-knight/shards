require "./command"
require "../molinillo_solver"
require "../ai_docs"
require "../checksum"
require "../change_logger"

module Shards
  module Commands
    class Update < Command
      def run(shards : Array(String))
        check_pinning
        check_symlink_privilege

        Log.info { "Resolving dependencies" }

        solver = MolinilloSolver.new(spec, override)

        if lockfile? && !shards.empty?
          # update selected dependencies to latest possible versions, but
          # avoid to update unspecified dependencies, if possible:
          solver.locks = locks.shards.reject { |d| shards.includes?(d.name) }
        end

        solver.prepare(development: Shards.with_development?)

        packages = handle_resolver_errors { solver.solve }
        # Names whose checksum came from the lock; every other checksum is recorded fresh.
        list_of_locked_packages = copy_matching_locked_checksums(packages).select(&.checksum)
        locked_names = list_of_locked_packages.map(&.name).to_set
        # update records a checksum for every package from its current source.
        check_policy(packages, packages.map(&.name).to_set)
        verified_sources = verify_reused_sources(list_of_locked_packages)
        install(packages, locked_names, verified_sources)

        AIDocsInstaller.new(path).install(packages)

        if generate_lockfile?(packages)
          old_packages = if lockfile?
                           Shards::Lock.from_file(lockfile_path).shards
                         else
                           [] of Package
                         end
          write_lockfile(packages)
          ChangeLogger.record(path, "update", old_packages, packages, lockfile_path)
        else
          # Touch lockfile so its mtime is bigger than that of shard.yml
          File.touch(lockfile_path)
        end

        # Touch install path so its mtime is bigger than that of the lockfile
        touch_install_path

        check_crystal_version(packages)
      end

      private def install(packages : Array(Package), locked_names : Set(String), verified_sources : Set(String))
        newly_installed = [] of Package
        packages.each do |package|
          if install(package)
            verify_checksum_before_scripts(package)
            newly_installed << package
          elsif package.spec.scripts["postinstall"]?
            # Its postinstall already ran, so check the lock against the source.
            verify_locked_source(package) unless verified_sources.includes?(package.name)
          else
            verify_checksum_before_scripts(package)
          end
        end

        # Set lock checksums from source state before any postinstall can
        # modify installed files.
        compute_checksums(packages, locked_names)
        verify_reused_installed_copies(packages, newly_installed)

        # then execute the postinstall script of installed dependencies (with
        # access to all transitive dependencies). Each copy is verified again
        # right before its own script, because an earlier script may have
        # changed it.
        newly_installed.each do |package|
          verify_checksum_before_scripts(package)
          package.postinstall
        end

        # always install executables because the path resolver never actually
        # installs dependencies:
        packages.each(&.install_executables)
      end

      # An installed copy that `update` keeps (no postinstall output to allow
      # for) must match the checksum about to be locked, so a locally modified
      # copy fails instead of hiding behind a clean lock entry.
      private def verify_reused_installed_copies(packages : Array(Package), newly_installed : Array(Package))
        packages.each do |package|
          next if newly_installed.includes?(package)
          next if package.resolver.is_a?(PathResolver)
          next if package.spec.scripts["postinstall"]?

          expected = package.checksum
          next unless expected
          next if expected.starts_with?(LEGACY_GIT_TREE_PREFIX)

          actual = package.compute_checksum
          unless actual == expected
            raise ChecksumMismatch.new(package.name, expected, actual || "unavailable")
          end
        end
      end

      private def install(package : Package)
        if package.installed?
          Log.info { "Using #{package.name} (#{package.report_version})" }
          return
        end

        Log.info { "Installing #{package.name} (#{package.report_version})" }
        package.install
        package
      end

      private def generate_lockfile?(packages)
        !Shards.frozen?
      end

      # Records the sha256 checksum of a fresh checkout for every package whose
      # checksum did not come from the lock, so a locally modified installed copy
      # is never what gets locked. A sha256 checksum reused from the lock was
      # verified above and stays. Legacy `git-tree:` entries, verified above,
      # are upgraded. Path dependencies are re-hashed because their source moves.
      private def compute_checksums(packages : Array(Package), locked_names : Set(String))
        packages.each do |package|
          recorded = package.checksum
          is_reused_current = locked_names.includes?(package.name) &&
                              !recorded.nil? &&
                              Checksum.current?(recorded)
          next if is_reused_current && !package.resolver.is_a?(PathResolver)

          if computed = package.pristine_checksum
            package.checksum = computed
          end
        end
      end
    end
  end
end
