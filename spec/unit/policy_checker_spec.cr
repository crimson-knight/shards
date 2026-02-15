require "./spec_helper"
require "../../src/policy"
require "../../src/policy_checker"
require "../../src/policy_report"

module Shards
  describe PolicyChecker do
    describe "#check_blocked" do
      it "flags blocked dependencies" do
        create_git_repository "blocked_dep", "1.0.0"
        resolver = GitResolver.new("blocked_dep", git_url(:blocked_dep))
        package = Package.new("blocked_dep", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          dependencies:
            blocked:
              - name: blocked_dep
                reason: "Known bad"
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.has_errors?.should be_true
        report.errors.size.should eq(1)
        report.errors[0].rule.should eq("blocked_dependency")
        report.errors[0].message.should contain("Known bad")
      end

      it "allows non-blocked dependencies" do
        create_git_repository "good_dep", "1.0.0"
        resolver = GitResolver.new("good_dep", git_url(:good_dep))
        package = Package.new("good_dep", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          dependencies:
            blocked:
              - name: other_dep
                reason: "Not this one"
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.errors.should be_empty
      end
    end

    describe "#check_sources" do
      it "flags dependencies from unapproved hosts" do
        create_git_repository "unapproved", "1.0.0"
        resolver = GitResolver.new("unapproved", "https://evil.com/attacker/unapproved.git")
        package = Package.new("unapproved", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          sources:
            allowed_hosts:
              - github.com
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.has_errors?.should be_true
        report.errors[0].rule.should eq("allowed_hosts")
      end

      it "allows dependencies from approved hosts" do
        create_git_repository "approved", "1.0.0"
        resolver = GitResolver.new("approved", "https://github.com/myorg/approved.git")
        package = Package.new("approved", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          sources:
            allowed_hosts:
              - github.com
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.clean?.should be_true
      end

      it "flags path dependencies when denied" do
        create_path_repository "local_dep", "1.0.0"
        resolver = PathResolver.new("local_dep", git_path(:local_dep))
        package = Package.new("local_dep", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          sources:
            deny_path_dependencies: true
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.has_errors?.should be_true
        report.errors[0].rule.should eq("deny_path_dependencies")
      end

      it "allows path dependencies when not denied" do
        create_path_repository "local_ok", "1.0.0"
        resolver = PathResolver.new("local_ok", git_path(:local_ok))
        package = Package.new("local_ok", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          sources:
            deny_path_dependencies: false
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.clean?.should be_true
      end
    end

    describe "#check_minimum_version" do
      it "flags versions below minimum" do
        create_git_repository "old_shard", "1.0.0"
        resolver = GitResolver.new("old_shard", "https://github.com/org/old_shard.git")
        package = Package.new("old_shard", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          dependencies:
            minimum_versions:
              old_shard: ">= 2.0.0"
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.has_errors?.should be_true
        report.errors[0].rule.should eq("minimum_version")
      end

      it "allows versions that meet minimum" do
        create_git_repository "new_shard", "3.0.0"
        resolver = GitResolver.new("new_shard", "https://github.com/org/new_shard.git")
        package = Package.new("new_shard", resolver, Version.new("3.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          dependencies:
            minimum_versions:
              new_shard: ">= 2.0.0"
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.clean?.should be_true
      end
    end

    describe "#check_security" do
      it "require_license flags packages without license info" do
        create_git_repository "no_license", "1.0.0"
        resolver = GitResolver.new("no_license", git_url(:no_license))
        package = Package.new("no_license", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          security:
            require_license: true
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.has_warnings?.should be_true
        report.warnings[0].rule.should eq("require_license")
      end
    end

    describe "#check_custom" do
      it "custom rules match dependency names" do
        create_git_repository "crypto_lib", "1.0.0"
        resolver = GitResolver.new("crypto_lib", "https://github.com/org/crypto_lib.git")
        package = Package.new("crypto_lib", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          custom:
            - name: "no-crypto"
              pattern: "crypto|cipher"
              action: warn
              reason: "Needs security review"
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.has_warnings?.should be_true
        report.warnings[0].rule.should eq("custom:no-crypto")
        report.warnings[0].message.should contain("Needs security review")
      end

      it "custom block rules produce errors" do
        create_git_repository "unsafe_lib", "1.0.0"
        resolver = GitResolver.new("unsafe_lib", "https://github.com/org/unsafe_lib.git")
        package = Package.new("unsafe_lib", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          custom:
            - name: "no-unsafe"
              pattern: "unsafe"
              action: block
              reason: "Not allowed"
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.has_errors?.should be_true
        report.errors[0].rule.should eq("custom:no-unsafe")
      end

      it "custom rules do not match non-matching names" do
        create_git_repository "safe_lib", "1.0.0"
        resolver = GitResolver.new("safe_lib", "https://github.com/org/safe_lib.git")
        package = Package.new("safe_lib", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml <<-YAML
        version: 1
        rules:
          custom:
            - name: "no-crypto"
              pattern: "crypto|cipher"
              action: warn
        YAML

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.clean?.should be_true
      end
    end

    describe "clean report" do
      it "returns clean report when no violations" do
        create_git_repository "clean_dep", "1.0.0"
        resolver = GitResolver.new("clean_dep", "https://github.com/org/clean_dep.git")
        package = Package.new("clean_dep", resolver, Version.new("1.0.0"))

        policy = Policy.from_yaml("version: 1\n")

        checker = PolicyChecker.new(policy)
        report = checker.check([package])
        report.clean?.should be_true
        report.has_errors?.should be_false
        report.has_warnings?.should be_false
        report.exit_code.should eq(0)
      end
    end

    describe "PolicyReport" do
      it "exit_code returns correct values" do
        report = PolicyReport.new
        report.exit_code.should eq(0)

        report.add_violation(
          package: "test",
          rule: "test_rule",
          severity: PolicyReport::Severity::Warning,
          message: "test warning"
        )
        report.exit_code.should eq(2)
        report.exit_code(strict: true).should eq(1)

        report.add_violation(
          package: "test",
          rule: "test_rule",
          severity: PolicyReport::Severity::Error,
          message: "test error"
        )
        report.exit_code.should eq(1)
      end

      it "to_json_output produces valid JSON" do
        report = PolicyReport.new
        report.add_violation(
          package: "my_dep",
          rule: "blocked_dependency",
          severity: PolicyReport::Severity::Error,
          message: "Blocked by policy"
        )

        io = IO::Memory.new
        report.to_json_output(io)
        json = JSON.parse(io.to_s)

        json["violations"].as_a.size.should eq(1)
        json["violations"][0]["package"].as_s.should eq("my_dep")
        json["violations"][0]["severity"].as_s.should eq("error")
        json["summary"]["errors"].as_i.should eq(1)
        json["summary"]["warnings"].as_i.should eq(0)
        json["summary"]["total"].as_i.should eq(1)
      end

      it "to_terminal produces output" do
        report = PolicyReport.new
        report.add_violation(
          package: "test",
          rule: "test_rule",
          severity: PolicyReport::Severity::Error,
          message: "test error"
        )

        io = IO::Memory.new
        report.to_terminal(io, colors: false)
        output = io.to_s
        output.should contain("ERROR")
        output.should contain("test_rule")
        output.should contain("1 error(s)")
      end

      it "to_terminal shows pass message when clean" do
        report = PolicyReport.new
        io = IO::Memory.new
        report.to_terminal(io, colors: false)
        io.to_s.should contain("Policy check passed")
      end
    end
  end
end
