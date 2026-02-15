require "./ext/yaml"
require "./config"
require "./errors"

module Shards
  class Policy
    CURRENT_VERSION = "1"

    getter version : String
    getter sources : SourceRules
    getter dependencies : DependencyRules
    getter freshness : FreshnessRules
    getter security : SecurityRules
    getter custom : Array(CustomRule)

    def initialize(
      @version = CURRENT_VERSION,
      @sources = SourceRules.new,
      @dependencies = DependencyRules.new,
      @freshness = FreshnessRules.new,
      @security = SecurityRules.new,
      @custom = [] of CustomRule,
    )
    end

    # --- Nested data structures ---

    class SourceRules
      getter allowed_hosts : Array(String)
      getter allowed_orgs : Hash(String, Array(String))
      getter? deny_path_dependencies : Bool

      def initialize(
        @allowed_hosts = [] of String,
        @allowed_orgs = {} of String => Array(String),
        @deny_path_dependencies = false,
      )
      end

      def empty?
        allowed_hosts.empty? && allowed_orgs.empty? && !deny_path_dependencies?
      end
    end

    class DependencyRules
      getter blocked : Array(BlockedDep)
      getter minimum_versions : Hash(String, String)

      def initialize(
        @blocked = [] of BlockedDep,
        @minimum_versions = {} of String => String,
      )
      end
    end

    class BlockedDep
      getter name : String
      getter reason : String?

      def initialize(@name, @reason = nil)
      end
    end

    class FreshnessRules
      getter max_age_days : Int32?
      getter require_recent_commit : Int32?

      def initialize(
        @max_age_days = nil,
        @require_recent_commit = nil,
      )
      end
    end

    class SecurityRules
      getter? require_license : Bool
      getter? require_checksum : Bool
      getter? block_postinstall : Bool
      getter? audit_postinstall : Bool

      def initialize(
        @require_license = false,
        @require_checksum = false,
        @block_postinstall = false,
        @audit_postinstall = false,
      )
      end
    end

    class CustomRule
      getter name : String
      getter pattern : Regex
      getter action : Symbol # :warn or :block
      getter reason : String?

      def initialize(@name, pattern_str : String, action_str : String, @reason = nil)
        @pattern = Regex.new(pattern_str, Regex::Options::IGNORE_CASE)
        @action = action_str == "block" ? :block : :warn
      end
    end

    # --- Parsing (mirrors Override.from_file / Override.from_yaml) ---

    def self.from_file(path : String) : self
      raise Error.new("Missing #{File.basename(path)}") unless File.exists?(path)
      from_yaml(File.read(path), path)
    end

    def self.from_yaml(input : String, filename = POLICY_FILENAME) : self
      parser = YAML::PullParser.new(input)
      parser.read_stream do
        if parser.kind.stream_end?
          return new
        end
        parser.read_document do
          new(parser)
        end
      end
    rescue ex : YAML::ParseException
      raise ParseError.new(ex.message, input, filename, ex.line_number, ex.column_number)
    ensure
      parser.close if parser
    end

    def initialize(pull : YAML::PullParser)
      @version = CURRENT_VERSION
      @sources = SourceRules.new
      @dependencies = DependencyRules.new
      @freshness = FreshnessRules.new
      @security = SecurityRules.new
      @custom = [] of CustomRule

      pull.each_in_mapping do
        case pull.read_scalar
        when "version"
          @version = pull.read_scalar
        when "rules"
          parse_rules(pull)
        else
          pull.skip
        end
      end
    end

    private def parse_rules(pull)
      pull.each_in_mapping do
        case pull.read_scalar
        when "sources"      then @sources = parse_sources(pull)
        when "dependencies" then @dependencies = parse_dependencies(pull)
        when "freshness"    then @freshness = parse_freshness(pull)
        when "security"     then @security = parse_security(pull)
        when "custom"       then @custom = parse_custom(pull)
        else                     pull.skip
        end
      end
    end

    private def parse_sources(pull) : SourceRules
      allowed_hosts = [] of String
      allowed_orgs = {} of String => Array(String)
      deny_path_dependencies = false

      pull.each_in_mapping do
        case pull.read_scalar
        when "allowed_hosts"
          pull.each_in_sequence do
            allowed_hosts << pull.read_scalar
          end
        when "allowed_orgs"
          pull.each_in_mapping do
            host = pull.read_scalar
            orgs = [] of String
            pull.each_in_sequence do
              orgs << pull.read_scalar
            end
            allowed_orgs[host] = orgs
          end
        when "deny_path_dependencies"
          deny_path_dependencies = pull.read_scalar == "true"
        else
          pull.skip
        end
      end

      SourceRules.new(allowed_hosts, allowed_orgs, deny_path_dependencies)
    end

    private def parse_dependencies(pull) : DependencyRules
      blocked = [] of BlockedDep
      minimum_versions = {} of String => String

      pull.each_in_mapping do
        case pull.read_scalar
        when "blocked"
          pull.each_in_sequence do
            name = ""
            reason = nil
            pull.each_in_mapping do
              case pull.read_scalar
              when "name"   then name = pull.read_scalar
              when "reason" then reason = pull.read_scalar
              else               pull.skip
              end
            end
            blocked << BlockedDep.new(name, reason) unless name.empty?
          end
        when "minimum_versions"
          pull.each_in_mapping do
            dep_name = pull.read_scalar
            version_req = pull.read_scalar
            minimum_versions[dep_name] = version_req
          end
        else
          pull.skip
        end
      end

      DependencyRules.new(blocked, minimum_versions)
    end

    private def parse_freshness(pull) : FreshnessRules
      max_age_days = nil
      require_recent_commit = nil

      pull.each_in_mapping do
        case pull.read_scalar
        when "max_age_days"          then max_age_days = pull.read_scalar.to_i?
        when "require_recent_commit" then require_recent_commit = pull.read_scalar.to_i?
        else                              pull.skip
        end
      end

      FreshnessRules.new(max_age_days, require_recent_commit)
    end

    private def parse_security(pull) : SecurityRules
      require_license = false
      require_checksum = false
      block_postinstall = false
      audit_postinstall = false

      pull.each_in_mapping do
        case pull.read_scalar
        when "require_license"   then require_license = pull.read_scalar == "true"
        when "require_checksum"  then require_checksum = pull.read_scalar == "true"
        when "block_postinstall" then block_postinstall = pull.read_scalar == "true"
        when "audit_postinstall" then audit_postinstall = pull.read_scalar == "true"
        else                          pull.skip
        end
      end

      SecurityRules.new(require_license, require_checksum, block_postinstall, audit_postinstall)
    end

    private def parse_custom(pull) : Array(CustomRule)
      rules = [] of CustomRule

      pull.each_in_sequence do
        name = ""
        pattern_str = ""
        action_str = "warn"
        reason = nil

        pull.each_in_mapping do
          case pull.read_scalar
          when "name"    then name = pull.read_scalar
          when "pattern" then pattern_str = pull.read_scalar
          when "action"  then action_str = pull.read_scalar
          when "reason"  then reason = pull.read_scalar
          else                pull.skip
          end
        end

        rules << CustomRule.new(name, pattern_str, action_str, reason) unless name.empty? || pattern_str.empty?
      end

      rules
    end
  end
end
