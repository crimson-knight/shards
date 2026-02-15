require "./lock"
require "./package"

module Shards
  class LockfileDiffer
    record Change,
      name : String,
      status : Status,
      from_version : String?,
      to_version : String?,
      from_commit : String?,
      to_commit : String?,
      from_source : String?,
      to_source : String?,
      from_resolver_key : String?,
      to_resolver_key : String?

    enum Status
      Added
      Updated
      Removed
      Unchanged
    end

    # Compare two package sets and produce changes
    def self.diff(from_packages : Array(Package), to_packages : Array(Package)) : Array(Change)
      from_map = from_packages.to_h { |p| {p.name, p} }
      to_map = to_packages.to_h { |p| {p.name, p} }
      all_names = (from_map.keys + to_map.keys).uniq

      changes = [] of Change

      all_names.each do |name|
        from_pkg = from_map[name]?
        to_pkg = to_map[name]?

        if from_pkg.nil? && to_pkg
          # Added
          changes << Change.new(
            name: name,
            status: Status::Added,
            from_version: nil,
            to_version: extract_version(to_pkg.version),
            from_commit: nil,
            to_commit: extract_commit(to_pkg.version),
            from_source: nil,
            to_source: to_pkg.resolver.source,
            from_resolver_key: nil,
            to_resolver_key: to_pkg.resolver.class.key
          )
        elsif from_pkg && to_pkg.nil?
          # Removed
          changes << Change.new(
            name: name,
            status: Status::Removed,
            from_version: extract_version(from_pkg.version),
            to_version: nil,
            from_commit: extract_commit(from_pkg.version),
            to_commit: nil,
            from_source: from_pkg.resolver.source,
            to_source: nil,
            from_resolver_key: from_pkg.resolver.class.key,
            to_resolver_key: nil
          )
        elsif from_pkg && to_pkg
          from_ver = extract_version(from_pkg.version)
          to_ver = extract_version(to_pkg.version)
          from_commit_val = extract_commit(from_pkg.version)
          to_commit_val = extract_commit(to_pkg.version)
          from_src = from_pkg.resolver.source
          to_src = to_pkg.resolver.source

          if from_ver == to_ver && from_commit_val == to_commit_val && from_src == to_src && from_pkg.resolver.class.key == to_pkg.resolver.class.key
            # Unchanged - still emit it but with Unchanged status
            changes << Change.new(
              name: name,
              status: Status::Unchanged,
              from_version: from_ver,
              to_version: to_ver,
              from_commit: from_commit_val,
              to_commit: to_commit_val,
              from_source: from_src,
              to_source: to_src,
              from_resolver_key: from_pkg.resolver.class.key,
              to_resolver_key: to_pkg.resolver.class.key
            )
          else
            # Updated
            changes << Change.new(
              name: name,
              status: Status::Updated,
              from_version: from_ver,
              to_version: to_ver,
              from_commit: from_commit_val,
              to_commit: to_commit_val,
              from_source: from_src,
              to_source: to_src,
              from_resolver_key: from_pkg.resolver.class.key,
              to_resolver_key: to_pkg.resolver.class.key
            )
          end
        end
      end

      # Sort: Added first, then Updated, then Removed, then Unchanged; alpha within each
      changes.sort_by! { |c| {c.status.value, c.name} }
      changes
    end

    private def self.extract_version(version : Version) : String
      value = version.value
      if match = value.match(VERSION_AT_GIT_COMMIT)
        match[1]
      elsif match = value.match(VERSION_AT_HG_COMMIT)
        match[1]
      elsif match = value.match(VERSION_AT_FOSSIL_COMMIT)
        match[1]
      else
        value
      end
    end

    private def self.extract_commit(version : Version) : String?
      value = version.value
      if match = value.match(VERSION_AT_GIT_COMMIT)
        match[2]
      elsif match = value.match(VERSION_AT_HG_COMMIT)
        match[2]
      elsif match = value.match(VERSION_AT_FOSSIL_COMMIT)
        match[2]
      else
        nil
      end
    end
  end
end
