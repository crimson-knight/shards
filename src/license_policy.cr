require "yaml"
require "./spdx"
require "./license_scanner"

module Shards
  class LicensePolicy
    DEFAULT_POLICY_FILENAME = ".shards-license-policy.yml"

    record PolicyConfig,
      allowed : Set(String),
      denied : Set(String),
      require_license : Bool,
      overrides : Hash(String, Override)

    record Override,
      license : String,
      reason : String?

    enum Verdict
      Allowed
      Denied
      Unlicensed
      Unknown
      Overridden
    end

    record DependencyResult,
      name : String,
      version : String,
      declared_license : String?,
      detected_license : String?,
      effective_license : String?,
      license_source : Symbol,
      verdict : Verdict,
      override_reason : String?,
      spdx_valid : Bool,
      category : SPDX::Category,
      scan_result : LicenseScanner::ScanResult?

    record PolicyReport,
      root_name : String,
      root_version : String,
      root_license : String?,
      dependencies : Array(DependencyResult),
      policy_used : Bool,
      summary : Summary

    record Summary,
      total : Int32,
      allowed : Int32,
      denied : Int32,
      unlicensed : Int32,
      unknown : Int32,
      overridden : Int32

    def self.load_policy(path : String?) : PolicyConfig?
      actual_path = path || DEFAULT_POLICY_FILENAME
      return nil unless File.exists?(actual_path)
      yaml = YAML.parse(File.read(actual_path))
      policy = yaml["policy"]?
      return nil unless policy

      allowed = Set(String).new
      if allowed_list = policy["allowed"]?
        if arr = allowed_list.as_a?
          arr.each do |item|
            if s = item.as_s?
              allowed << s
            end
          end
        end
      end

      denied = Set(String).new
      if denied_list = policy["denied"]?
        if arr = denied_list.as_a?
          arr.each do |item|
            if s = item.as_s?
              denied << s
            end
          end
        end
      end

      require_license = false
      if req = policy["require_license"]?
        if b = req.as_bool?
          require_license = b
        end
      end

      overrides = Hash(String, Override).new
      if overrides_map = policy["overrides"]?
        if h = overrides_map.as_h?
          h.each do |key, value|
            name = key.as_s
            license = ""
            reason : String? = nil
            if vh = value.as_h?
              if l = vh["license"]?
                license = l.as_s? || ""
              end
              if r = vh["reason"]?
                reason = r.as_s?
              end
            end
            overrides[name] = Override.new(license: license, reason: reason)
          end
        end
      end

      PolicyConfig.new(
        allowed: allowed,
        denied: denied,
        require_license: require_license,
        overrides: overrides
      )
    end

    def self.evaluate(
      packages : Array(Package),
      root_spec : Spec,
      policy : PolicyConfig?,
      detect : Bool = false,
    ) : PolicyReport
      results = packages.map { |pkg| evaluate_package(pkg, policy, detect) }
      summary = compute_summary(results)
      PolicyReport.new(
        root_name: root_spec.name,
        root_version: root_spec.version.to_s,
        root_license: root_spec.license,
        dependencies: results,
        policy_used: !policy.nil?,
        summary: summary
      )
    end

    def self.evaluate_against_policy(license : String?, policy : PolicyConfig?) : Verdict
      return Verdict::Unlicensed if license.nil? || license.empty?
      return Verdict::Unknown if policy.nil?

      # Try to parse as SPDX expression
      begin
        expr = SPDX::Parser.parse(license)

        # Check denied list first - if any license ID in the expression is denied
        ids = expr.license_ids
        ids.each do |id|
          return Verdict::Denied if policy.denied.includes?(id)
        end

        # Check if expression is satisfied by the allowed set
        if expr.satisfied_by?(policy.allowed)
          return Verdict::Allowed
        end

        # Expression parsed but not fully satisfied by allowed set
        return Verdict::Unknown
      rescue Shards::Error
        # Could not parse as SPDX, fall back to simple string matching
      end

      # Simple string check for unparseable license strings
      return Verdict::Denied if policy.denied.includes?(license)
      return Verdict::Allowed if policy.allowed.includes?(license)
      Verdict::Unknown
    end

    private def self.evaluate_package(pkg, policy, detect) : DependencyResult
      # 1. Get declared license from pkg.spec.license
      declared_license = pkg.spec.license

      # 2. Check for policy override
      override = policy.try(&.overrides[pkg.name]?)
      override_reason : String? = nil

      # 3. Optionally scan for LICENSE file
      scan_result : LicenseScanner::ScanResult? = nil
      detected_license : String? = nil
      if detect && pkg.installed?
        scan_result = LicenseScanner.scan(pkg.install_path)
        detected_license = scan_result.detected_license
      end

      # 4. Determine effective license and source
      if override
        effective_license = override.license
        source = :override
        override_reason = override.reason
      elsif declared_license && !declared_license.empty?
        effective_license = declared_license
        source = :declared
      elsif detected_license && !detected_license.empty?
        effective_license = detected_license
        source = :detected
      else
        effective_license = nil
        source = :none
      end

      # 5. Determine verdict
      if override
        verdict = Verdict::Overridden
      elsif effective_license.nil? || effective_license.empty?
        if policy && policy.require_license
          verdict = Verdict::Denied
        else
          verdict = Verdict::Unlicensed
        end
      else
        verdict = evaluate_against_policy(effective_license, policy)
      end

      # 6. Check SPDX validity
      spdx_valid = false
      if eff = effective_license
        begin
          expr = SPDX::Parser.parse(eff)
          spdx_valid = expr.license_ids.all? { |id| SPDX.valid_id?(id) }
        rescue Shards::Error
          spdx_valid = false
        end
      end

      # 7. Get category
      category = if eff = effective_license
                   SPDX.category_for(eff)
                 else
                   SPDX::Category::Unknown
                 end

      # 8. Build DependencyResult
      DependencyResult.new(
        name: pkg.name,
        version: pkg.version.to_s,
        declared_license: declared_license,
        detected_license: detected_license,
        effective_license: effective_license,
        license_source: source,
        verdict: verdict,
        override_reason: override_reason,
        spdx_valid: spdx_valid,
        category: category,
        scan_result: scan_result
      )
    end

    def self.compute_summary(results : Array(DependencyResult)) : Summary
      allowed = 0
      denied = 0
      unlicensed = 0
      unknown = 0
      overridden = 0

      results.each do |r|
        case r.verdict
        when Verdict::Allowed    then allowed += 1
        when Verdict::Denied     then denied += 1
        when Verdict::Unlicensed then unlicensed += 1
        when Verdict::Unknown    then unknown += 1
        when Verdict::Overridden then overridden += 1
        end
      end

      Summary.new(
        total: results.size.to_i32,
        allowed: allowed.to_i32,
        denied: denied.to_i32,
        unlicensed: unlicensed.to_i32,
        unknown: unknown.to_i32,
        overridden: overridden.to_i32
      )
    end
  end
end
