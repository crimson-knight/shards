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

        copy_matching_locked_checksums(packages)

        check_policy(packages)

        if Shards.frozen?
          validate(packages)
        end

        verified = install(packages)

        # Checksums for freshly-installed packages are verified INSIDE the
        # install loop, before each postinstall script runs — a check that
        # fires after attacker-supplied code has executed is not a control.
        # This pass covers only what that loop did not: packages that were
        # already present, and therefore ran no script this session.
        verify_or_compute_checksums(packages, verified)

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

      # Returns the names of packages whose checksum was settled pre-script, so
      # the later pass does not re-check them against a directory their own
      # postinstall script has since modified.
      private def install(packages : Array(Package)) : Set(String)
        verified = Set(String).new
        # packages are returned by the solver in reverse topological order,
        # so transitive dependencies are installed first
        packages.each do |package|
          # first install the dependency:
          next unless install(package)

          # Verify the source identity before running any dependency code.
          verify_checksum_before_scripts(package)
          verified << package.name

          # then execute the postinstall script
          # (with access to all transitive dependencies):
          package.postinstall

          # always install executables because the path resolver never actually
          # installs dependencies:
          package.install_executables
        end
        verified
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
