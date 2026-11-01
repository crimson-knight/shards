require "./command"

module Shards
  module Commands
    # Runs postinstall scripts that are pending or have changed since last execution.
    #
    # When called without arguments, runs all pending scripts. When given shard
    # names, runs only those specific scripts.
    #
    # This command exists because postinstall scripts only auto-run on first
    # install. If a script changes during `minecart update`, the user must
    # explicitly run it with this command.
    class RunScript < Command
      # Runs postinstall scripts for the specified shards, or all pending if none given.
      def run(shard_names : Array(String))
        if shard_names.empty?
          run_all_pending
        else
          shard_names.each { |name| run_for(name) }
        end
      end

      private def run_all_pending
        info = Shards.postinstall_info
        pending = info.shards.select { |_, entry| !entry.has_run }

        if pending.empty?
          Log.info { "No pending postinstall scripts." }
          return
        end

        pending.each_key { |name| run_for(name) }
      end

      private def run_for(name : String)
        installed = Shards.info.installed[name]?
        raise Error.new("Shard #{name.inspect} is not installed") unless installed
        raise Error.new("Shard #{name.inspect} has no postinstall script") unless installed.spec.scripts["postinstall"]?

        check_postinstall_policy(name)
        package = installed.resolver.is_a?(PathResolver) ? installed : reinstall_verified(installed)

        command = package.spec.scripts["postinstall"]?
        raise Error.new("Shard #{name.inspect} has no postinstall script") unless command

        Log.info { "Running postinstall of #{name}: #{command}" }
        Script.run(package.install_path, command, "postinstall", name)

        script_hash = PostinstallInfo.hash_script(command)
        info = Shards.postinstall_info
        info.shards[name] = PostinstallInfo::Entry.new(script_hash, has_run: true)
        info.save
      end

      private def check_postinstall_policy(name : String)
        current_policy = policy
        return unless current_policy && current_policy.security.block_postinstall?

        raise Error.new("#{policy_path} blocks postinstall scripts (security.block_postinstall); not running the script of #{name.inspect}")
      end

      # The installed copy may have been edited since it was verified, so the
      # script runs from a fresh install of the locked version, verified
      # against its lock entry the way `install` verifies it.
      private def reinstall_verified(installed : Package) : Package
        raise Error.new("No #{LOCK_FILENAME} found; run `minecart install` before running postinstall scripts") unless lockfile?

        locked = locks.shards.find { |package| package.name == installed.name }
        unless locked && locked.resolver == installed.resolver && locked.version == installed.version
          raise Error.new("Installed #{installed.name.inspect} does not match #{LOCK_FILENAME}; run `minecart install` first")
        end

        unless locked.checksum || Shards.allow_missing_checksums?
          raise MissingLockChecksum.new([locked.name])
        end

        Log.info { "Reinstalling #{locked.name} (#{locked.report_version}) from its locked source" }
        locked.install
        verify_checksum_before_scripts(locked)
        locked
      end
    end
  end
end
