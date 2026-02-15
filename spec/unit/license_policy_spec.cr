require "./spec_helper"
require "../../src/spdx"
require "../../src/license_scanner"
require "../../src/license_policy"

module Shards
  describe LicensePolicy do
    describe ".load_policy" do
      it "returns nil when file doesn't exist" do
        result = LicensePolicy.load_policy("/nonexistent/path/to/policy.yml")
        result.should be_nil
      end

      it "loads valid policy with allowed licenses" do
        Dir.cd(tmp_path) do
          File.write("test-policy.yml", <<-YAML)
          policy:
            allowed:
              - MIT
              - Apache-2.0
              - BSD-3-Clause
            denied: []
            require_license: false
          YAML

          policy = LicensePolicy.load_policy("test-policy.yml")
          policy.should_not be_nil
          policy = policy.not_nil!
          policy.allowed.should eq(Set{"MIT", "Apache-2.0", "BSD-3-Clause"})
          policy.denied.empty?.should be_true
          policy.require_license.should be_false
        end
      end

      it "loads valid policy with denied licenses" do
        Dir.cd(tmp_path) do
          File.write("test-policy-denied.yml", <<-YAML)
          policy:
            allowed:
              - MIT
            denied:
              - GPL-3.0-only
              - AGPL-3.0-only
            require_license: false
          YAML

          policy = LicensePolicy.load_policy("test-policy-denied.yml")
          policy.should_not be_nil
          policy = policy.not_nil!
          policy.denied.should eq(Set{"GPL-3.0-only", "AGPL-3.0-only"})
        end
      end

      it "loads policy with overrides" do
        Dir.cd(tmp_path) do
          File.write("test-policy-overrides.yml", <<-YAML)
          policy:
            allowed:
              - MIT
            denied: []
            require_license: false
            overrides:
              some_shard:
                license: MIT
                reason: "Confirmed with author via email"
              another_shard:
                license: Apache-2.0
          YAML

          policy = LicensePolicy.load_policy("test-policy-overrides.yml")
          policy.should_not be_nil
          policy = policy.not_nil!
          policy.overrides.size.should eq(2)
          policy.overrides["some_shard"].license.should eq("MIT")
          policy.overrides["some_shard"].reason.should eq("Confirmed with author via email")
          policy.overrides["another_shard"].license.should eq("Apache-2.0")
          policy.overrides["another_shard"].reason.should be_nil
        end
      end

      it "loads policy with require_license flag" do
        Dir.cd(tmp_path) do
          File.write("test-policy-require.yml", <<-YAML)
          policy:
            allowed:
              - MIT
            denied: []
            require_license: true
          YAML

          policy = LicensePolicy.load_policy("test-policy-require.yml")
          policy.should_not be_nil
          policy = policy.not_nil!
          policy.require_license.should be_true
        end
      end

      it "returns nil when file exists but has no policy key" do
        Dir.cd(tmp_path) do
          File.write("test-policy-empty.yml", <<-YAML)
          something_else:
            key: value
          YAML

          result = LicensePolicy.load_policy("test-policy-empty.yml")
          result.should be_nil
        end
      end
    end

    describe ".evaluate_against_policy" do
      it "returns Allowed for an allowed license" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT", "Apache-2.0"},
          denied: Set(String).new,
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        verdict = LicensePolicy.evaluate_against_policy("MIT", policy)
        verdict.should eq(LicensePolicy::Verdict::Allowed)
      end

      it "returns Denied for a denied license" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT"},
          denied: Set{"GPL-3.0-only"},
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        verdict = LicensePolicy.evaluate_against_policy("GPL-3.0-only", policy)
        verdict.should eq(LicensePolicy::Verdict::Denied)
      end

      it "returns Unknown for license not in allowed or denied" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT"},
          denied: Set{"GPL-3.0-only"},
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        verdict = LicensePolicy.evaluate_against_policy("Apache-2.0", policy)
        verdict.should eq(LicensePolicy::Verdict::Unknown)
      end

      it "denied takes priority over compound expression" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT"},
          denied: Set{"GPL-3.0-only"},
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        # Even though MIT is allowed, GPL-3.0-only is denied
        verdict = LicensePolicy.evaluate_against_policy("MIT OR GPL-3.0-only", policy)
        verdict.should eq(LicensePolicy::Verdict::Denied)
      end

      it "OR expression returns Allowed if either side is allowed" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT", "Apache-2.0"},
          denied: Set(String).new,
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        verdict = LicensePolicy.evaluate_against_policy("MIT OR BSD-3-Clause", policy)
        verdict.should eq(LicensePolicy::Verdict::Allowed)
      end

      it "AND expression requires both sides allowed" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT", "Apache-2.0"},
          denied: Set(String).new,
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )

        # Both allowed
        verdict = LicensePolicy.evaluate_against_policy("MIT AND Apache-2.0", policy)
        verdict.should eq(LicensePolicy::Verdict::Allowed)

        # Only one allowed
        verdict = LicensePolicy.evaluate_against_policy("MIT AND BSD-3-Clause", policy)
        verdict.should eq(LicensePolicy::Verdict::Unknown)
      end

      it "returns Unlicensed for nil license" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT"},
          denied: Set(String).new,
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        verdict = LicensePolicy.evaluate_against_policy(nil, policy)
        verdict.should eq(LicensePolicy::Verdict::Unlicensed)
      end

      it "returns Unlicensed for empty license string" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"MIT"},
          denied: Set(String).new,
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        verdict = LicensePolicy.evaluate_against_policy("", policy)
        verdict.should eq(LicensePolicy::Verdict::Unlicensed)
      end

      it "returns Unknown for nil license with no policy" do
        verdict = LicensePolicy.evaluate_against_policy(nil, nil)
        verdict.should eq(LicensePolicy::Verdict::Unlicensed)
      end

      it "returns Unknown when no policy is provided for a valid license" do
        verdict = LicensePolicy.evaluate_against_policy("MIT", nil)
        verdict.should eq(LicensePolicy::Verdict::Unknown)
      end

      it "handles non-SPDX license strings with simple matching" do
        policy = LicensePolicy::PolicyConfig.new(
          allowed: Set{"CustomLicense-1.0"},
          denied: Set(String).new,
          require_license: false,
          overrides: Hash(String, LicensePolicy::Override).new
        )
        verdict = LicensePolicy.evaluate_against_policy("CustomLicense-1.0", policy)
        verdict.should eq(LicensePolicy::Verdict::Allowed)
      end
    end

    describe ".compute_summary" do
      it "counts each verdict type correctly" do
        results = [
          LicensePolicy::DependencyResult.new(
            name: "pkg1", version: "1.0.0",
            declared_license: "MIT", detected_license: nil,
            effective_license: "MIT", license_source: :declared,
            verdict: LicensePolicy::Verdict::Allowed, override_reason: nil,
            spdx_valid: true, category: SPDX::Category::Permissive,
            scan_result: nil
          ),
          LicensePolicy::DependencyResult.new(
            name: "pkg2", version: "2.0.0",
            declared_license: "GPL-3.0-only", detected_license: nil,
            effective_license: "GPL-3.0-only", license_source: :declared,
            verdict: LicensePolicy::Verdict::Denied, override_reason: nil,
            spdx_valid: true, category: SPDX::Category::StrongCopyleft,
            scan_result: nil
          ),
          LicensePolicy::DependencyResult.new(
            name: "pkg3", version: "3.0.0",
            declared_license: nil, detected_license: nil,
            effective_license: nil, license_source: :none,
            verdict: LicensePolicy::Verdict::Unlicensed, override_reason: nil,
            spdx_valid: false, category: SPDX::Category::Unknown,
            scan_result: nil
          ),
          LicensePolicy::DependencyResult.new(
            name: "pkg4", version: "4.0.0",
            declared_license: "BSL-1.1", detected_license: nil,
            effective_license: "BSL-1.1", license_source: :declared,
            verdict: LicensePolicy::Verdict::Unknown, override_reason: nil,
            spdx_valid: true, category: SPDX::Category::Proprietary,
            scan_result: nil
          ),
          LicensePolicy::DependencyResult.new(
            name: "pkg5", version: "5.0.0",
            declared_license: nil, detected_license: nil,
            effective_license: "MIT", license_source: :override,
            verdict: LicensePolicy::Verdict::Overridden, override_reason: "Manual review",
            spdx_valid: true, category: SPDX::Category::Permissive,
            scan_result: nil
          ),
          LicensePolicy::DependencyResult.new(
            name: "pkg6", version: "6.0.0",
            declared_license: "Apache-2.0", detected_license: nil,
            effective_license: "Apache-2.0", license_source: :declared,
            verdict: LicensePolicy::Verdict::Allowed, override_reason: nil,
            spdx_valid: true, category: SPDX::Category::Permissive,
            scan_result: nil
          ),
        ]

        summary = LicensePolicy.compute_summary(results)
        summary.total.should eq(6)
        summary.allowed.should eq(2)
        summary.denied.should eq(1)
        summary.unlicensed.should eq(1)
        summary.unknown.should eq(1)
        summary.overridden.should eq(1)
      end

      it "handles empty results" do
        summary = LicensePolicy.compute_summary([] of LicensePolicy::DependencyResult)
        summary.total.should eq(0)
        summary.allowed.should eq(0)
        summary.denied.should eq(0)
        summary.unlicensed.should eq(0)
        summary.unknown.should eq(0)
        summary.overridden.should eq(0)
      end
    end
  end
end
