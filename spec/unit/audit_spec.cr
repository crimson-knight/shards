require "./spec_helper"
require "../../src/version"
require "../../src/purl"
require "../../src/vulnerability_scanner"
require "../../src/vulnerability_report"

private def make_vuln(id : String, severity : Shards::Severity, aliases : Array(String) = [] of String) : Shards::Vulnerability
  Shards::Vulnerability.new(
    id: id,
    summary: "Test vulnerability #{id}",
    details: "Details for #{id}",
    severity: severity,
    cvss_score: nil,
    affected_versions: [] of String,
    references: [] of String,
    aliases: aliases,
    published: nil,
    modified: nil
  )
end

module Shards
  describe PurlGenerator do
    describe ".parse_owner_repo" do
      it "parses owner/repo from GitHub HTTPS URL" do
        owner, repo = PurlGenerator.parse_owner_repo("https://github.com/crystal-lang/shards.git")
        owner.should eq("crystal-lang")
        repo.should eq("shards")
      end

      it "parses owner/repo from GitHub HTTPS URL without .git" do
        owner, repo = PurlGenerator.parse_owner_repo("https://github.com/crystal-lang/shards")
        owner.should eq("crystal-lang")
        repo.should eq("shards")
      end

      it "parses owner/repo from GitLab HTTPS URL" do
        owner, repo = PurlGenerator.parse_owner_repo("https://gitlab.com/myorg/mylib.git")
        owner.should eq("myorg")
        repo.should eq("mylib")
      end

      it "parses owner/repo from Bitbucket HTTPS URL" do
        owner, repo = PurlGenerator.parse_owner_repo("https://bitbucket.org/team/project.git")
        owner.should eq("team")
        repo.should eq("project")
      end

      it "returns nil tuple for path with no segments" do
        owner, repo = PurlGenerator.parse_owner_repo("file:///local")
        # Single path segment, not enough for owner/repo
        owner.should be_nil
        repo.should be_nil
      end

      it "returns nil tuple for empty string" do
        owner, repo = PurlGenerator.parse_owner_repo("")
        owner.should be_nil
        repo.should be_nil
      end
    end

    describe ".generate" do
      it "generates purl for a GitHub-hosted shard" do
        create_git_repository "gh_shard", "1.0.0"
        resolver = GitResolver.new("gh_shard", "https://github.com/owner/gh_shard.git")
        pkg = Package.new("gh_shard", resolver, version("1.0.0"))
        purl = PurlGenerator.generate(pkg)
        purl.should eq("pkg:github/owner/gh_shard@1.0.0")
      end

      it "generates purl for a GitLab-hosted shard" do
        create_git_repository "gl_shard", "2.0.0"
        resolver = GitResolver.new("gl_shard", "https://gitlab.com/myorg/gl_shard.git")
        pkg = Package.new("gl_shard", resolver, version("2.0.0"))
        purl = PurlGenerator.generate(pkg)
        purl.should eq("pkg:gitlab/myorg/gl_shard@2.0.0")
      end

      it "returns nil for a PathResolver-based dependency" do
        create_path_repository "local_dep", "0.1.0"
        resolver = PathResolver.new("local_dep", git_path("local_dep"))
        pkg = Package.new("local_dep", resolver, version("0.1.0"))
        purl = PurlGenerator.generate(pkg)
        purl.should be_nil
      end

      it "generates generic purl for non-recognized git hosts" do
        create_git_repository "custom_shard", "3.0.0"
        resolver = GitResolver.new("custom_shard", "https://git.example.com/team/custom_shard.git")
        pkg = Package.new("custom_shard", resolver, version("3.0.0"))
        purl = PurlGenerator.generate(pkg)
        purl.should_not be_nil
        purl.not_nil!.should start_with("pkg:generic/")
        purl.not_nil!.should contain("custom_shard")
        purl.not_nil!.should contain("3.0.0")
      end
    end
  end

  describe Severity do
    describe ".parse" do
      it "parses 'critical' to Critical" do
        Severity.parse("critical").should eq(Severity::Critical)
      end

      it "parses 'high' to High" do
        Severity.parse("high").should eq(Severity::High)
      end

      it "parses 'medium' to Medium" do
        Severity.parse("medium").should eq(Severity::Medium)
      end

      it "parses 'low' to Low" do
        Severity.parse("low").should eq(Severity::Low)
      end

      it "parses unknown value to Unknown" do
        Severity.parse("unknown_value").should eq(Severity::Unknown)
      end

      it "parses case-insensitively" do
        Severity.parse("HIGH").should eq(Severity::High)
        Severity.parse("Critical").should eq(Severity::Critical)
      end
    end

    describe "#at_or_above?" do
      it "High is at or above Medium" do
        Severity::High.at_or_above?(Severity::Medium).should be_true
      end

      it "Critical is at or above High" do
        Severity::Critical.at_or_above?(Severity::High).should be_true
      end

      it "Low is not at or above High" do
        Severity::Low.at_or_above?(Severity::High).should be_false
      end

      it "Medium is at or above Medium (equal)" do
        Severity::Medium.at_or_above?(Severity::Medium).should be_true
      end

      it "Unknown is not at or above Low" do
        Severity::Unknown.at_or_above?(Severity::Low).should be_false
      end
    end
  end

  describe IgnoreRule do
    it "is always active without an expires date" do
      rule = IgnoreRule.new("GHSA-1234", reason: "accepted risk")
      rule.active?.should be_true
      rule.expired?.should be_false
    end

    it "is expired and not active with a past expires date" do
      past = Time.utc - 30.days
      rule = IgnoreRule.new("GHSA-5678", reason: "temporary", expires: past)
      rule.expired?.should be_true
      rule.active?.should be_false
    end

    it "is active with a future expires date" do
      future = Time.utc + 30.days
      rule = IgnoreRule.new("CVE-2024-9999", reason: "deferred", expires: future)
      rule.active?.should be_true
      rule.expired?.should be_false
    end
  end

  describe VulnerabilityReport do
    describe "#exit_code" do
      it "returns 0 when no vulnerabilities" do
        create_git_repository "safe_pkg", "1.0.0"
        resolver = GitResolver.new("safe_pkg", "https://github.com/owner/safe_pkg.git")
        pkg = Package.new("safe_pkg", resolver, version("1.0.0"))
        result = PackageScanResult.new(pkg, "pkg:github/owner/safe_pkg@1.0.0", [] of Vulnerability)

        report = VulnerabilityReport.new([result])
        report.exit_code.should eq(0)
      end

      it "returns 1 when vulnerabilities exist above threshold" do
        create_git_repository "vuln_pkg", "1.0.0"
        resolver = GitResolver.new("vuln_pkg", "https://github.com/owner/vuln_pkg.git")
        pkg = Package.new("vuln_pkg", resolver, version("1.0.0"))

        vuln = make_vuln("GHSA-test-0001", Severity::High)
        result = PackageScanResult.new(pkg, "pkg:github/owner/vuln_pkg@1.0.0", [vuln])

        report = VulnerabilityReport.new([result])
        report.exit_code.should eq(1)
      end

      it "returns 0 when vulnerabilities are below fail threshold" do
        create_git_repository "low_vuln_pkg", "1.0.0"
        resolver = GitResolver.new("low_vuln_pkg", "https://github.com/owner/low_vuln_pkg.git")
        pkg = Package.new("low_vuln_pkg", resolver, version("1.0.0"))

        vuln = make_vuln("GHSA-test-0002", Severity::Low)
        result = PackageScanResult.new(pkg, "pkg:github/owner/low_vuln_pkg@1.0.0", [vuln])

        report = VulnerabilityReport.new([result], fail_above: Severity::High)
        report.exit_code.should eq(0)
      end

      it "returns 1 when vulnerabilities match fail threshold exactly" do
        create_git_repository "med_vuln_pkg", "1.0.0"
        resolver = GitResolver.new("med_vuln_pkg", "https://github.com/owner/med_vuln_pkg.git")
        pkg = Package.new("med_vuln_pkg", resolver, version("1.0.0"))

        vuln = make_vuln("GHSA-test-0003", Severity::Medium)
        result = PackageScanResult.new(pkg, "pkg:github/owner/med_vuln_pkg@1.0.0", [vuln])

        report = VulnerabilityReport.new([result], fail_above: Severity::Medium)
        report.exit_code.should eq(1)
      end
    end

    describe "#vulnerability_count" do
      it "returns 0 when no vulnerabilities" do
        create_git_repository "count_pkg", "1.0.0"
        resolver = GitResolver.new("count_pkg", "https://github.com/owner/count_pkg.git")
        pkg = Package.new("count_pkg", resolver, version("1.0.0"))
        result = PackageScanResult.new(pkg, "pkg:github/owner/count_pkg@1.0.0", [] of Vulnerability)

        report = VulnerabilityReport.new([result])
        report.vulnerability_count.should eq(0)
      end

      it "returns correct count with multiple vulnerabilities" do
        create_git_repository "multi_vuln_pkg", "1.0.0"
        resolver = GitResolver.new("multi_vuln_pkg", "https://github.com/owner/multi_vuln_pkg.git")
        pkg = Package.new("multi_vuln_pkg", resolver, version("1.0.0"))

        vulns = [
          make_vuln("GHSA-0001", Severity::High),
          make_vuln("GHSA-0002", Severity::Critical),
        ]
        result = PackageScanResult.new(pkg, "pkg:github/owner/multi_vuln_pkg@1.0.0", vulns)

        report = VulnerabilityReport.new([result])
        report.vulnerability_count.should eq(2)
      end
    end

    describe "#filtered_results" do
      it "filters out ignored vulnerabilities by ID" do
        create_git_repository "ign_pkg", "1.0.0"
        resolver = GitResolver.new("ign_pkg", "https://github.com/owner/ign_pkg.git")
        pkg = Package.new("ign_pkg", resolver, version("1.0.0"))

        vulns = [
          make_vuln("GHSA-ignored", Severity::High),
          make_vuln("GHSA-kept", Severity::Medium),
        ]
        result = PackageScanResult.new(pkg, "pkg:github/owner/ign_pkg@1.0.0", vulns)

        ignore_rules = [IgnoreRule.new("GHSA-ignored")]
        report = VulnerabilityReport.new([result], ignore_rules: ignore_rules)

        filtered = report.filtered_results
        remaining_ids = filtered.flat_map(&.vulnerabilities.map(&.id))
        remaining_ids.should_not contain("GHSA-ignored")
        remaining_ids.should contain("GHSA-kept")
      end

      it "filters out vulnerabilities below min severity" do
        create_git_repository "sev_pkg", "1.0.0"
        resolver = GitResolver.new("sev_pkg", "https://github.com/owner/sev_pkg.git")
        pkg = Package.new("sev_pkg", resolver, version("1.0.0"))

        vulns = [
          make_vuln("GHSA-high", Severity::High),
          make_vuln("GHSA-low", Severity::Low),
        ]
        result = PackageScanResult.new(pkg, "pkg:github/owner/sev_pkg@1.0.0", vulns)

        report = VulnerabilityReport.new([result], min_severity: Severity::Medium)

        filtered = report.filtered_results
        remaining_ids = filtered.flat_map(&.vulnerabilities.map(&.id))
        remaining_ids.should contain("GHSA-high")
        remaining_ids.should_not contain("GHSA-low")
      end

      it "does not filter out expired ignore rules" do
        create_git_repository "exp_pkg", "1.0.0"
        resolver = GitResolver.new("exp_pkg", "https://github.com/owner/exp_pkg.git")
        pkg = Package.new("exp_pkg", resolver, version("1.0.0"))

        vulns = [
          make_vuln("GHSA-expired-ignore", Severity::High),
        ]
        result = PackageScanResult.new(pkg, "pkg:github/owner/exp_pkg@1.0.0", vulns)

        past = Time.utc - 30.days
        ignore_rules = [IgnoreRule.new("GHSA-expired-ignore", expires: past)]
        report = VulnerabilityReport.new([result], ignore_rules: ignore_rules)

        filtered = report.filtered_results
        remaining_ids = filtered.flat_map(&.vulnerabilities.map(&.id))
        remaining_ids.should contain("GHSA-expired-ignore")
      end
    end

    describe "#to_json" do
      it "produces valid JSON output" do
        create_git_repository "json_pkg", "1.0.0"
        resolver = GitResolver.new("json_pkg", "https://github.com/owner/json_pkg.git")
        pkg = Package.new("json_pkg", resolver, version("1.0.0"))

        vuln = make_vuln("GHSA-json-test", Severity::Medium)
        result = PackageScanResult.new(pkg, "pkg:github/owner/json_pkg@1.0.0", [vuln])

        report = VulnerabilityReport.new([result])
        io = IO::Memory.new
        report.to_json(io)

        json = JSON.parse(io.to_s)
        json["schema_version"].should eq("1.0.0")
        json["tool"].should eq("shards-alpha")
        json["summary"]["total_packages"].should eq(1)
        json["summary"]["total_vulnerabilities"].should eq(1)
        json["packages"].as_a.size.should eq(1)
        json["packages"].as_a.first["name"].should eq("json_pkg")
      end
    end

    describe "#to_sarif" do
      it "produces valid SARIF output" do
        create_git_repository "sarif_pkg", "1.0.0"
        resolver = GitResolver.new("sarif_pkg", "https://github.com/owner/sarif_pkg.git")
        pkg = Package.new("sarif_pkg", resolver, version("1.0.0"))

        vuln = make_vuln("GHSA-sarif-test", Severity::High)
        result = PackageScanResult.new(pkg, "pkg:github/owner/sarif_pkg@1.0.0", [vuln])

        report = VulnerabilityReport.new([result])
        io = IO::Memory.new
        report.to_sarif(io)

        json = JSON.parse(io.to_s)
        json["version"].should eq("2.1.0")
        json["$schema"].as_s.should contain("sarif")
        runs = json["runs"].as_a
        runs.size.should eq(1)
        runs.first["tool"]["driver"]["name"].should eq("shards-alpha audit")
      end
    end
  end
end
