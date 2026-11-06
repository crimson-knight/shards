require "./lock"
require "./package"
require "./resolvers/path"
require "./helpers"
require "./script"

module Shards
  # A postinstall script such as `shards build` runs an install of its own
  # inside the package's installed copy. That nested install reaches the
  # project's install directory through the shared `lib` link, so whatever it
  # resolves lands next to the project's verified copies. Before the script
  # runs, this writes the project's locked packages as the package's
  # `shard.lock` and passes `--production` (frozen, no development
  # dependencies) through `SHARDS_OPTS`, so the nested install resolves
  # exactly the project's locked versions and nothing else. The shard.lock the
  # package ships, if any, is put back once the script has finished. Any failure
  # to hand or restore the lock is a `Script::Error`, so the caller's tree checks
  # and cleanup run on it as they do for a failing script.
  class HandProjectLockToScript
    private NESTED_INSTALL_OPTIONS = "--production"

    # What a package shipped at its `shard.lock` path.
    private record ShippedFile, content : String, permissions : File::Permissions
    private record ShippedLink, target : String

    def initialize(@script_owner : Package, @list_of_project_packages : Array(Package))
    end

    def perform(& : Hash(String, String?) ->) : Nil
      shipped_lock = read_shipped_lock
      write_handed_lock
      Log.debug { "Handed the project's lock to the postinstall script of #{@script_owner.name} at #{lock_path}" }
      begin
        yield({"SHARDS_OPTS" => nested_install_options} of String => String?)
      ensure
        restore_shipped_lock(shipped_lock)
      end
    end

    private def lock_path : String
      File.join(@script_owner.install_path, LOCK_FILENAME)
    end

    # Reads the path itself, not what a symlink there points at.
    private def read_shipped_lock : ShippedFile | ShippedLink | Nil
      info = File.info?(lock_path, follow_symlinks: false)
      return nil unless info
      return ShippedLink.new(File.readlink(lock_path)) if info.symlink?
      return ShippedFile.new(File.read(lock_path), info.permissions) if info.file?

      raise Script::Error.new("#{@script_owner.name} ships #{lock_path} as something other than a file, so the project's lock cannot be handed to its postinstall script.")
    rescue ex : File::Error
      raise Script::Error.new("Could not read #{lock_path} before the postinstall script of #{@script_owner.name}: #{ex.message}")
    end

    # Whatever sits at the path is removed first, so a symlink the package ships
    # is never written through to the file it points at.
    private def write_handed_lock : Nil
      Helpers.rm_rf!(lock_path)
      Lock.write(list_of_packages_for_nested_lock, nil, lock_path)
    rescue ex : File::Error | PathNotRemoved
      raise Script::Error.new("Could not hand the project's lock to the postinstall script of #{@script_owner.name}: #{ex.message}")
    end

    # A script that removed its own copy leaves nothing to restore into; the
    # caller's checks handle that copy.
    private def restore_shipped_lock(shipped_lock : ShippedFile | ShippedLink | Nil) : Nil
      return unless File.info?(@script_owner.install_path, follow_symlinks: false)

      Helpers.restore_owner_access(@script_owner.install_path)
      Helpers.rm_rf!(lock_path)
      if shipped_lock.is_a?(ShippedFile)
        File.write(lock_path, shipped_lock.content, perm: shipped_lock.permissions)
      elsif shipped_lock.is_a?(ShippedLink)
        File.symlink(shipped_lock.target, lock_path)
      end
    rescue ex : File::Error | PathNotRemoved
      raise Script::Error.new("Could not restore #{lock_path} after the postinstall script of #{@script_owner.name}: #{ex.message}")
    end

    # Every locked package except the script's own. A path dependency's source
    # is relative to the project root, so it is written as an absolute path
    # that still resolves from inside the package's copy.
    private def list_of_packages_for_nested_lock : Array(Package)
      @list_of_project_packages.compact_map do |package|
        next if package.name == @script_owner.name

        resolver = package.resolver
        if resolver.is_a?(PathResolver)
          absolute_resolver = PathResolver.new(package.name, File.expand_path(resolver.source, home: true))
          Package.new(package.name, absolute_resolver, package.version, package.is_override, package.checksum)
        else
          package
        end
      end
    end

    private def nested_install_options : String
      if existing_options = ENV["SHARDS_OPTS"]?.presence
        "#{existing_options} #{NESTED_INSTALL_OPTIONS}"
      else
        NESTED_INSTALL_OPTIONS
      end
    end
  end
end
