require "./command"
require "../policy"
require "../policy_checker"
require "../policy_report"

module Shards
  module Commands
    class Policy < Command
      @policy_path : String?
      @strict : Bool = false
      @format : String = "terminal"

      def run(args : Array(String))
        remaining = [] of String
        args.each do |arg|
          case arg
          when .starts_with?("--policy=") then @policy_path = arg.split("=", 2).last
          when "--strict"                 then @strict = true
          when .starts_with?("--format=") then @format = arg.split("=", 2).last
          else                                 remaining << arg unless arg.starts_with?("--")
          end
        end

        subcommand = remaining[0]? || "check"

        case subcommand
        when "check" then run_check
        when "init"  then run_init
        when "show"  then run_show
        else
          raise Error.new("Unknown policy subcommand: #{subcommand}. Use: check, init, show")
        end
      end

      private def policy_file_path : String
        @policy_path || File.join(path, POLICY_FILENAME)
      end

      private def load_policy : ::Shards::Policy
        ppath = policy_file_path
        unless File.exists?(ppath)
          raise Error.new("No policy file found at #{ppath}. Run 'shards policy init' to create one.")
        end
        ::Shards::Policy.from_file(ppath)
      end

      private def run_check
        policy = load_policy
        checker = PolicyChecker.new(policy)
        packages = locks.shards
        report = checker.check(packages)
        output_report(report)
        code = report.exit_code(strict: @strict)
        exit code unless code == 0
      end

      private def run_init
        target = policy_file_path
        if File.exists?(target)
          raise Error.new("Policy file already exists: #{target}")
        end
        File.write(target, DEFAULT_POLICY_TEMPLATE)
        Log.info { "Created #{target}" }
      end

      private def run_show
        policy = load_policy
        puts "Policy: #{policy_file_path}"
        puts "Version: #{policy.version}"
        puts ""
        puts "Source rules:"
        puts "  Allowed hosts: #{policy.sources.allowed_hosts.empty? ? "(any)" : policy.sources.allowed_hosts.join(", ")}"
        puts "  Deny path dependencies: #{policy.sources.deny_path_dependencies?}"
        puts ""
        puts "Dependency rules:"
        puts "  Blocked: #{policy.dependencies.blocked.empty? ? "(none)" : policy.dependencies.blocked.map(&.name).join(", ")}"
        puts "  Minimum versions: #{policy.dependencies.minimum_versions.empty? ? "(none)" : policy.dependencies.minimum_versions.map { |k, v| "#{k} #{v}" }.join(", ")}"
        puts ""
        puts "Security rules:"
        puts "  Require license: #{policy.security.require_license?}"
        puts "  Block postinstall: #{policy.security.block_postinstall?}"
        puts "  Audit postinstall: #{policy.security.audit_postinstall?}"
      end

      private def output_report(report : PolicyReport)
        case @format
        when "json"
          report.to_json_output(STDOUT)
          puts
        else
          report.to_terminal(STDOUT)
        end
      end

      DEFAULT_POLICY_TEMPLATE = <<-YAML
      version: 1

      rules:
        sources:
          allowed_hosts: []
          deny_path_dependencies: false

        dependencies:
          blocked: []
          minimum_versions: {}

        security:
          require_license: false
          block_postinstall: false
          audit_postinstall: false
      YAML
    end
  end
end
