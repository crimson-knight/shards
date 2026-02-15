require "./command"
require "../molinillo_solver"
require "../ai_docs"
require "../checksum"
require "../change_logger"

module Shards
  module Commands
    class Update < Command
      def run(shards : Array(String))
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
        check_policy(packages)
        install(packages)

        # Compute checksums for all packages (update always regenerates)
        compute_checksums(packages)

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

      private def install(packages : Array(Package))
        # first install all dependencies:
        installed = packages.compact_map { |package| install(package) }

        # then execute the postinstall script of installed dependencies (with
        # access to all transitive dependencies):
        installed.each(&.postinstall)

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

      private def compute_checksums(packages : Array(Package))
        packages.each do |package|
          next unless package.installed?
          if computed = package.compute_checksum
            package.checksum = computed
          end
        end
      end
    end
  end
end
