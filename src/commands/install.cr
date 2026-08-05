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

        verified = install(packages)

        # Checksums for freshly-installed packages are verified INSIDE the
        # install loop, before each postinstall script runs — a check that
        # fires after attacker-supplied code has executed is not a control.
        # This pass covers only what that loop did not: packages that were
        # already present, and therefore ran no script this session.
        unless Shards.skip_verify?
          verify_or_compute_checksums(packages, verified)
        else
          Log.warn { "Checksum verification skipped (--skip-verify)" }
        end

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

          # verify the freshly-installed files against the locked checksum
          # BEFORE running any code they contain. Fails the install by
          # default; --checksum-warn downgrades to a warning.
          unless Shards.skip_verify?
            verify_checksum_before_scripts(package)
            verified << package.name
          end

          # then execute the postinstall script
          # (with access to all transitive dependencies):
          package.postinstall

          # always install executables because the path resolver never actually
          # installs dependencies:
          package.install_executables
        end
        verified
      end

      # Pre-script checksum gate for a single freshly-installed package.
      # Mismatch raises by default: the files on disk are not the files the
      # lock was written against, and the next thing that would happen to
      # them is script execution. --checksum-warn downgrades to a warning so
      # a knowingly-moved dependency can still be installed deliberately.
      private def verify_checksum_before_scripts(package : Package)
        return if package.resolver.is_a?(PathResolver) && !Shards.frozen?

        if expected = package.checksum
          actual = package.compute_checksum
          if actual && actual != expected
            if Shards.checksum_warn?
              Log.warn { "Checksum mismatch for #{package.name} (expected #{expected}, got #{actual}) — continuing because --checksum-warn is set" }
            else
              raise ChecksumMismatch.new(package.name, expected, actual)
            end
          else
            Log.debug { "Checksum verified for #{package.name} before scripts" }
          end
        elsif computed = package.compute_checksum
          # No checksum in the lock yet (migration case): record what was
          # actually installed so the next install has something to verify.
          package.checksum = computed
          Log.debug { "Computed checksum for #{package.name}: #{computed}" }
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

      private def verify_or_compute_checksums(packages : Array(Package), already_verified = Set(String).new)
        packages.each do |package|
          next unless package.installed?
          # Already settled pre-script during this run. Re-checking now would
          # compare against a directory the package's own postinstall script
          # may have written into (build artifacts, compiled binaries), which
          # is a guaranteed false mismatch, not a detection.
          next if already_verified.includes?(package.name)
          # A package that was already present and declares a postinstall
          # script carries that script's artifacts from an earlier run, so its
          # on-disk state cannot be compared to a source checksum. Nothing is
          # executed for it this run, so there is no pre-execution gate to make.
          next if !package.spec.scripts["postinstall"]?.nil?
          # Path dependencies in non-frozen mode are symlinks, skip verification
          # but in frozen mode they should still be verified
          next if package.resolver.is_a?(PathResolver) && !Shards.frozen?

          if expected = package.checksum
            # Verify against locked checksum
            actual = package.compute_checksum
            if actual && actual != expected
              if Shards.checksum_warn?
                Log.warn { "Checksum mismatch for #{package.name} (expected #{expected}, got #{actual}) — continuing because --checksum-warn is set" }
              else
                raise ChecksumMismatch.new(package.name, expected, actual)
              end
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
