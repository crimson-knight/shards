require "./command"
require "../molinillo_solver"

module Shards
  module Commands
    class Lock < Command
      def run(shards : Array(String), print = false, update = false, rekey = false)
        check_symlink_privilege

        Log.info { "Resolving dependencies" }

        solver = MolinilloSolver.new(spec, override)

        if lockfile?
          if update
            # update selected dependencies to latest possible versions, but
            # avoid to update unspecified dependencies, if possible:
            unless shards.empty?
              solver.locks = locks.shards.reject { |d| shards.includes?(d.name) }
            end
          else
            # install must be as conservative as possible:
            solver.locks = locks.shards
          end
        end

        solver.prepare(development: Shards.with_development?)

        packages = handle_resolver_errors { solver.solve }
        return if packages.empty?

        rekey_checksums(packages) if rekey

        if print
          Shards::Lock.write(packages, @override_path, STDOUT)
        else
          write_lockfile(packages)
        end
      end

      private def rekey_checksums(packages : Array(Package))
        previous_checksums = if lockfile?
                               locks.shards.to_h { |package| {package.name, package} }
                             else
                               {} of String => Package
                             end

        packages.each do |package|
          if previous = previous_checksums[package.name]?
            if previous.resolver == package.resolver && previous.version == package.version
              package.checksum = previous.checksum
            end
          end

          if package.resolver.is_a?(GitResolver)
            package.checksum = package.resolver.checksum_for(package.version)
          elsif package.installed?
            package.checksum = package.computed_checksum
          end
        end
      end
    end
  end
end
