require "./config"
require "./policy"
require "./spec"
require "./resolvers/path"
require "./resolvers/git"
require "./errors"

module Shards
  class PinningChecker
    EXACT_VERSION = /\A=?\s*\d+(?:\.\d+)*(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\z/

    def initialize(@path : String, @spec : Spec, @strict : Bool = false)
    end

    def check : Nil
      rules = policy_dependency_rules
      require_exact = rules.require_exact
      strict = @strict || Shards.strict_pinning?
      has_legacy_library_declaration = @spec.pinning == "library"

      if has_legacy_library_declaration
        Log.warn { "Deprecated shard.yml key pinning: library; use .minecart-policy.yml rules.dependencies.publishes_version_ranges: true" }
      end

      if rules.publishes_version_ranges? || has_legacy_library_declaration
        check_library_lock
        return unless rules.has_explicit_require_exact && require_exact == "true"
      end

      return if require_exact == "false" && !strict

      errors = [] of String
      @spec.dependencies.each do |dependency|
        next if dependency.resolver.is_a?(PathResolver)

        if reason = unpinned_reason(dependency.requirement)
          message = "dependency '#{dependency.name}' is not pinned (#{reason}); pin an exact version or commit, or set rules.dependencies.publishes_version_ranges: true in .minecart-policy.yml"
          if strict || require_exact == "true"
            errors << message
          else
            Log.warn { message }
          end
        elsif reason = exact_version_reason(dependency.requirement)
          Log.info { "dependency '#{dependency.name}' uses an exact version #{reason}; commit plus the lock checksum is stronger" }
        end
      end

      return if errors.empty?

      errors.each { |message| Log.error { message } }
      raise PinningError.new("Root dependencies must be pinned")
    end

    private def policy_dependency_rules : Policy::DependencyRules
      policy_path = Shards.config_file_path(@path, MINECART_POLICY_FILENAME, POLICY_FILENAME)
      return Policy.new.dependencies unless File.exists?(policy_path)

      Policy.from_file(policy_path).dependencies
    end

    private def check_library_lock
      lock_path = File.join(@path, LOCK_FILENAME)
      reason = if !File.exists?(lock_path)
                 "shard.lock is missing"
               elsif ignored_lockfile?
                 "shard.lock is gitignored"
               elsif !committed_lockfile?
                 "shard.lock is not committed"
               end
      return unless reason

      message = "publishes_version_ranges requires a committed shard.lock; #{reason}"
      if @strict || Shards.strict_pinning?
        Log.error { message }
        raise PinningError.new("A committed shard.lock is required for a library")
      end
      Log.warn { message }
    end

    private def ignored_lockfile? : Bool
      Process.run(
        "git",
        ["check-ignore", "--no-index", "-q", "--", LOCK_FILENAME],
        chdir: @path
      ).success?
    rescue
      false
    end

    private def committed_lockfile? : Bool
      Process.run(
        "git",
        ["cat-file", "-e", "HEAD:#{LOCK_FILENAME}"],
        chdir: @path
      ).success?
    rescue
      false
    end

    private def unpinned_reason(requirement : Requirement) : String?
      case requirement
      when GitBranchRef
        "branch #{requirement.to_s.sub(/^branch /, "").inspect}"
      when GitTagRef, GitCommitRef
        nil
      when Any
        "no version/tag/commit"
      when Version
        nil
      when VersionReq
        return "version range #{requirement.to_s.inspect}" unless exact_version?(requirement)
        nil
      end
    end

    private def exact_version_reason(requirement : Requirement) : String?
      case requirement
      when Version
        requirement.value.inspect
      when VersionReq
        requirement.patterns.first?.try(&.strip).try(&.inspect) if exact_version?(requirement)
      else
        nil
      end
    end

    private def exact_version?(requirement : VersionReq) : Bool
      requirement.patterns.size == 1 && EXACT_VERSION.matches?(requirement.patterns.first)
    end
  end
end
