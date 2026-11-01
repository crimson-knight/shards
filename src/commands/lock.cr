require "./command"
require "../molinillo_solver"

module Shards
  module Commands
    class Lock < Command
      def run(shards : Array(String), print = false, update = false, rekey = false, update_checksums = false)
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

        # Keep the checksum of every entry whose source and version are unchanged.
        list_of_locked_packages = copy_matching_locked_checksums(packages)

        if rekey
          rekey_checksums(packages)
        else
          upgrade_legacy_checksums(list_of_locked_packages) if update_checksums
          record_new_checksums(packages - list_of_locked_packages)
        end

        if print
          Shards::Lock.write(packages, @override_path, STDOUT)
        else
          write_lockfile(packages)
        end
      end

      # Re-trusts the current source: every fetched dependency gets the
      # `sha256-v2:` checksum of a fresh install of its locked version.
      private def rekey_checksums(packages : Array(Package))
        packages.each do |package|
          if package.resolver.is_a?(PathResolver)
            package.checksum = package.computed_checksum if package.installed?
          else
            package.checksum = package.pristine_checksum
          end
        end
      end

      # Entries that are new to the lock (or changed version or source) get the
      # `sha256-v2:` checksum of a fresh checkout of their locked version.
      private def record_new_checksums(list_of_new_packages : Array(Package))
        list_of_new_packages.each do |package|
          next if package.resolver.is_a?(PathResolver)

          package.checksum = package.pristine_checksum
        end
      end

      # Upgrades legacy entries (`git-tree:` and v1 `sha256:`) to `sha256-v2:`
      # without re-trusting anything: each is verified with its original rules
      # against a fresh checkout (or, for a tree id, the Git mirror) before the
      # `sha256-v2:` checksum of that same version is recorded. Current entries
      # keep their recorded checksum.
      private def upgrade_legacy_checksums(list_of_locked_packages : Array(Package))
        list_of_upgraded_names = [] of String

        list_of_locked_packages.each do |package|
          recorded = package.checksum
          next unless recorded
          next if Checksum.current?(recorded)

          actual = package.source_checksum_like(recorded)
          raise ChecksumMismatch.new(package.name, recorded, actual || "unavailable") unless actual == recorded

          package.checksum = package.pristine_checksum
          list_of_upgraded_names << package.name
        end

        if list_of_upgraded_names.empty?
          Log.info { "No legacy checksums in #{LOCK_FILENAME}" }
        else
          Log.info { "Upgraded legacy checksums to #{Checksum::PREFIX.rchop(':')} for: #{list_of_upgraded_names.join(", ")}" }
        end
      end
    end
  end
end
