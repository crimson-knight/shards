require "./command"
require "../molinillo_solver"
require "../ai_docs"
require "../checksum"
require "../change_logger"
require "../assistant_config"

module Shards
  module Commands
    class Install < Command
      def run
        check_pinning

        if Shards.frozen? && !lockfile?
          raise Error.new("Missing shard.lock")
        end
        check_symlink_privilege

        Log.info { "Resolving dependencies" }

        solver = MolinilloSolver.new(spec, override)

        if lockfile?
          # install must be as conservative as possible:
          solver.locks = locks.shards
        end

        solver.prepare(development: Shards.with_development?)

        packages = handle_resolver_errors { solver.solve }

        list_of_locked_packages = copy_matching_locked_checksums(packages)
        locked_names = list_of_locked_packages.map(&.name).to_set
        list_of_new_names = packages.map(&.name).to_set - locked_names

        check_policy(packages, list_of_new_names)
        require_locked_checksums(list_of_locked_packages)

        if Shards.frozen?
          validate(packages)
        end

        # Every source is fetched and checked against the lock before any
        # dependency code runs: a check that fires after a postinstall script
        # has executed is not a control.
        verified_sources = verify_reused_sources(list_of_locked_packages)
        list_of_newly_installed = install(packages)
        verify_or_compute_checksums(packages, list_of_newly_installed.map(&.name).to_set, verified_sources)

        run_postinstall_scripts(list_of_newly_installed)

        AIDocsInstaller.new(path).install(packages)

        # Auto-install/update assistant config if opted in
        unless Shards.skip_ai_assistant?
          if spec.ai_assistant.try(&.auto_install)
            AssistantConfig.auto_install(path)
          end
        end

        if generate_lockfile?(packages)
          old_packages = if lockfile?
                           Shards::Lock.from_file(lockfile_path).shards
                         else
                           [] of Package
                         end
          write_lockfile(packages)
          ChangeLogger.record(path, "install", old_packages, packages, lockfile_path)
        elsif !Shards.frozen?
          # Touch lockfile so its mtime is bigger than that of shard.yml
          File.touch(lockfile_path)
        end

        # Touch install path so its mtime is bigger than that of the lockfile
        touch_install_path

        check_crystal_version(packages)
      end

      private def validate(packages)
        packages.each do |package|
          if lock = locks.shards.find { |d| d.name == package.name }
            if lock.resolver != package.resolver
              raise LockConflict.new("#{package.name} source changed")
            else
              validate_locked_version(package, lock.version)
            end
          else
            raise LockConflict.new("can't install new dependency #{package.name} in production")
          end
        end
      end

      private def validate_locked_version(package, version)
        return if package.version == version
        raise LockConflict.new("#{package.name} requirements changed")
      end

      # Installs every package that is missing and verifies each fresh copy
      # against its lock entry (or records it on first use). No script runs
      # here. Returns the packages installed by this run.
      private def install(packages : Array(Package)) : Array(Package)
        list_of_newly_installed = [] of Package
        # packages are returned by the solver in reverse topological order,
        # so transitive dependencies are installed first
        packages.each do |package|
          next unless install(package)

          verify_checksum_before_scripts(package)
          list_of_newly_installed << package
        end
        list_of_newly_installed
      end

      # Runs the postinstall script of each newly installed package (with
      # access to all transitive dependencies). Each copy is verified again
      # right before its own script, because an earlier script may have
      # changed it.
      private def run_postinstall_scripts(list_of_newly_installed : Array(Package))
        list_of_newly_installed.each do |package|
          verify_checksum_before_scripts(package)
          package.postinstall

          # always install executables because the path resolver never actually
          # installs dependencies:
          package.install_executables
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
        !Shards.frozen? && (!lockfile? || outdated_lockfile?(packages))
      end

      private def outdated_lockfile?(packages)
        return true if locks.version != Shards::Lock::CURRENT_VERSION
        return true if packages.size != locks.shards.size
        # Trigger lockfile rewrite if any locked package is missing a checksum
        return true if locks.shards.any? { |pkg| pkg.checksum.nil? }

        packages.index_by(&.name) != locks.shards.index_by(&.name)
      end
    end
  end
end
