require "./lock"
require "./package"
require "./resolvers/path"

module Shards
  # A postinstall script such as `shards build` runs an install of its own
  # inside the package's installed copy. That nested install reaches the
  # project's install directory through the shared `lib` link, so whatever it
  # resolves lands next to the project's verified copies. Before the script
  # runs, this writes the project's locked packages as the package's
  # `shard.lock` and passes `--production` (frozen, no development
  # dependencies) through `SHARDS_OPTS`, so the nested install resolves
  # exactly the project's locked versions and nothing else. The shard.lock the
  # package ships, if any, is put back once the script has finished.
  class HandProjectLockToScript
    NESTED_INSTALL_OPTIONS = "--production"

    def initialize(@script_owner : Package, @list_of_project_packages : Array(Package))
    end

    def perform(& : Hash(String, String?) ->) : Nil
      lock_path = File.join(@script_owner.install_path, LOCK_FILENAME)
      shipped_lock = File.file?(lock_path) ? File.read(lock_path) : nil

      Lock.write(list_of_packages_for_nested_lock, nil, lock_path)
      Log.debug { "Handed the project's lock to the postinstall script of #{@script_owner.name} at #{lock_path}" }
      begin
        yield({"SHARDS_OPTS" => nested_install_options} of String => String?)
      ensure
        if shipped_lock
          File.write(lock_path, shipped_lock)
        else
          File.delete?(lock_path)
        end
      end
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
