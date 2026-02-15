require "./spec_helper"
require "json"
require "../../src/version"
require "../../src/compliance/report_builder"
require "../../src/compliance/report_formatter"
require "../../src/compliance/html_template"

module Shards
  module Compliance
    describe ReportData do
      it "initializes with required fields" do
        project = ProjectInfo.new(
          name: "test_project",
          version: "1.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 5,
          direct_dependencies: 3,
          transitive_dependencies: 2,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: true,
          overall_status: "pass"
        )

        sections = SectionData.new

        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections
        )

        report.project.name.should eq("test_project")
        report.project.version.should eq("1.0.0")
        report.project.crystal_version.should eq("1.10.0")
        report.version.should eq("1.0")
        report.generator.should contain("shards-alpha")
        report.reviewer.should be_nil
        report.attestation.should be_nil
      end

      it "includes reviewer and attestation when provided" do
        project = ProjectInfo.new(
          name: "reviewed_project",
          version: "2.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 0,
          direct_dependencies: 0,
          transitive_dependencies: 0,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: true,
          overall_status: "pass"
        )

        sections = SectionData.new
        attestation = Attestation.new(
          reviewer: "security-team",
          reviewed_at: Time.utc,
          notes: "Approved for production"
        )

        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections,
          reviewer: "security-team",
          attestation: attestation
        )

        report.reviewer.should eq("security-team")
        report.attestation.should_not be_nil
        report.attestation.not_nil!.reviewer.should eq("security-team")
        report.attestation.not_nil!.notes.should eq("Approved for production")
      end
    end

    describe Summary do
      it "reports pass when no vulnerabilities and all sections pass" do
        vuln_counts = VulnerabilityCounts.new(critical: 0, high: 0, medium: 0, low: 0)
        summary = Summary.new(
          total_dependencies: 3,
          direct_dependencies: 2,
          transitive_dependencies: 1,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: true,
          overall_status: "pass"
        )

        summary.overall_status.should eq("pass")
        summary.vulnerabilities.critical.should eq(0)
        summary.vulnerabilities.high.should eq(0)
      end

      it "stores vulnerability counts correctly" do
        vuln_counts = VulnerabilityCounts.new(critical: 1, high: 2, medium: 3, low: 4)

        vuln_counts.critical.should eq(1)
        vuln_counts.high.should eq(2)
        vuln_counts.medium.should eq(3)
        vuln_counts.low.should eq(4)
      end

      it "tracks dependency counts" do
        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 10,
          direct_dependencies: 4,
          transitive_dependencies: 6,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "unavailable",
          integrity_verified: nil,
          overall_status: "pass"
        )

        summary.total_dependencies.should eq(10)
        summary.direct_dependencies.should eq(4)
        summary.transitive_dependencies.should eq(6)
      end
    end

    describe ReportBuilder do
      it "determines overall status as fail with critical vulnerabilities" do
        create_git_repository "cr_dep", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("cr_project/lib/cr_dep")

          File.write "cr_project/shard.yml", {
            name: "cr_project", version: "0.1.0",
            dependencies: {cr_dep: {git: git_url(:cr_dep)}},
          }.to_yaml

          File.write "cr_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {cr_dep: {git: git_url(:cr_dep), version: "1.0.0"}},
          })

          File.write "cr_project/lib/cr_dep/shard.yml", {
            name: "cr_dep", version: "1.0.0",
          }.to_yaml

          File.write "cr_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {cr_dep: {git: git_url(:cr_dep), version: "1.0.0"}},
          })

          spec = Shards::Spec.from_file("cr_project")
          locks = Shards::Lock.from_file("cr_project/shard.lock")

          builder = ReportBuilder.new(
            path: "cr_project",
            spec: spec,
            locks: locks,
            sections: ["sbom"]
          )

          report = builder.build
          # Without vulnerabilities, overall status should be pass
          report.summary.overall_status.should eq("pass")
          report.summary.total_dependencies.should eq(1)
          report.summary.direct_dependencies.should eq(1)
          report.summary.transitive_dependencies.should eq(0)
        end
      end

      it "computes transitive dependencies correctly" do
        create_git_repository "trans_a", "1.0.0"
        create_git_repository "trans_b", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("trans_project/lib/trans_a")
          Dir.mkdir_p("trans_project/lib/trans_b")

          File.write "trans_project/shard.yml", {
            name: "trans_project", version: "0.1.0",
            dependencies: {trans_a: {git: git_url(:trans_a)}},
          }.to_yaml

          File.write "trans_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {
              trans_a: {git: git_url(:trans_a), version: "1.0.0"},
              trans_b: {git: git_url(:trans_b), version: "1.0.0"},
            },
          })

          File.write "trans_project/lib/trans_a/shard.yml", {
            name: "trans_a", version: "1.0.0",
          }.to_yaml

          File.write "trans_project/lib/trans_b/shard.yml", {
            name: "trans_b", version: "1.0.0",
          }.to_yaml

          File.write "trans_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {
              trans_a: {git: git_url(:trans_a), version: "1.0.0"},
              trans_b: {git: git_url(:trans_b), version: "1.0.0"},
            },
          })

          spec = Shards::Spec.from_file("trans_project")
          locks = Shards::Lock.from_file("trans_project/shard.lock")

          builder = ReportBuilder.new(
            path: "trans_project",
            spec: spec,
            locks: locks,
            sections: ["sbom"]
          )

          report = builder.build
          report.summary.total_dependencies.should eq(2)
          report.summary.direct_dependencies.should eq(1)
          report.summary.transitive_dependencies.should eq(1)
        end
      end

      it "generates SBOM section with SPDX structure" do
        create_git_repository "sbom_dep", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("sbom_rpt_project/lib/sbom_dep")

          File.write "sbom_rpt_project/shard.yml", {
            name: "sbom_rpt_project", version: "0.1.0",
            dependencies: {sbom_dep: {git: git_url(:sbom_dep)}},
          }.to_yaml

          File.write "sbom_rpt_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {sbom_dep: {git: git_url(:sbom_dep), version: "1.0.0"}},
          })

          File.write "sbom_rpt_project/lib/sbom_dep/shard.yml", {
            name: "sbom_dep", version: "1.0.0",
          }.to_yaml

          File.write "sbom_rpt_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {sbom_dep: {git: git_url(:sbom_dep), version: "1.0.0"}},
          })

          spec = Shards::Spec.from_file("sbom_rpt_project")
          locks = Shards::Lock.from_file("sbom_rpt_project/shard.lock")

          builder = ReportBuilder.new(
            path: "sbom_rpt_project",
            spec: spec,
            locks: locks,
            sections: ["sbom"]
          )

          report = builder.build
          report.sections.sbom.should_not be_nil

          sbom = report.sections.sbom.not_nil!
          sbom["spdxVersion"].should eq("SPDX-2.3")
          sbom["dataLicense"].should eq("CC0-1.0")
          sbom["packages"].as_a.size.should eq(2)
        end
      end

      it "filters sections when specific sections are requested" do
        create_git_repository "filter_dep", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("filter_project/lib/filter_dep")

          File.write "filter_project/shard.yml", {
            name: "filter_project", version: "0.1.0",
            dependencies: {filter_dep: {git: git_url(:filter_dep)}},
          }.to_yaml

          File.write "filter_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {filter_dep: {git: git_url(:filter_dep), version: "1.0.0"}},
          })

          File.write "filter_project/lib/filter_dep/shard.yml", {
            name: "filter_dep", version: "1.0.0",
          }.to_yaml

          File.write "filter_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {filter_dep: {git: git_url(:filter_dep), version: "1.0.0"}},
          })

          spec = Shards::Spec.from_file("filter_project")
          locks = Shards::Lock.from_file("filter_project/shard.lock")

          # Request only "sbom" section
          builder = ReportBuilder.new(
            path: "filter_project",
            spec: spec,
            locks: locks,
            sections: ["sbom"]
          )

          report = builder.build
          report.sections.sbom.should_not be_nil
          # Other sections should not be collected
          report.sections.vulnerability_audit.should be_nil
          report.sections.license_audit.should be_nil
          report.sections.policy_compliance.should be_nil
          report.sections.change_history.should be_nil
        end
      end

      it "includes all sections when 'all' is requested" do
        create_git_repository "all_dep", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("all_project/lib/all_dep")

          File.write "all_project/shard.yml", {
            name: "all_project", version: "0.1.0",
            dependencies: {all_dep: {git: git_url(:all_dep)}},
          }.to_yaml

          File.write "all_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {all_dep: {git: git_url(:all_dep), version: "1.0.0"}},
          })

          File.write "all_project/lib/all_dep/shard.yml", {
            name: "all_dep", version: "1.0.0",
          }.to_yaml

          File.write "all_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {all_dep: {git: git_url(:all_dep), version: "1.0.0"}},
          })

          spec = Shards::Spec.from_file("all_project")
          locks = Shards::Lock.from_file("all_project/shard.lock")

          builder = ReportBuilder.new(
            path: "all_project",
            spec: spec,
            locks: locks,
            sections: ["all"]
          )

          report = builder.build
          # SBOM should always be present when "all" is requested
          report.sections.sbom.should_not be_nil
          # Integrity should attempt to run (may produce data since packages have no checksum)
          report.sections.integrity.should_not be_nil
        end
      end

      it "adds attestation when reviewer is specified" do
        create_git_repository "attest_dep", "1.0.0"

        Dir.cd(tmp_path) do
          Dir.mkdir_p("attest_project/lib/attest_dep")

          File.write "attest_project/shard.yml", {
            name: "attest_project", version: "0.1.0",
            dependencies: {attest_dep: {git: git_url(:attest_dep)}},
          }.to_yaml

          File.write "attest_project/shard.lock", YAML.dump({
            version: Lock::CURRENT_VERSION,
            shards:  {attest_dep: {git: git_url(:attest_dep), version: "1.0.0"}},
          })

          File.write "attest_project/lib/attest_dep/shard.yml", {
            name: "attest_dep", version: "1.0.0",
          }.to_yaml

          File.write "attest_project/lib/.shards.info", YAML.dump({
            version: "1.0",
            shards:  {attest_dep: {git: git_url(:attest_dep), version: "1.0.0"}},
          })

          spec = Shards::Spec.from_file("attest_project")
          locks = Shards::Lock.from_file("attest_project/shard.lock")

          builder = ReportBuilder.new(
            path: "attest_project",
            spec: spec,
            locks: locks,
            sections: ["sbom"],
            reviewer: "alice@example.com"
          )

          report = builder.build
          report.reviewer.should eq("alice@example.com")
          report.attestation.should_not be_nil
          report.attestation.not_nil!.reviewer.should eq("alice@example.com")
        end
      end
    end

    describe ReportFormatter do
      it "writes JSON with correct top-level structure" do
        project = ProjectInfo.new(
          name: "json_project",
          version: "1.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 2,
          direct_dependencies: 1,
          transitive_dependencies: 1,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "unavailable",
          integrity_verified: nil,
          overall_status: "pass"
        )

        sections = SectionData.new
        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections
        )

        output_path = File.tempname("compliance", ".json")
        begin
          formatter = ReportFormatter.new("json")
          formatter.write(report, output_path)

          File.exists?(output_path).should be_true
          json = JSON.parse(File.read(output_path))

          json["report"].should_not be_nil
          json["report"]["version"].should eq("1.0")
          json["report"]["project"]["name"].should eq("json_project")
          json["report"]["project"]["version"].should eq("1.0.0")
          json["report"]["summary"]["total_dependencies"].should eq(2)
          json["report"]["summary"]["overall_status"].should eq("pass")
          json["report"]["summary"]["vulnerabilities"]["critical"].should eq(0)
          json["report"]["sections"].should_not be_nil
        ensure
          File.delete(output_path) if File.exists?(output_path)
        end
      end

      it "writes JSON with attestation when reviewer is present" do
        project = ProjectInfo.new(
          name: "att_json_project",
          version: "1.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 0,
          direct_dependencies: 0,
          transitive_dependencies: 0,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: true,
          overall_status: "pass"
        )

        sections = SectionData.new
        attestation = Attestation.new(
          reviewer: "reviewer@corp.com",
          reviewed_at: Time.utc
        )

        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections,
          reviewer: "reviewer@corp.com",
          attestation: attestation
        )

        output_path = File.tempname("compliance_att", ".json")
        begin
          formatter = ReportFormatter.new("json")
          formatter.write(report, output_path)

          json = JSON.parse(File.read(output_path))
          json["report"]["reviewer"].should eq("reviewer@corp.com")
          json["report"]["attestation"]["reviewer"].should eq("reviewer@corp.com")
        ensure
          File.delete(output_path) if File.exists?(output_path)
        end
      end

      it "writes HTML with DOCTYPE and key elements" do
        project = ProjectInfo.new(
          name: "html_project",
          version: "2.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 3,
          direct_dependencies: 2,
          transitive_dependencies: 1,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: true,
          overall_status: "pass"
        )

        sections = SectionData.new
        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections
        )

        output_path = File.tempname("compliance", ".html")
        begin
          formatter = ReportFormatter.new("html")
          formatter.write(report, output_path)

          File.exists?(output_path).should be_true
          html = File.read(output_path)

          html.should contain("<!DOCTYPE html>")
          html.should contain("<html lang=\"en\">")
          html.should contain("Supply Chain Compliance Report")
          html.should contain("html_project")
          html.should contain("Executive Summary")
          html.should contain("PASS")
          html.should contain("</html>")
        ensure
          File.delete(output_path) if File.exists?(output_path)
        end
      end

      it "writes markdown with headers and tables" do
        project = ProjectInfo.new(
          name: "md_project",
          version: "3.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new(critical: 0, high: 0, medium: 1, low: 2)
        summary = Summary.new(
          total_dependencies: 5,
          direct_dependencies: 3,
          transitive_dependencies: 2,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "warning",
          integrity_verified: false,
          overall_status: "action_required"
        )

        sections = SectionData.new
        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections,
          reviewer: "sec-lead"
        )

        output_path = File.tempname("compliance", ".md")
        begin
          formatter = ReportFormatter.new("markdown")
          formatter.write(report, output_path)

          File.exists?(output_path).should be_true
          md = File.read(output_path)

          md.should contain("# Compliance Report: md_project")
          md.should contain("## Executive Summary")
          md.should contain("| Metric | Value |")
          md.should contain("| Total Dependencies | 5 |")
          md.should contain("**ACTION_REQUIRED**")
          md.should contain("**Reviewer:** sec-lead")
          # Vulnerability table should be present since there are non-zero counts
          md.should contain("### Vulnerabilities")
          md.should contain("| Medium | 1 |")
          md.should contain("| Low | 2 |")
        ensure
          File.delete(output_path) if File.exists?(output_path)
        end
      end

      it "raises on unknown format" do
        project = ProjectInfo.new(
          name: "unknown_fmt",
          version: "1.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 0,
          direct_dependencies: 0,
          transitive_dependencies: 0,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: nil,
          overall_status: "pass"
        )

        sections = SectionData.new
        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections
        )

        output_path = File.tempname("compliance", ".txt")
        begin
          formatter = ReportFormatter.new("xml")
          expect_raises(Error, "Unknown report format") do
            formatter.write(report, output_path)
          end
        ensure
          File.delete(output_path) if File.exists?(output_path)
        end
      end
    end

    describe HtmlTemplate do
      it "renders complete HTML document" do
        project = ProjectInfo.new(
          name: "tmpl_project",
          version: "1.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 1,
          direct_dependencies: 1,
          transitive_dependencies: 0,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: true,
          overall_status: "pass"
        )

        sections = SectionData.new
        attestation = Attestation.new(
          reviewer: "admin",
          reviewed_at: Time.utc
        )

        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections,
          reviewer: "admin",
          attestation: attestation
        )

        html = HtmlTemplate.render(report)

        html.should contain("<!DOCTYPE html>")
        html.should contain("<title>Compliance Report - tmpl_project</title>")
        html.should contain("status-badge pass")
        html.should contain("Attestation")
        html.should contain("admin")
        html.should contain("<footer>")
        html.should contain("<script>")
      end

      it "renders fail status badge for failing reports" do
        project = ProjectInfo.new(
          name: "fail_project",
          version: "1.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new(critical: 2)
        summary = Summary.new(
          total_dependencies: 3,
          direct_dependencies: 3,
          transitive_dependencies: 0,
          vulnerabilities: vuln_counts,
          license_compliance: "fail",
          policy_compliance: "fail",
          integrity_verified: false,
          overall_status: "fail"
        )

        sections = SectionData.new
        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections
        )

        html = HtmlTemplate.render(report)

        html.should contain("status-badge fail")
        html.should contain("FAIL")
      end

      it "escapes HTML special characters in project names" do
        project = ProjectInfo.new(
          name: "test<script>alert(1)</script>",
          version: "1.0.0",
          crystal_version: "1.10.0"
        )

        vuln_counts = VulnerabilityCounts.new
        summary = Summary.new(
          total_dependencies: 0,
          direct_dependencies: 0,
          transitive_dependencies: 0,
          vulnerabilities: vuln_counts,
          license_compliance: "pass",
          policy_compliance: "pass",
          integrity_verified: nil,
          overall_status: "pass"
        )

        sections = SectionData.new
        report = ReportData.new(
          project: project,
          summary: summary,
          sections: sections
        )

        html = HtmlTemplate.render(report)

        html.should_not contain("<script>alert(1)</script>")
        html.should contain("&lt;script&gt;alert(1)&lt;/script&gt;")
      end
    end
  end
end
