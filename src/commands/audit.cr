require "./command"
require "../vulnerability_scanner"
require "../vulnerability_report"
require "../purl"
require "digest/sha256"

module Shards
  module Commands
    class Audit < Command
      IGNORE_FILENAME = ".shards-audit-ignore"

      def run(
        format : String = "terminal",
        severity : String? = nil,
        ignore_ids : Array(String) = [] of String,
        ignore_file : String? = nil,
        fail_above : String? = nil,
        offline : Bool = false,
        update_db : Bool = false,
      )
        # Validate format
        unless format.in?("terminal", "json", "sarif")
          raise Error.new("Unknown audit format: #{format}. Use 'terminal', 'json', or 'sarif'.")
        end

        # Parse severity filter
        min_severity = if sev = severity
                         Severity.parse(sev)
                       else
                         Severity::Unknown
                       end

        # Parse fail threshold
        fail_threshold = if fa = fail_above
                           Severity.parse(fa)
                         else
                           Severity::Low # Default: fail on any vuln
                         end

        # Load packages from lockfile
        packages = locks.shards

        if packages.empty?
          Log.info { "No dependencies to audit." }
          return
        end

        Log.info { "Auditing #{packages.size} package(s) for vulnerabilities..." }

        # Create scanner
        scanner = VulnerabilityScanner.new(path, offline: offline)

        # Force cache refresh if requested
        if update_db
          scanner.update_cache(packages)
        else
          scanner.scan(packages)
        end

        results = scanner.results

        # Load ignore rules
        ignore_rules = load_ignore_rules(ignore_ids, ignore_file)

        # Build report
        report = VulnerabilityReport.new(
          results,
          ignore_rules: ignore_rules,
          min_severity: min_severity,
          fail_above: fail_threshold
        )

        # Output
        case format
        when "terminal"
          report.to_terminal
        when "json"
          report.to_json(STDOUT)
          puts # trailing newline
        when "sarif"
          report.to_sarif(STDOUT)
          puts
        end

        # Exit with appropriate code
        code = report.exit_code
        exit(code) if code != 0
      end

      private def load_ignore_rules(cli_ids : Array(String), ignore_file_path : String?) : Array(IgnoreRule)
        rules = [] of IgnoreRule

        # CLI --ignore flag
        cli_ids.each do |id|
          rules << IgnoreRule.new(id, reason: "Ignored via CLI flag")
        end

        # Ignore file (explicit path or default)
        file_path = ignore_file_path || File.join(path, IGNORE_FILENAME)
        rules.concat(VulnerabilityScanner.load_ignore_rules(file_path))

        rules
      end
    end
  end
end
