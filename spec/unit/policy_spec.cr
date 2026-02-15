require "./spec_helper"
require "../../src/policy"

module Shards
  describe Policy do
    it "parses a complete policy file" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      rules:
        sources:
          allowed_hosts:
            - github.com
            - gitlab.com
          allowed_orgs:
            github.com:
              - crystal-lang
              - my-company
          deny_path_dependencies: true
        dependencies:
          blocked:
            - name: malicious_shard
              reason: "Known supply chain compromise"
          minimum_versions:
            some_shard: ">= 2.0.0"
        freshness:
          max_age_days: 365
          require_recent_commit: 180
        security:
          require_license: true
          require_checksum: false
          block_postinstall: false
          audit_postinstall: true
        custom:
          - name: "no-crypto"
            pattern: "crypto|cipher"
            action: warn
            reason: "Needs review"
      YAML

      policy.version.should eq("1")

      # Sources
      policy.sources.allowed_hosts.should eq(["github.com", "gitlab.com"])
      policy.sources.allowed_orgs["github.com"].should eq(["crystal-lang", "my-company"])
      policy.sources.deny_path_dependencies?.should be_true
      policy.sources.empty?.should be_false

      # Dependencies
      policy.dependencies.blocked.size.should eq(1)
      policy.dependencies.blocked[0].name.should eq("malicious_shard")
      policy.dependencies.blocked[0].reason.should eq("Known supply chain compromise")
      policy.dependencies.minimum_versions["some_shard"].should eq(">= 2.0.0")

      # Freshness
      policy.freshness.max_age_days.should eq(365)
      policy.freshness.require_recent_commit.should eq(180)

      # Security
      policy.security.require_license?.should be_true
      policy.security.require_checksum?.should be_false
      policy.security.block_postinstall?.should be_false
      policy.security.audit_postinstall?.should be_true

      # Custom
      policy.custom.size.should eq(1)
      policy.custom[0].name.should eq("no-crypto")
      policy.custom[0].pattern.source.should eq("crypto|cipher")
      policy.custom[0].action.should eq(:warn)
      policy.custom[0].reason.should eq("Needs review")
    end

    it "parses empty policy (version only)" do
      policy = Policy.from_yaml("version: 1\n")
      policy.version.should eq("1")
      policy.sources.empty?.should be_true
      policy.sources.allowed_hosts.should be_empty
      policy.sources.allowed_orgs.should be_empty
      policy.sources.deny_path_dependencies?.should be_false
      policy.dependencies.blocked.should be_empty
      policy.dependencies.minimum_versions.should be_empty
      policy.freshness.max_age_days.should be_nil
      policy.freshness.require_recent_commit.should be_nil
      policy.security.require_license?.should be_false
      policy.security.require_checksum?.should be_false
      policy.security.block_postinstall?.should be_false
      policy.security.audit_postinstall?.should be_false
      policy.custom.should be_empty
    end

    it "parses minimal sources" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      rules:
        sources:
          allowed_hosts:
            - github.com
      YAML
      policy.sources.allowed_hosts.should eq(["github.com"])
      policy.sources.deny_path_dependencies?.should be_false
      policy.sources.allowed_orgs.should be_empty
    end

    it "skips unknown attributes gracefully" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      unknown_key: test
      rules:
        sources:
          allowed_hosts:
            - github.com
          unknown_field: value
        unknown_section:
          foo: bar
      YAML
      policy.sources.allowed_hosts.should eq(["github.com"])
      policy.version.should eq("1")
    end

    it "defaults to empty collections when sections missing" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      rules:
        security:
          require_license: true
      YAML
      policy.sources.empty?.should be_true
      policy.dependencies.blocked.should be_empty
      policy.dependencies.minimum_versions.should be_empty
      policy.freshness.max_age_days.should be_nil
      policy.custom.should be_empty
      policy.security.require_license?.should be_true
    end

    it "parses custom rule with block action" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      rules:
        custom:
          - name: "no-unsafe"
            pattern: "unsafe"
            action: block
            reason: "Unsafe packages not allowed"
      YAML
      policy.custom.size.should eq(1)
      policy.custom[0].action.should eq(:block)
      policy.custom[0].reason.should eq("Unsafe packages not allowed")
    end

    it "parses multiple blocked dependencies" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      rules:
        dependencies:
          blocked:
            - name: bad_dep1
              reason: "First bad dep"
            - name: bad_dep2
              reason: "Second bad dep"
      YAML
      policy.dependencies.blocked.size.should eq(2)
      policy.dependencies.blocked[0].name.should eq("bad_dep1")
      policy.dependencies.blocked[1].name.should eq("bad_dep2")
    end

    it "parses blocked dependency without reason" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      rules:
        dependencies:
          blocked:
            - name: bad_dep
      YAML
      policy.dependencies.blocked.size.should eq(1)
      policy.dependencies.blocked[0].name.should eq("bad_dep")
      policy.dependencies.blocked[0].reason.should be_nil
    end
  end
end
