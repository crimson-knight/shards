require "./command"
require "../compliance/report_builder"
require "../compliance/report_formatter"
require "file_utils"

module Shards
  module Commands
    class ComplianceReport < Command
      def run(args : Array(String))
        format = "json"
        output : String? = nil
        sections = ["all"]
        reviewer : String? = nil
        since : String? = nil
        sign = false

        args.each do |arg|
          case arg
          when .starts_with?("--format=")   then format = arg.split("=", 2).last
          when .starts_with?("--output=")   then output = arg.split("=", 2).last
          when .starts_with?("--sections=") then sections = arg.split("=", 2).last.split(",")
          when .starts_with?("--reviewer=") then reviewer = arg.split("=", 2).last
          when .starts_with?("--since=")    then since = arg.split("=", 2).last
          when "--sign"                     then sign = true
          end
        end

        ext = case format
              when "html"           then ".html"
              when "markdown", "md" then ".md"
              else                       ".json"
              end
        output_path = output || "#{spec.name}-compliance-report#{ext}"

        builder = Compliance::ReportBuilder.new(
          path: path,
          spec: spec,
          locks: locks,
          sections: sections,
          since: since,
          reviewer: reviewer
        )

        report_data = builder.build

        formatter = Compliance::ReportFormatter.new(format: format)
        formatter.write(report_data, output_path)

        if sign
          sign_report(output_path)
        end

        archive_report(output_path)

        Log.info { "Compliance report generated: #{output_path}" }
        print_summary(report_data)
      end

      private def sign_report(report_path : String)
        output = IO::Memory.new
        error = IO::Memory.new
        status = Process.run(
          "gpg", ["--detach-sign", "--armor", "--output", "#{report_path}.sig", report_path],
          output: output, error: error
        )
        if status.success?
          Log.info { "Signed report: #{report_path}.sig" }
        else
          Log.warn { "Could not sign report: #{error.to_s.strip}" }
        end
      rescue
        Log.warn { "GPG not available, skipping report signing" }
      end

      private def archive_report(report_path : String)
        archive_dir = File.join(path, ".shards", "audit", "reports")
        Dir.mkdir_p(archive_dir)

        timestamp = Time.utc.to_s("%Y%m%d-%H%M%S")
        ext = File.extname(report_path)
        basename = File.basename(report_path, ext)
        archive_path = File.join(archive_dir, "#{basename}-#{timestamp}#{ext}")

        FileUtils.cp(report_path, archive_path)
        Log.debug { "Archived report to #{archive_path}" }
      rescue ex
        Log.warn { "Could not archive report: #{ex.message}" }
      end

      private def print_summary(data : Compliance::ReportData)
        status = data.summary.overall_status.upcase
        deps = data.summary.total_dependencies
        Log.info { "Status: #{status} | Dependencies: #{deps}" }
      end
    end
  end
end
