require "json"
require "../checksum"
require "../purl"

module Shards
  module Compliance
    struct ProjectInfo
      getter name : String
      getter version : String
      getter crystal_version : String

      def initialize(@name, @version, @crystal_version)
      end
    end

    struct VulnerabilityCounts
      property critical : Int32
      property high : Int32
      property medium : Int32
      property low : Int32

      def initialize(@critical = 0, @high = 0, @medium = 0, @low = 0)
      end
    end

    struct Summary
      getter total_dependencies : Int32
      getter direct_dependencies : Int32
      getter transitive_dependencies : Int32
      getter vulnerabilities : VulnerabilityCounts
      getter license_compliance : String
      getter policy_compliance : String
      getter integrity_verified : Bool?
      getter overall_status : String

      def initialize(@total_dependencies, @direct_dependencies, @transitive_dependencies,
                     @vulnerabilities, @license_compliance, @policy_compliance,
                     @integrity_verified, @overall_status)
      end
    end

    struct SectionData
      property sbom : JSON::Any?
      property vulnerability_audit : JSON::Any?
      property license_audit : JSON::Any?
      property policy_compliance : JSON::Any?
      property integrity : JSON::Any?
      property change_history : JSON::Any?

      def initialize
        @sbom = nil
        @vulnerability_audit = nil
        @license_audit = nil
        @policy_compliance = nil
        @integrity = nil
        @change_history = nil
      end
    end

    struct Attestation
      getter reviewer : String
      getter reviewed_at : Time
      getter notes : String?

      def initialize(@reviewer, @reviewed_at, @notes = nil)
      end
    end

    struct ReportData
      getter version : String
      getter generated_at : Time
      getter generator : String
      getter project : ProjectInfo
      getter reviewer : String?
      getter summary : Summary
      getter sections : SectionData
      getter attestation : Attestation?

      def initialize(@project, @summary, @sections,
                     @reviewer = nil, @attestation = nil,
                     @version = "1.0",
                     @generated_at = Time.utc,
                     @generator = "shards-alpha #{VERSION}")
      end
    end

    class ReportBuilder
      getter path : String
      getter spec : Shards::Spec
      getter locks : Shards::Lock
      getter requested_sections : Array(String)
      getter since : String?
      getter reviewer : String?

      def initialize(@path, @spec, @locks,
                     sections : Array(String) = ["all"],
                     @since = nil, @reviewer = nil)
        @requested_sections = sections
      end

      def build : ReportData
        packages = locks.shards
        root_spec = spec

        sections = SectionData.new

        if include_section?("sbom")
          sections.sbom = collect_sbom(root_spec, packages)
        end

        if include_section?("audit")
          sections.vulnerability_audit = collect_vulnerability_audit
        end

        if include_section?("licenses")
          sections.license_audit = collect_license_audit
        end

        if include_section?("policy")
          sections.policy_compliance = collect_policy_compliance
        end

        if include_section?("integrity")
          sections.integrity = collect_integrity_check(packages)
        end

        if include_section?("changelog")
          sections.change_history = collect_change_history
        end

        summary = compute_summary(packages, root_spec, sections)

        attestation = if r = reviewer
                        Attestation.new(reviewer: r, reviewed_at: Time.utc)
                      end

        ReportData.new(
          project: ProjectInfo.new(
            name: root_spec.name,
            version: root_spec.version.to_s,
            crystal_version: Shards.crystal_version
          ),
          summary: summary,
          sections: sections,
          reviewer: reviewer,
          attestation: attestation
        )
      end

      private def include_section?(name : String) : Bool
        requested_sections.includes?("all") || requested_sections.includes?(name)
      end

      private def try_collect(section_name : String, &) : JSON::Any?
        yield
      rescue ex
        Log.warn { "#{section_name} section unavailable: #{ex.message}" }
        nil
      end

      private def collect_sbom(root_spec : Shards::Spec, packages : Array(Package)) : JSON::Any?
        try_collect("sbom") do
          io = IO::Memory.new
          locked_names = packages.map(&.name).to_set
          dep_graph = {} of String => Array(String)
          packages.each do |pkg|
            deps = begin
              pkg.spec.dependencies.map(&.name).select { |n| locked_names.includes?(n) }
            rescue
              [] of String
            end
            dep_graph[pkg.name] = deps
          end

          JSON.build(io, indent: 2) do |json|
            json.object do
              json.field "spdxVersion", "SPDX-2.3"
              json.field "dataLicense", "CC0-1.0"
              json.field "SPDXID", "SPDXRef-DOCUMENT"
              json.field "name", "#{root_spec.name}-sbom"
              json.field "documentNamespace", "https://spdx.org/spdxdocs/#{root_spec.name}-#{generate_uuid}"

              json.field "creationInfo" do
                json.object do
                  json.field "created", Time.utc.to_rfc3339
                  json.field "creators" do
                    json.array { json.string "Tool: shards-alpha #{VERSION}" }
                  end
                end
              end

              json.field "packages" do
                json.array do
                  # Root package
                  json.object do
                    json.field "SPDXID", "SPDXRef-RootPackage"
                    json.field "name", root_spec.name
                    json.field "versionInfo", root_spec.version.to_s
                    json.field "downloadLocation", "NOASSERTION"
                    json.field "filesAnalyzed", false
                    license_val = root_spec.license.try { |l| l.empty? ? "NOASSERTION" : l } || "NOASSERTION"
                    json.field "licenseDeclared", license_val
                    json.field "licenseConcluded", license_val
                    json.field "copyrightText", "NOASSERTION"
                  end

                  packages.each do |pkg|
                    spdx_id = "SPDXRef-Package-#{pkg.name.gsub(/[^a-zA-Z0-9.\-]/, "-")}"
                    source_url = pkg.resolver.is_a?(PathResolver) ? "NOASSERTION" : pkg.resolver.source
                    purl = PurlGenerator.generate(pkg)

                    json.object do
                      json.field "SPDXID", spdx_id
                      json.field "name", pkg.name
                      json.field "versionInfo", pkg.version.to_s
                      json.field "downloadLocation", source_url
                      json.field "filesAnalyzed", false
                      license_val = begin
                        l = pkg.spec.license
                        (l && !l.empty?) ? l : "NOASSERTION"
                      rescue
                        "NOASSERTION"
                      end
                      json.field "licenseDeclared", license_val
                      json.field "licenseConcluded", license_val
                      json.field "copyrightText", "NOASSERTION"
                      if purl
                        json.field "externalRefs" do
                          json.array do
                            json.object do
                              json.field "referenceCategory", "PACKAGE-MANAGER"
                              json.field "referenceType", "purl"
                              json.field "referenceLocator", purl
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end

              json.field "relationships" do
                json.array do
                  write_rel(json, "SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-RootPackage")
                  root_dep_names = root_spec.dependencies.map(&.name).to_set
                  packages.each do |pkg|
                    if root_dep_names.includes?(pkg.name)
                      write_rel(json, "SPDXRef-RootPackage", "DEPENDS_ON",
                        "SPDXRef-Package-#{pkg.name.gsub(/[^a-zA-Z0-9.\-]/, "-")}")
                    end
                  end
                  packages.each do |pkg|
                    if deps = dep_graph[pkg.name]?
                      deps.each do |dep_name|
                        write_rel(json,
                          "SPDXRef-Package-#{pkg.name.gsub(/[^a-zA-Z0-9.\-]/, "-")}",
                          "DEPENDS_ON",
                          "SPDXRef-Package-#{dep_name.gsub(/[^a-zA-Z0-9.\-]/, "-")}")
                      end
                    end
                  end
                end
              end
            end
          end

          JSON.parse(io.to_s)
        end
      end

      private def write_rel(json : JSON::Builder, from : String, type : String, to : String)
        json.object do
          json.field "spdxElementId", from
          json.field "relationshipType", type
          json.field "relatedSpdxElement", to
        end
      end

      private def collect_vulnerability_audit : JSON::Any?
        try_collect("vulnerability_audit") do
          run_subcommand(["audit", "--format=json"])
        end
      end

      private def collect_license_audit : JSON::Any?
        try_collect("license_audit") do
          run_subcommand(["licenses", "--format=json"])
        end
      end

      private def collect_policy_compliance : JSON::Any?
        try_collect("policy_compliance") do
          policy_path = File.join(path, ".shards-policy.yml")
          return nil unless File.exists?(policy_path)
          run_subcommand(["policy", "check", "--format=json"])
        end
      end

      private def collect_change_history : JSON::Any?
        try_collect("change_history") do
          log_path = File.join(path, ".shards", "audit", "changelog.json")
          if File.exists?(log_path)
            JSON.parse(File.read(log_path))
          else
            nil
          end
        end
      end

      private def collect_integrity_check(packages : Array(Package)) : JSON::Any?
        try_collect("integrity") do
          entries = [] of JSON::Any

          packages.each do |pkg|
            expected = pkg.checksum
            verified = false
            reason = "no checksum in lock"

            if expected
              if pkg.installed?
                actual = pkg.compute_checksum
                if actual
                  if actual == expected
                    verified = true
                    reason = "checksum match"
                  else
                    reason = "checksum mismatch"
                  end
                else
                  reason = "could not compute checksum"
                end
              else
                reason = "not installed"
              end
            end

            entry = JSON.parse({
              name:     pkg.name,
              version:  pkg.version.to_s,
              verified: verified,
              reason:   reason,
            }.to_json)
            entries << entry
          end

          all_verified = entries.all? do |e|
            e["verified"].as_bool || e["reason"].as_s == "no checksum in lock"
          end

          JSON.parse({
            all_verified: all_verified,
            dependencies: entries,
          }.to_json)
        end
      end

      private def run_subcommand(args : Array(String)) : JSON::Any?
        output = IO::Memory.new
        error = IO::Memory.new
        # Try shards-alpha first (our binary name)
        status = Process.run(
          "shards-alpha", args,
          output: output, error: error, chdir: path
        )
        if status.success?
          # Extract JSON from combined output
          text = output.to_s
          if start = text.index('{') || text.index('[')
            JSON.parse(text[start..])
          else
            nil
          end
        else
          nil
        end
      rescue
        nil
      end

      private def compute_summary(packages : Array(Package), root_spec : Shards::Spec, sections : SectionData) : Summary
        direct_deps = root_spec.dependencies.size
        total_deps = packages.size
        transitive_deps = [total_deps - direct_deps, 0].max

        vuln_counts = extract_vulnerability_counts(sections.vulnerability_audit)
        license_status = extract_section_status(sections.license_audit)
        policy_status = extract_section_status(sections.policy_compliance)
        integrity_ok = extract_integrity_status(sections.integrity)

        overall = determine_overall_status(vuln_counts, license_status, policy_status, integrity_ok)

        Summary.new(
          total_dependencies: total_deps,
          direct_dependencies: direct_deps,
          transitive_dependencies: transitive_deps,
          vulnerabilities: vuln_counts,
          license_compliance: license_status,
          policy_compliance: policy_status,
          integrity_verified: integrity_ok,
          overall_status: overall
        )
      end

      private def extract_vulnerability_counts(data : JSON::Any?) : VulnerabilityCounts
        return VulnerabilityCounts.new unless data
        # Try to count vulnerabilities by severity from JSON data
        critical = high = medium = low = 0
        if vulns = data["vulnerabilities"]?
          vulns.as_a.each do |v|
            case v["severity"]?.try(&.as_s?.try(&.downcase))
            when "critical" then critical += 1
            when "high"     then high += 1
            when "medium"   then medium += 1
            when "low"      then low += 1
            end
          end
        end
        VulnerabilityCounts.new(critical, high, medium, low)
      rescue
        VulnerabilityCounts.new
      end

      private def extract_section_status(data : JSON::Any?) : String
        return "unavailable" unless data
        "pass"
      rescue
        "unavailable"
      end

      private def extract_integrity_status(data : JSON::Any?) : Bool?
        return nil unless data
        data["all_verified"]?.try(&.as_bool)
      rescue
        nil
      end

      private def determine_overall_status(vulns : VulnerabilityCounts, license : String, policy : String, integrity : Bool?) : String
        if vulns.critical > 0 || vulns.high > 0 || license == "fail" || policy == "fail"
          "fail"
        elsif vulns.medium > 0 || license == "warning" || policy == "warning" || integrity == false
          "action_required"
        else
          "pass"
        end
      end

      private def generate_uuid : String
        bytes = Random::Secure.random_bytes(16)
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        hex = bytes.hexstring
        "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
      end
    end
  end
end
