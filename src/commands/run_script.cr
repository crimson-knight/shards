require "./command"

module Shards
  module Commands
    # Runs postinstall scripts that are pending or have changed since last execution.
    #
    # When called without arguments, runs all pending scripts. When given shard
    # names, runs only those specific scripts.
    #
    # This command exists because postinstall scripts only auto-run on first
    # install. If a script changes during `shards update`, the user must
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

        Log.info { "Running postinstall of #{name}: #{command}" }
        Script.run(installed.install_path, command, "postinstall", name)

        script_hash = PostinstallInfo.hash_script(command)
        info = Shards.postinstall_info
        info.shards[name] = PostinstallInfo::Entry.new(script_hash, has_run: true)
        info.save
      end
    end
  end
end
