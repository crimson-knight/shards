require "./command"
require "../molinillo_solver"
require "../ai_docs"
require "../checksum"
require "../change_logger"

module Shards
  module Commands
    class Install < Command
      def run
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

        # Propagate checksums from lock file to resolved packages
        if lockfile?
          lock_checksums = locks.shards.to_h { |p| {p.name, p.checksum} }
          packages.each do |pkg|
            pkg.checksum = lock_checksums[pkg.name]?
          end
        end

        check_policy(packages)

        if Shards.frozen?
          validate(packages)
        end

        install(packages)

        # Checksum verification/computation
        unless Shards.skip_verify?
          verify_or_compute_checksums(packages)
        else
          Log.warn { "Checksum verification skipped (--skip-verify)" }
        end

        AIDocsInstaller.new(path).install(packages)

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

      private def install(packages : Array(Package))
        # packages are returned by the solver in reverse topological order,
        # so transitive dependencies are installed first
        packages.each do |package|
          # first install the dependency:
          next unless install(package)

          # then execute the postinstall script
          # (with access to all transitive dependencies):
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

      private def verify_or_compute_checksums(packages : Array(Package))
        packages.each do |package|
          next unless package.installed?
          # Path dependencies in non-frozen mode are symlinks, skip verification
          # but in frozen mode they should still be verified
          next if package.resolver.is_a?(PathResolver) && !Shards.frozen?

          if expected = package.checksum
            # Verify against locked checksum
            actual = package.compute_checksum
            if actual && actual != expected
              raise ChecksumMismatch.new(package.name, expected, actual)
            end
            Log.debug { "Checksum verified for #{package.name}" }
          else
            # No checksum in lock file yet (migration case) -- compute and store
            if computed = package.compute_checksum
              package.checksum = computed
              Log.debug { "Computed checksum for #{package.name}: #{computed}" }
            end
          end
        end
      end
    end
  end
end
