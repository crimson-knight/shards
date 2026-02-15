require "uri"
require "./policy"
require "./policy_report"
require "./package"
require "./versions"
require "./resolvers/resolver"
require "./resolvers/path"

module Shards
  class PolicyChecker
    getter policy : Policy
    getter report : PolicyReport

    def initialize(@policy : Policy)
      @report = PolicyReport.new
    end

    # Main entry point: check all packages against all rules
    def check(packages : Array(Package)) : PolicyReport
      @report = PolicyReport.new

      packages.each do |package|
        check_blocked(package)
        check_sources(package)
        check_minimum_version(package)
        check_security(package)
        check_custom(package)
        check_freshness(package)
      end

      @report
    end

    private def check_blocked(package : Package)
      policy.dependencies.blocked.each do |blocked|
        if package.name == blocked.name
          reason = blocked.reason || "Blocked by policy"
          @report.add_violation(
            package: package.name,
            rule: "blocked_dependency",
            severity: PolicyReport::Severity::Error,
            message: "Dependency '#{package.name}' is blocked: #{reason}"
          )
        end
      end
    end

    private def check_sources(package : Package)
      return if policy.sources.empty?
      resolver = package.resolver

      # Check path dependency denial
      if resolver.is_a?(PathResolver)
        if policy.sources.deny_path_dependencies?
          @report.add_violation(
            package: package.name,
            rule: "deny_path_dependencies",
            severity: PolicyReport::Severity::Error,
            message: "Path dependencies are not allowed by policy: '#{package.name}' (#{resolver.source})"
          )
        end
        return # Path deps don't have hosts/orgs to check
      end

      source = resolver.source
      host = extract_host(source)
      return unless host # Can't determine host, skip

      # Check allowed_hosts (if list is non-empty, it's an allowlist)
      unless policy.sources.allowed_hosts.empty?
        unless policy.sources.allowed_hosts.includes?(host)
          @report.add_violation(
            package: package.name,
            rule: "allowed_hosts",
            severity: PolicyReport::Severity::Error,
            message: "Source host '#{host}' is not in the allowed hosts list for '#{package.name}'"
          )
          return # No point checking org if host is blocked
        end
      end

      # Check allowed_orgs (if defined for this host)
      if orgs = policy.sources.allowed_orgs[host]?
        owner = extract_owner(source)
        if owner && !orgs.includes?(owner)
          @report.add_violation(
            package: package.name,
            rule: "allowed_orgs",
            severity: PolicyReport::Severity::Error,
            message: "Organization '#{owner}' on '#{host}' is not in the allowed orgs list for '#{package.name}'"
          )
        end
      end
    end

    private def check_minimum_version(package : Package)
      if min_pattern = policy.dependencies.minimum_versions[package.name]?
        req = VersionReq.new(min_pattern)
        unless Versions.matches?(package.version, req)
          @report.add_violation(
            package: package.name,
            rule: "minimum_version",
            severity: PolicyReport::Severity::Error,
            message: "Version #{package.version} of '#{package.name}' does not satisfy minimum version requirement '#{min_pattern}'"
          )
        end
      end
    end

    private def check_security(package : Package)
      sec = policy.security

      if sec.require_license?
        begin
          license = package.spec.license
          if license.nil? || license.empty?
            @report.add_violation(
              package: package.name,
              rule: "require_license",
              severity: PolicyReport::Severity::Warning,
              message: "Dependency '#{package.name}' has no license declared"
            )
          end
        rescue
          # Skip if spec can't be loaded
        end
      end

      if sec.block_postinstall?
        begin
          if package.spec.scripts["postinstall"]?
            @report.add_violation(
              package: package.name,
              rule: "block_postinstall",
              severity: PolicyReport::Severity::Error,
              message: "Dependency '#{package.name}' has a postinstall script, which is blocked by policy"
            )
          end
        rescue
          # Skip if spec can't be loaded
        end
      elsif sec.audit_postinstall?
        begin
          if command = package.spec.scripts["postinstall"]?
            @report.add_violation(
              package: package.name,
              rule: "audit_postinstall",
              severity: PolicyReport::Severity::Warning,
              message: "Dependency '#{package.name}' has a postinstall script that should be reviewed: #{command}"
            )
          end
        rescue
          # Skip if spec can't be loaded
        end
      end
    end

    private def check_freshness(package : Package)
      # Freshness checks are inherently warnings because shards
      # doesn't track release dates. These checks are best-effort
      # based on available metadata. For now, these generate
      # informational warnings that can be acted upon externally.
      # Full freshness checking would require querying the
      # resolver for tag dates, which is expensive. Mark as TODO
      # for Phase 2 with caching.
    end

    private def check_custom(package : Package)
      policy.custom.each do |rule|
        if rule.pattern.matches?(package.name)
          severity = rule.action == :block ? PolicyReport::Severity::Error : PolicyReport::Severity::Warning
          reason = rule.reason || "Matched custom rule '#{rule.name}'"
          @report.add_violation(
            package: package.name,
            rule: "custom:#{rule.name}",
            severity: severity,
            message: "Dependency '#{package.name}' matched custom rule '#{rule.name}': #{reason}"
          )
        end
      end
    end

    # --- Host/owner extraction helpers ---

    private def extract_host(source : String) : String?
      URI.parse(source).host.try(&.downcase)
    rescue
      nil
    end

    private def extract_owner(source : String) : String?
      uri = URI.parse(source)
      path = uri.path
      return nil unless path
      path = path.lchop('/')
      path = path.rchop(".git") if path.ends_with?(".git")
      parts = path.split('/')
      parts.first? if parts.size >= 2
    rescue
      nil
    end
  end
end
