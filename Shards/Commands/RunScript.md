# class Shards::Commands::RunScript

Runs postinstall scripts that are pending or have changed since last execution.

When called without arguments, runs all pending scripts. When given shard
names, runs only those specific scripts.

This command exists because postinstall scripts only auto-run on first
install. If a script changes during `shards update`, the user must
explicitly run it with this command.

## Instance Methods

### `run(shard_names : Array(String))`

Runs postinstall scripts for the specified shards, or all pending if none given.

