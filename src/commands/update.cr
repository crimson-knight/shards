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
        # `update` with names re-resolves only those; without names, every one.
        re_resolved_names = shards.empty? ? packages.map(&.name).to_set : shards.to_set
        install(packages, locked_names, re_resolved_names, verified_sources)

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

      private def install(packages : Array(Package), locked_names : Set(String), re_resolved_names : Set(String), verified_sources : Set(String))
        newly_installed = [] of Package
        packages.each do |package|
          if install(package)
            verify_checksum_before_scripts(package)
            newly_installed << package
          elsif package.resolver.is_a?(PathResolver)
            verify_checksum_before_scripts(package)
          else
            # A reused copy is compared with a fresh checkout verified against
            # the lock, whatever its installed manifest says.
            verify_locked_source(package) unless verified_sources.includes?(package.name)
          end
        end

        # Set lock checksums from source state before any postinstall can
        # modify installed files.
        compute_checksums(packages, locked_names, re_resolved_names)

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

      # Records the `sha256-v2:` checksum of a fresh checkout for every package
      # whose checksum did not come from the lock, so a locally modified
      # installed copy is never what gets locked. A checksum reused from the
      # lock was verified above and stays as written, legacy `sha256:` and
      # `git-tree:` entries included, unless this update re-resolves that
      # dependency; a re-resolved legacy entry is rewritten as `sha256-v2:`.
      # Path dependencies are re-hashed because their source moves.
      private def compute_checksums(packages : Array(Package), locked_names : Set(String), re_resolved_names : Set(String))
        packages.each do |package|
          recorded = package.checksum
          unless package.resolver.is_a?(PathResolver) || recorded.nil? || !locked_names.includes?(package.name)
            next unless re_resolved_names.includes?(package.name)
            next if Checksum.current?(recorded)
          end

          if computed = package.pristine_checksum
            package.checksum = computed
          end
        end
      end
    end
  end
end
