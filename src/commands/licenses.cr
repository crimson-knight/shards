require "./command"
require "../spdx"
require "../license_scanner"
require "../license_policy"
require "json"
require "colorize"

module Shards
  module Commands
    class Licenses < Command
      def run(
        format : String = "terminal",
        policy_path : String? = nil,
        check : Bool = false,
        include_dev : Bool = false,
        detect : Bool = false,
      )
        packages = locks.shards
        root_spec = spec
        policy = LicensePolicy.load_policy(policy_path)
        report = LicensePolicy.evaluate(packages, root_spec, policy, detect)

        case format
        when "terminal" then render_terminal(report)
        when "json"     then render_json(report)
        when "csv"      then render_csv(report)
        when "markdown" then render_markdown(report)
        else
          raise Error.new("Unknown format: #{format}. Use: terminal, json, csv, markdown")
        end

        if check && (report.summary.denied > 0 || report.summary.unlicensed > 0)
          denied_count = report.summary.denied
          unlicensed_count = report.summary.unlicensed
          msgs = [] of String
          msgs << "#{denied_count} denied" if denied_count > 0
          msgs << "#{unlicensed_count} unlicensed" if unlicensed_count > 0
          raise Error.new("License policy violations: #{msgs.join(", ")}")
        end
      end

      # Terminal output -- tabular format with optional colors
      private def render_terminal(report : LicensePolicy::PolicyReport)
        puts "License Report for #{report.root_name} (#{report.root_version})"
        puts "Root license: #{report.root_license || "Not specified"}"
        puts ""

        # Determine column widths
        name_width = 20
        version_width = 12
        license_width = 20
        source_width = 10
        status_width = 12

        report.dependencies.each do |dep|
          name_width = {name_width, dep.name.size}.max
          version_width = {version_width, dep.version.size}.max
          lic = dep.effective_license || "Unlicensed"
          license_width = {license_width, lic.size}.max
          source_width = {source_width, dep.license_source.to_s.size}.max
        end

        # Header
        header = String.build do |s|
          s << "%-#{name_width}s  " % "Dependency"
          s << "%-#{version_width}s  " % "Version"
          s << "%-#{license_width}s  " % "License"
          s << "%-#{source_width}s" % "Source"
          s << "  %-#{status_width}s" % "Status" if report.policy_used
        end
        puts header
        puts "-" * header.size

        # Rows
        report.dependencies.each do |dep|
          license_str = dep.effective_license || "Unlicensed"
          source_str = dep.license_source.to_s
          verdict_str = dep.verdict.to_s

          line = String.build do |s|
            s << "%-#{name_width}s  " % dep.name
            s << "%-#{version_width}s  " % dep.version
            s << "%-#{license_width}s  " % license_str
            s << "%-#{source_width}s" % source_str
            if report.policy_used
              s << "  "
              s << verdict_str
            end
          end

          if Shards.colors?
            case dep.verdict
            when .denied?
              puts line.colorize(:red)
            when .unlicensed?
              puts line.colorize(:yellow)
            when .allowed?, .overridden?
              puts line.colorize(:green)
            else
              puts line
            end
          else
            puts line
          end
        end

        # Summary
        puts ""
        s = report.summary
        summary_parts = ["Total: #{s.total}"]
        summary_parts << "Allowed: #{s.allowed}" if report.policy_used && s.allowed > 0
        summary_parts << "Denied: #{s.denied}" if s.denied > 0
        summary_parts << "Unlicensed: #{s.unlicensed}" if s.unlicensed > 0
        summary_parts << "Unknown: #{s.unknown}" if s.unknown > 0
        summary_parts << "Overridden: #{s.overridden}" if s.overridden > 0
        puts "Summary: #{summary_parts.join(", ")}"
      end

      # JSON output
      private def render_json(report : LicensePolicy::PolicyReport)
        JSON.build(STDOUT, indent: 2) do |json|
          json.object do
            json.field "project", report.root_name
            json.field "version", report.root_version
            json.field "license", report.root_license

            json.field "dependencies" do
              json.array do
                report.dependencies.each do |dep|
                  json.object do
                    json.field "name", dep.name
                    json.field "version", dep.version
                    json.field "declared_license", dep.declared_license
                    json.field "detected_license", dep.detected_license
                    json.field "effective_license", dep.effective_license
                    json.field "source", dep.license_source.to_s
                    json.field "spdx_valid", dep.spdx_valid
                    json.field "category", dep.category.to_s
                    json.field "verdict", dep.verdict.to_s
                    if reason = dep.override_reason
                      json.field "override_reason", reason
                    end
                  end
                end
              end
            end

            json.field "summary" do
              json.object do
                json.field "total", report.summary.total
                json.field "allowed", report.summary.allowed
                json.field "denied", report.summary.denied
                json.field "unlicensed", report.summary.unlicensed
                json.field "unknown", report.summary.unknown
                json.field "overridden", report.summary.overridden
              end
            end

            json.field "policy_used", report.policy_used
          end
        end
        puts # trailing newline
      end

      # CSV output
      private def render_csv(report : LicensePolicy::PolicyReport)
        puts "Name,Version,Declared License,Detected License,Effective License,Source,SPDX Valid,Category,Verdict"
        report.dependencies.each do |dep|
          row = [
            csv_escape(dep.name),
            csv_escape(dep.version),
            csv_escape(dep.declared_license || ""),
            csv_escape(dep.detected_license || ""),
            csv_escape(dep.effective_license || ""),
            csv_escape(dep.license_source.to_s),
            dep.spdx_valid.to_s,
            csv_escape(dep.category.to_s),
            csv_escape(dep.verdict.to_s),
          ]
          puts row.join(",")
        end
      end

      # Markdown output
      private def render_markdown(report : LicensePolicy::PolicyReport)
        puts "# License Report for #{report.root_name} (#{report.root_version})"
        puts ""
        puts "Root license: #{report.root_license || "Not specified"}"
        puts ""

        if report.policy_used
          puts "| Dependency | Version | License | Source | SPDX Valid | Category | Verdict |"
          puts "|------------|---------|---------|--------|------------|----------|---------|"
          report.dependencies.each do |dep|
            lic = dep.effective_license || "Unlicensed"
            puts "| #{dep.name} | #{dep.version} | #{lic} | #{dep.license_source} | #{dep.spdx_valid} | #{dep.category} | #{dep.verdict} |"
          end
        else
          puts "| Dependency | Version | License | Source | SPDX Valid | Category |"
          puts "|------------|---------|---------|--------|------------|----------|"
          report.dependencies.each do |dep|
            lic = dep.effective_license || "Unlicensed"
            puts "| #{dep.name} | #{dep.version} | #{lic} | #{dep.license_source} | #{dep.spdx_valid} | #{dep.category} |"
          end
        end

        puts ""
        s = report.summary
        puts "**Summary:** #{s.total} dependencies"
        if s.denied > 0
          puts "- Denied: #{s.denied}"
        end
        if s.unlicensed > 0
          puts "- Unlicensed: #{s.unlicensed}"
        end
        if s.unknown > 0
          puts "- Unknown: #{s.unknown}"
        end
      end

      private def csv_escape(value : String) : String
        if value.includes?(',') || value.includes?('"') || value.includes?('\n')
          "\"#{value.gsub('"', "\"\"")}\""
        else
          value
        end
      end
    end
  end
end
