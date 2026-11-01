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

        command = installed.spec.scripts["postinstall"]?
        raise Error.new("Shard #{name.inspect} has no postinstall script") unless command

        verify_before_running(installed)

        Log.info { "Running postinstall of #{name}: #{command}" }
        Script.run(installed.install_path, command, "postinstall", name)

        script_hash = PostinstallInfo.hash_script(command)
        info = Shards.postinstall_info
        info.shards[name] = PostinstallInfo::Entry.new(script_hash, has_run: true)
        info.save
      end

      # Applies the same gates as `install` before any dependency code runs:
      # the `block_postinstall` policy, and a lock entry for this exact version
      # whose checksum matches a fresh checkout of that version.
      private def verify_before_running(installed : Package)
        if current_policy = policy
          if current_policy.security.block_postinstall?
            raise Error.new("#{policy_path} blocks postinstall scripts (security.block_postinstall); not running the script of #{installed.name.inspect}")
          end
        end

        return if installed.resolver.is_a?(PathResolver)
        raise Error.new("No #{LOCK_FILENAME} found; run `minecart install` before running postinstall scripts") unless lockfile?

        locked = locks.shards.find { |package| package.name == installed.name }
        unless locked && locked.resolver == installed.resolver && locked.version == installed.version
          raise Error.new("Installed #{installed.name.inspect} does not match #{LOCK_FILENAME}; run `minecart install` first")
        end

        unless locked.checksum || Shards.allow_missing_checksums?
          raise MissingLockChecksum.new([locked.name], [] of String)
        end

        verify_locked_source(locked)
      end
    end
  end
end
