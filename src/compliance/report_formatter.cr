require "json"
require "./report_builder"
require "./html_template"

module Shards
  module Compliance
    class ReportFormatter
      getter format : String
      getter template_path : String?

      def initialize(@format, @template_path = nil)
      end

      def write(data : ReportData, output_path : String) : Nil
        dir = File.dirname(output_path)
        Dir.mkdir_p(dir) unless dir == "."

        case format
        when "json"
          write_json(data, output_path)
        when "html"
          write_html(data, output_path)
        when "markdown", "md"
          write_markdown(data, output_path)
        else
          raise Error.new("Unknown report format: #{format}. Use 'json', 'html', or 'markdown'.")
        end
      end

      private def write_json(data : ReportData, path : String)
        File.open(path, "w") do |file|
          JSON.build(file, indent: 2) do |json|
            json.object do
              json.field "report" do
                json.object do
                  json.field "version", data.version
                  json.field "generated_at", data.generated_at.to_rfc3339
                  json.field "generator", data.generator

                  json.field "project" do
                    json.object do
                      json.field "name", data.project.name
                      json.field "version", data.project.version
                      json.field "crystal_version", data.project.crystal_version
                    end
                  end

                  json.field "reviewer", data.reviewer if data.reviewer

                  json.field "summary" do
                    serialize_summary(json, data.summary)
                  end

                  json.field "sections" do
                    json.object do
                      json.field "sbom", data.sections.sbom if data.sections.sbom
                      json.field "vulnerability_audit", data.sections.vulnerability_audit if data.sections.vulnerability_audit
                      json.field "license_audit", data.sections.license_audit if data.sections.license_audit
                      json.field "policy_compliance", data.sections.policy_compliance if data.sections.policy_compliance
                      json.field "integrity", data.sections.integrity if data.sections.integrity
                      json.field "change_history", data.sections.change_history if data.sections.change_history
                    end
                  end

                  if att = data.attestation
                    json.field "attestation" do
                      json.object do
                        json.field "reviewer", att.reviewer
                        json.field "reviewed_at", att.reviewed_at.to_rfc3339
                        json.field "notes", att.notes if att.notes
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      private def serialize_summary(json : JSON::Builder, summary : Summary)
        json.object do
          json.field "total_dependencies", summary.total_dependencies
          json.field "direct_dependencies", summary.direct_dependencies
          json.field "transitive_dependencies", summary.transitive_dependencies
          json.field "vulnerabilities" do
            json.object do
              json.field "critical", summary.vulnerabilities.critical
              json.field "high", summary.vulnerabilities.high
              json.field "medium", summary.vulnerabilities.medium
              json.field "low", summary.vulnerabilities.low
            end
          end
          json.field "license_compliance", summary.license_compliance
          json.field "policy_compliance", summary.policy_compliance
          unless summary.integrity_verified.nil?
            json.field "integrity_verified", summary.integrity_verified
          end
          json.field "overall_status", summary.overall_status
        end
      end

      private def write_html(data : ReportData, path : String)
        html = HtmlTemplate.render(data)
        File.write(path, html)
      end

      private def write_markdown(data : ReportData, path : String)
        md = String.build do |str|
          str << "# Compliance Report: #{data.project.name}\n\n"
          str << "**Generated:** #{data.generated_at.to_rfc3339}\n"
          str << "**Generator:** #{data.generator}\n"
          str << "**Project Version:** #{data.project.version}\n"
          str << "**Crystal Version:** #{data.project.crystal_version}\n"
          if reviewer = data.reviewer
            str << "**Reviewer:** #{reviewer}\n"
          end

          str << "\n---\n\n"
          str << "## Executive Summary\n\n"
          str << "| Metric | Value |\n"
          str << "|--------|-------|\n"
          str << "| Total Dependencies | #{data.summary.total_dependencies} |\n"
          str << "| Direct Dependencies | #{data.summary.direct_dependencies} |\n"
          str << "| Transitive Dependencies | #{data.summary.transitive_dependencies} |\n"
          str << "| Overall Status | **#{data.summary.overall_status.upcase}** |\n"
          str << "| License Compliance | #{data.summary.license_compliance} |\n"
          str << "| Policy Compliance | #{data.summary.policy_compliance} |\n"

          vuln = data.summary.vulnerabilities
          if vuln.critical > 0 || vuln.high > 0 || vuln.medium > 0 || vuln.low > 0
            str << "\n### Vulnerabilities\n\n"
            str << "| Severity | Count |\n"
            str << "|----------|-------|\n"
            str << "| Critical | #{vuln.critical} |\n"
            str << "| High | #{vuln.high} |\n"
            str << "| Medium | #{vuln.medium} |\n"
            str << "| Low | #{vuln.low} |\n"
          end

          if sbom = data.sections.sbom
            str << "\n---\n\n## Software Bill of Materials\n\n"
            if pkgs = sbom["packages"]?
              str << "| Package | Version | License |\n"
              str << "|---------|---------|--------|\n"
              pkgs.as_a.each do |pkg|
                str << "| #{pkg["name"]?} | #{pkg["versionInfo"]?} | #{pkg["licenseDeclared"]?} |\n"
              end
            end
          end

          if integrity = data.sections.integrity
            str << "\n---\n\n## Integrity Verification\n\n"
            all_ok = integrity["all_verified"]?.try(&.as_bool)
            str << "All verified: **#{all_ok}**\n\n"
            if deps = integrity["dependencies"]?
              str << "| Dependency | Version | Verified | Reason |\n"
              str << "|-----------|---------|----------|--------|\n"
              deps.as_a.each do |dep|
                str << "| #{dep["name"]?} | #{dep["version"]?} | #{dep["verified"]?} | #{dep["reason"]?} |\n"
              end
            end
          end

          if att = data.attestation
            str << "\n---\n\n## Attestation\n\n"
            str << "**Reviewer:** #{att.reviewer}\n"
            str << "**Reviewed At:** #{att.reviewed_at.to_rfc3339}\n"
            str << "**Notes:** #{att.notes || "None"}\n"
          end
        end

        File.write(path, md)
      end
    end
  end
end
