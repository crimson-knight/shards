# Phase 6: `shards compliance-report` -- Implementation Plan

## 1. Overview

### Purpose

The `compliance-report` command orchestrates all prior compliance phases (audit, licenses, policy, diff, SBOM, integrity) into a single unified report suitable for presenting to SOC2/ISO 27001 auditors. It produces machine-parseable JSON, professional HTML, or Markdown output covering every compliance question an auditor would ask.

### Architecture Summary

The implementation follows the established shards command pattern: a `Command` subclass in `src/commands/`, with supporting modules in a new `src/compliance/` directory. The command uses the existing `Command` base class from `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/command.cr`, which provides `spec`, `locks`, `path`, and lock file access.

### Compliance Standards Addressed

| Auditor Question | Data Source | SOC2 Criteria | ISO 27001 Control |
|---|---|---|---|
| What third-party dependencies do you use? | SBOM section | CC3.2 | A.8.9, A.8.30 |
| Are any of them vulnerable? | Vulnerability audit section | CC7.1, CC7.2 | A.8.8 |
| Are they all properly licensed? | License audit section | CC3.2 | A.5.19-5.22 |
| How do you control what enters the codebase? | Policy compliance section | CC6.1, CC8.1 | A.8.28 |
| How do you track dependency changes? | Change history section | CC8.1, CC7.2 | A.8.9 |
| Can you prove dependency integrity? | Integrity section | CC6.1 | A.8.9 |
| When was this last reviewed? | Attestation section | CC8.1 | A.5.19 |

---

## 2. Files to Create

### 2.1 `src/commands/compliance_report.cr` -- CLI Command

This file defines the `Commands::ComplianceReport` class. It follows the exact same pattern as `Commands::SBOM` in `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr`: it extends `Command`, receives parsed CLI arguments, and delegates to builder classes.

```crystal
# src/commands/compliance_report.cr
require "./command"
require "../compliance/report_builder"
require "../compliance/report_formatter"
require "json"

module Shards
  module Commands
    class ComplianceReport < Command
      struct Options
        property format : String = "json"
        property output : String? = nil
        property sections : Array(String) = ["all"]
        property since : String? = nil
        property reviewer : String? = nil
        property sign : Bool = false
        property template : String? = nil
      end

      def run(args : Array(String))
        options = parse_options(args)
        
        builder = Compliance::ReportBuilder.new(
          path: path,
          spec: spec,
          locks: locks,
          sections: options.sections,
          since: options.since,
          reviewer: options.reviewer
        )
        
        report_data = builder.build
        
        formatter = Compliance::ReportFormatter.new(
          format: options.format,
          template_path: options.template
        )
        
        output_path = options.output || default_output_path(options.format)
        formatter.write(report_data, output_path)
        
        if options.sign
          sign_report(output_path)
        end
        
        archive_report(output_path)
        
        Log.info { "Compliance report generated: #{output_path}" }
        print_summary(report_data)
      end

      private def parse_options(args : Array(String)) : Options
        # Parse --format=, --output=, --sections=, --since=,
        # --reviewer=, --sign, --template= from args array
        # (following the same pattern as SBOM arg parsing in cli.cr)
      end

      private def default_output_path(format : String) : String
        # Returns e.g. "my_app-compliance-report.json"
      end

      private def sign_report(path : String)
        # Calls `git gpg` to produce detached signature
      end

      private def archive_report(path : String)
        # Copies report to .shards/audit/reports/ with timestamp
      end

      private def print_summary(data : Compliance::ReportData)
        # Prints pass/fail summary to STDOUT with color
      end
    end
  end
end
```

**Key design decisions:**
- `Options` is a simple struct, not a class -- matches Crystal idioms for value types.
- `parse_options` follows the same `args.each` pattern used for SBOM in `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` lines 157-163.
- `run` signature takes `Array(String)` matching the MCP command pattern in `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/mcp.cr`.

### 2.2 `src/compliance/report_builder.cr` -- Report Orchestrator

This is the core orchestration module. It runs each sub-report collector and assembles them into a `ReportData` struct.

```crystal
# src/compliance/report_builder.cr
require "json"
require "../version"

module Shards
  module Compliance
    # Immutable data structure for the complete report
    struct ReportData
      property version : String = "1.0"
      property generated_at : Time = Time.utc
      property generator : String = "shards-alpha #{VERSION}"
      property project : ProjectInfo
      property reviewer : String?
      property signature : String?
      property summary : Summary
      property sections : SectionData
      property attestation : Attestation?
    end

    struct ProjectInfo
      property name : String
      property version : String
      property crystal_version : String
    end

    struct Summary
      property total_dependencies : Int32
      property direct_dependencies : Int32
      property transitive_dependencies : Int32
      property vulnerabilities : VulnerabilityCounts
      property license_compliance : String  # "pass" | "fail" | "warning" | "unavailable"
      property policy_compliance : String   # same
      property integrity_verified : Bool | Nil
      property overall_status : String      # "pass" | "action_required" | "fail"
    end

    struct VulnerabilityCounts
      property critical : Int32 = 0
      property high : Int32 = 0
      property medium : Int32 = 0
      property low : Int32 = 0
    end

    struct SectionData
      property sbom : JSON::Any?
      property vulnerability_audit : JSON::Any?
      property license_audit : JSON::Any?
      property policy_compliance : JSON::Any?
      property integrity : JSON::Any?
      property change_history : JSON::Any?
    end

    struct Attestation
      property reviewer : String
      property reviewed_at : Time
      property notes : String?
    end

    class ReportBuilder
      getter path : String
      getter spec : Spec
      getter locks : Lock
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
        errors = [] of String

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
          Attestation.new(
            reviewer: r,
            reviewed_at: Time.utc,
            notes: nil
          )
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

      # --- Section Collectors ---

      private def collect_sbom(root_spec, packages) : JSON::Any?
        # Generate SBOM in-memory using the same logic as Commands::SBOM
        # but capturing output to IO::Memory instead of file
        # Returns JSON::Any of the SPDX document
      end

      private def collect_vulnerability_audit : JSON::Any?
        # Attempt to run `shards audit --format=json` as subprocess
        # or call the audit command's internal API if available
        # Returns nil with warning if phase 1 is not available
      end

      private def collect_license_audit : JSON::Any?
        # Attempt to gather license data via shards licenses --format=json
        # Returns nil with warning if phase 3 is not available
      end

      private def collect_policy_compliance : JSON::Any?
        # Attempt to run shards policy --format=json
        # Returns nil with warning if phase 4 is not available
      end

      private def collect_integrity_check(packages) : JSON::Any?
        # Check shard.lock for checksum fields (phase 2)
        # Verify each dependency's checksum if present
        # Returns verification results
      end

      private def collect_change_history : JSON::Any?
        # Attempt to run shards diff --format=json --since=DATE
        # Returns nil with warning if phase 5 is not available
      end

      private def compute_summary(packages, root_spec, sections) : Summary
        # Compute counts and overall status from section data
      end

      # Graceful degradation helper
      private def try_collect(section_name : String, &) : JSON::Any?
        yield
      rescue ex
        Log.warn { "#{section_name} data unavailable: #{ex.message}" }
        nil
      end
    end
  end
end
```

**Key algorithms:**
- **Graceful degradation**: Each `collect_*` method is wrapped in `try_collect` which catches exceptions and returns `nil`, allowing the report to proceed with available sections.
- **Summary computation**: `compute_summary` examines each section's data, counts vulnerabilities by severity, checks license/policy pass/fail, and determines overall status as "pass" (all green), "action_required" (warnings), or "fail" (violations).
- **SBOM collection**: Reuses the exact logic from `Commands::SBOM#generate_spdx` but writes to `IO::Memory` instead of a file, then parses the result as `JSON::Any`.
- **Sub-command execution**: For phases 1, 3, 4, 5, the collector first checks if the command class exists (compiled in), and if so calls it directly. Otherwise, it attempts subprocess execution via `Process.run("shards audit ...")`.

### 2.3 `src/compliance/report_formatter.cr` -- Output Formatting

Handles JSON, HTML, and Markdown serialization of `ReportData`.

```crystal
# src/compliance/report_formatter.cr
require "json"
require "./html_template"

module Shards
  module Compliance
    class ReportFormatter
      getter format : String
      getter template_path : String?

      def initialize(@format, @template_path = nil)
      end

      def write(data : ReportData, output_path : String)
        Dir.mkdir_p(File.dirname(output_path)) unless File.dirname(output_path) == "."
        
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
            serialize_report(json, data)
          end
        end
      end

      private def serialize_report(json : JSON::Builder, data : ReportData)
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
              json.field "signature", data.signature if data.signature
              
              json.field "summary" do
                serialize_summary(json, data.summary)
              end
              
              json.field "sections" do
                serialize_sections(json, data.sections)
              end
              
              if att = data.attestation
                json.field "attestation" do
                  serialize_attestation(json, att)
                end
              end
            end
          end
        end
      end

      # ... serialize_summary, serialize_sections, serialize_attestation ...

      private def write_html(data : ReportData, path : String)
        template = if custom = template_path
          File.read(custom)
        else
          HtmlTemplate::DEFAULT
        end
        
        html = HtmlTemplate.render(template, data)
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
          render_summary_markdown(str, data.summary)
          
          # Render each available section
          render_sections_markdown(str, data.sections)
          
          if att = data.attestation
            render_attestation_markdown(str, att)
          end
        end
        
        File.write(path, md)
      end

      # ... render_summary_markdown, render_sections_markdown ...
    end
  end
end
```

**Data flow**: `ReportData` struct flows from `ReportBuilder` to `ReportFormatter`. JSON output uses Crystal's `JSON.build` (same pattern as SBOM). HTML output uses string interpolation into an embedded template. Markdown output uses `String.build`.

### 2.4 `src/compliance/html_template.cr` -- Embedded HTML Template

Contains the HTML template as a Crystal heredoc constant, embedded directly in the binary (no external file dependencies). Follows the same pattern as `Commands::Docs` in `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/docs.cr`, which embeds CSS and JS as heredoc constants (`CSS_VARIABLES`, `AI_BUTTONS_CSS`, `AI_BUTTONS_JS`).

```crystal
# src/compliance/html_template.cr

module Shards
  module Compliance
    module HtmlTemplate
      DEFAULT = <<-'HTML'
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Compliance Report — {{PROJECT_NAME}}</title>
        <style>
          /* Professional print-friendly CSS */
          /* ... full CSS with pass/fail badges, expandable sections,
               severity color coding, responsive layout ... */
        </style>
      </head>
      <body>
        <header>
          <h1>Supply Chain Compliance Report</h1>
          <div class="report-meta">
            <span class="project-name">{{PROJECT_NAME}} v{{PROJECT_VERSION}}</span>
            <span class="generated">{{GENERATED_AT}}</span>
            <span class="generator">{{GENERATOR}}</span>
          </div>
        </header>
        
        <section class="executive-summary">
          <h2>Executive Summary</h2>
          <div class="status-badges">{{SUMMARY_BADGES}}</div>
          <div class="metrics">{{SUMMARY_METRICS}}</div>
        </section>
        
        {{SECTION_SBOM}}
        {{SECTION_VULNERABILITY_AUDIT}}
        {{SECTION_LICENSE_AUDIT}}
        {{SECTION_POLICY_COMPLIANCE}}
        {{SECTION_INTEGRITY}}
        {{SECTION_CHANGE_HISTORY}}
        {{SECTION_ATTESTATION}}
        
        <footer>
          <p>Generated by {{GENERATOR}}</p>
        </footer>
        
        <script>
          // Expandable sections toggle
          document.querySelectorAll('.section-header').forEach(h => {
            h.addEventListener('click', () => {
              h.parentElement.classList.toggle('collapsed');
            });
          });
        </script>
      </body>
      </html>
      HTML

      def self.render(template : String, data : ReportData) : String
        # Replace {{PLACEHOLDERS}} with actual data
        # Build section HTML fragments from data.sections
        # Returns complete HTML string
      end

      private def self.render_summary_badges(summary : Summary) : String
        # Returns HTML for pass/fail/warning badges
      end

      private def self.render_section(title : String, data : JSON::Any?, 
                                       css_class : String) : String
        # Returns HTML for a collapsible section with content
        # Returns empty string if data is nil (graceful degradation)
      end

      private def self.severity_class(severity : String) : String
        # Maps severity levels to CSS classes for color coding
      end
    end
  end
end
```

**Design notes:**
- The template uses `{{PLACEHOLDER}}` syntax for simple string replacement (not ECR), keeping the template engine minimal.
- CSS is designed for both screen and print (`@media print` rules for clean PDF export).
- Sections are expandable/collapsible via vanilla JS click handlers.
- Color scheme: critical=red, high=orange, medium=yellow, low=blue, pass=green.

### 2.5 `spec/integration/compliance_report_spec.cr` -- Integration Tests

Follows the exact patterns from `/Users/crimsonknight/open_source_coding_projects/shards/spec/integration/sbom_spec.cr`.

```crystal
# spec/integration/compliance_report_spec.cr
require "./spec_helper"
require "json"

describe "compliance-report" do
  it "generates JSON report with all sections" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report"

      # Default output path
      File.exists?("test-compliance-report.json").should be_true
      json = JSON.parse(File.read("test-compliance-report.json"))

      json["report"]["version"].should eq("1.0")
      json["report"]["generator"].as_s.should start_with("shards-alpha")
      json["report"]["project"]["name"].should eq("test")
      
      # Summary exists
      summary = json["report"]["summary"]
      summary["total_dependencies"].as_i.should be >= 2
      summary["direct_dependencies"].as_i.should eq(2)
      summary["overall_status"].as_s.should_not be_empty
      
      # SBOM section present
      json["report"]["sections"]["sbom"]?.should_not be_nil
    end
  end

  it "generates HTML report" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report --format=html"

      File.exists?("test-compliance-report.html").should be_true
      content = File.read("test-compliance-report.html")
      content.should contain("<!DOCTYPE html>")
      content.should contain("Supply Chain Compliance Report")
      content.should contain("test")
    end
  end

  it "generates Markdown report" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report --format=markdown"

      File.exists?("test-compliance-report.md").should be_true
      content = File.read("test-compliance-report.md")
      content.should contain("# Compliance Report: test")
      content.should contain("Executive Summary")
    end
  end

  it "writes to custom output path" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report --output=custom-report.json"

      File.exists?("custom-report.json").should be_true
    end
  end

  it "includes only selected sections" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report --sections=sbom,integrity"

      json = JSON.parse(File.read("test-compliance-report.json"))
      json["report"]["sections"]["sbom"]?.should_not be_nil
      # Sections not requested should not appear
    end
  end

  it "includes reviewer in attestation" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report --reviewer=security-team@company.com"

      json = JSON.parse(File.read("test-compliance-report.json"))
      json["report"]["attestation"]["reviewer"].should eq("security-team@company.com")
      json["report"]["attestation"]["reviewed_at"]?.should_not be_nil
    end
  end

  it "degrades gracefully when phases unavailable" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      # No audit/licenses/policy/diff commands exist yet in this build
      # Report should still succeed with available data (SBOM, integrity)
      run "shards compliance-report"

      json = JSON.parse(File.read("test-compliance-report.json"))
      json["report"]["sections"]["sbom"]?.should_not be_nil
      json["report"]["summary"]["overall_status"]?.should_not be_nil
    end
  end

  it "produces valid parseable JSON" do
    metadata = {
      dependencies: {web: "*", orm: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report"

      content = File.read("test-compliance-report.json")
      json = JSON.parse(content) # Should not raise

      # Required top-level structure
      json["report"]?.should_not be_nil
      json["report"]["version"]?.should_not be_nil
      json["report"]["generated_at"]?.should_not be_nil
      json["report"]["generator"]?.should_not be_nil
      json["report"]["project"]?.should_not be_nil
      json["report"]["summary"]?.should_not be_nil
      json["report"]["sections"]?.should_not be_nil
    end
  end

  it "archives report to .shards/audit/reports/" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      run "shards compliance-report"

      Dir.exists?(".shards/audit/reports").should be_true
      archived = Dir.glob(".shards/audit/reports/*.json")
      archived.size.should be >= 1
    end
  end

  it "fails without lock file" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      ex = expect_raises(FailedCommand) { run "shards compliance-report --no-color" }
      ex.stdout.should contain("Missing shard.lock")
    end
  end

  it "fails with unknown format" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      ex = expect_raises(FailedCommand) { run "shards compliance-report --format=pdf --no-color" }
      ex.stdout.should contain("Unknown report format")
    end
  end
end
```

### 2.6 `spec/unit/compliance_report_spec.cr` -- Unit Tests

```crystal
# spec/unit/compliance_report_spec.cr
require "./spec_helper"
require "json"
require "../../src/version"
require "../../src/compliance/report_builder"
require "../../src/compliance/report_formatter"

module Shards
  describe Compliance::ReportBuilder do
    # Unit tests for summary computation, section collection, 
    # graceful degradation
  end

  describe Compliance::ReportFormatter do
    # Unit tests for JSON serialization, HTML rendering,
    # Markdown rendering, custom templates
  end

  describe Compliance::HtmlTemplate do
    # Unit tests for template rendering, placeholder substitution,
    # section omission when data is nil
  end
end
```

---

## 3. Files to Modify

### 3.1 `src/cli.cr`

**Location**: `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr`

**Change 1**: Add `"compliance-report"` to the `BUILTIN_COMMANDS` array (line 5-22):

```crystal
BUILTIN_COMMANDS = %w[
  build
  run
  check
  init
  install
  list
  lock
  outdated
  prune
  update
  version
  run-script
  ai-docs
  docs
  sbom
  mcp
  compliance-report
]
```

**Change 2**: Add help text in `display_help_and_exit` (after the `mcp` line, ~line 44):

```crystal
          compliance-report [<options>]                 - Generate supply chain compliance report.
```

**Change 3**: Add the `when "compliance-report"` case in the command dispatch block (after the `sbom` case, ~line 164):

```crystal
when "compliance-report"
  Commands::ComplianceReport.run(
    path,
    args[1..-1]
  )
```

This follows the exact same dispatch pattern as `MCP` and `AIDocs` commands, which accept the raw args array.

---

## 4. Data Flow Architecture

```
User runs: shards compliance-report --format=html --reviewer=alice

  cli.cr
    |
    v
  Commands::ComplianceReport#run(args)
    |-- parse_options(args) -> Options struct
    |
    v
  Compliance::ReportBuilder#build
    |-- collect_sbom()        -> generates SPDX JSON in-memory
    |-- collect_vulnerability_audit() -> runs audit (or nil if unavailable)
    |-- collect_license_audit()       -> runs licenses (or nil if unavailable)  
    |-- collect_policy_compliance()   -> runs policy (or nil if unavailable)
    |-- collect_integrity_check()     -> verifies checksums from shard.lock
    |-- collect_change_history()      -> runs diff (or nil if unavailable)
    |-- compute_summary()    -> aggregates all section results
    |
    v
  ReportData (struct with all report data)
    |
    v
  Compliance::ReportFormatter#write(data, path)
    |-- write_json() / write_html() / write_markdown()
    |
    v
  Output file written
    |
    v
  archive_report() -> copies to .shards/audit/reports/
  sign_report()    -> optional GPG signing
  print_summary()  -> colored terminal output
```

---

## 5. Detailed Type Definitions

All types live under `Shards::Compliance` module.

```crystal
module Shards::Compliance
  # The complete report data structure
  struct ReportData
    property version : String
    property generated_at : Time
    property generator : String
    property project : ProjectInfo
    property reviewer : String?
    property signature : String?
    property summary : Summary
    property sections : SectionData
    property attestation : Attestation?
  end

  struct ProjectInfo
    property name : String
    property version : String
    property crystal_version : String
  end

  struct Summary
    property total_dependencies : Int32
    property direct_dependencies : Int32
    property transitive_dependencies : Int32
    property vulnerabilities : VulnerabilityCounts
    property license_compliance : String
    property policy_compliance : String
    property integrity_verified : Bool?
    property overall_status : String
  end

  struct VulnerabilityCounts
    property critical : Int32
    property high : Int32
    property medium : Int32
    property low : Int32
  end

  struct SectionData
    property sbom : JSON::Any?
    property vulnerability_audit : JSON::Any?
    property license_audit : JSON::Any?
    property policy_compliance : JSON::Any?
    property integrity : JSON::Any?
    property change_history : JSON::Any?
  end

  struct Attestation
    property reviewer : String
    property reviewed_at : Time
    property notes : String?
  end

  # Represents a single dependency in the integrity check
  struct IntegrityEntry
    property name : String
    property version : String
    property expected_checksum : String?
    property actual_checksum : String?
    property verified : Bool
    property reason : String?  # e.g. "checksum match", "no checksum in lock", "mismatch"
  end
end
```

---

## 6. Key Algorithms

### 6.1 SBOM Collection (In-Memory)

The SBOM section reuses the SPDX generation logic from `Commands::SBOM`. Rather than duplicating 100+ lines, the implementation should extract the SPDX generation into a shared method or call SBOM with an `IO::Memory`:

```crystal
private def collect_sbom(root_spec, packages) : JSON::Any?
  try_collect("sbom") do
    io = IO::Memory.new
    dep_graph = build_dependency_graph(packages)
    
    JSON.build(io, indent: 2) do |json|
      # ... Same SPDX generation logic as Commands::SBOM#generate_spdx
      # but writing to io instead of a file
    end
    
    JSON.parse(io.to_s)
  end
end
```

**Alternative approach (preferred)**: Create a shared `SBOMGenerator` module in `src/compliance/` or refactor `Commands::SBOM` to accept an `IO` parameter. The refactoring approach is cleaner but requires modifying the existing SBOM command.

### 6.2 Sub-Command Execution with Graceful Degradation

For phases that may not exist in the current build:

```crystal
private def collect_vulnerability_audit : JSON::Any?
  try_collect("vulnerability_audit") do
    output = IO::Memory.new
    error = IO::Memory.new
    
    status = Process.run(
      "shards audit --format=json",
      shell: true,
      output: output,
      error: error,
      chdir: path
    )
    
    if status.success?
      JSON.parse(output.to_s)
    else
      Log.warn { "Vulnerability audit unavailable: #{error.to_s.lines.first?}" }
      nil
    end
  end
end
```

The `try_collect` wrapper catches all exceptions:

```crystal
private def try_collect(section_name : String, &) : JSON::Any?
  begin
    yield
  rescue ex : Exception
    Log.warn { "#{section_name} section unavailable: #{ex.message}" }
    nil
  end
end
```

### 6.3 Integrity Verification

Checks the lock file for checksum fields (Phase 2 addition) and verifies them:

```crystal
private def collect_integrity_check(packages : Array(Package)) : JSON::Any?
  try_collect("integrity") do
    entries = packages.map do |pkg|
      # Check if shard.lock has a checksum for this package
      # Phase 2 adds content_hash to the lock format
      expected = nil  # Would come from lock file extension
      actual = compute_content_hash(pkg) if pkg.installed?
      
      verified = if expected && actual
        expected == actual
      elsif expected.nil?
        nil  # No checksum available
      else
        false
      end
      
      IntegrityEntry.new(
        name: pkg.name,
        version: pkg.version.to_s,
        expected_checksum: expected,
        actual_checksum: actual,
        verified: verified || false,
        reason: integrity_reason(expected, actual)
      )
    end
    
    all_verified = entries.all? { |e| e.verified || e.expected_checksum.nil? }
    
    JSON.parse(JSON.build do |json|
      json.object do
        json.field "all_verified", all_verified
        json.field "dependencies" do
          json.array do
            entries.each do |entry|
              json.object do
                json.field "name", entry.name
                json.field "version", entry.version
                json.field "verified", entry.verified
                json.field "reason", entry.reason if entry.reason
              end
            end
          end
        end
      end
    end)
  end
end
```

### 6.4 Summary Computation

```crystal
private def compute_summary(packages, root_spec, sections) : Summary
  direct_deps = root_spec.dependencies.size
  total_deps = packages.size
  transitive_deps = total_deps - direct_deps
  
  vuln_counts = extract_vulnerability_counts(sections.vulnerability_audit)
  license_status = extract_compliance_status(sections.license_audit, "license_compliance")
  policy_status = extract_compliance_status(sections.policy_compliance, "policy_compliance")
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

private def determine_overall_status(vulns, license, policy, integrity) : String
  if vulns.critical > 0 || vulns.high > 0 || license == "fail" || policy == "fail"
    "fail"
  elsif vulns.medium > 0 || license == "warning" || policy == "warning" || integrity == false
    "action_required"
  else
    "pass"
  end
end
```

### 6.5 Report Archiving

```crystal
private def archive_report(output_path : String)
  archive_dir = File.join(path, ".shards", "audit", "reports")
  Dir.mkdir_p(archive_dir)
  
  timestamp = Time.utc.to_s("%Y%m%d-%H%M%S")
  ext = File.extname(output_path)
  basename = File.basename(output_path, ext)
  archive_path = File.join(archive_dir, "#{basename}-#{timestamp}#{ext}")
  
  FileUtils.cp(output_path, archive_path)
  Log.debug { "Archived report to #{archive_path}" }
end
```

### 6.6 GPG Signing

```crystal
private def sign_report(path : String)
  output = IO::Memory.new
  error = IO::Memory.new
  
  status = Process.run(
    "git",
    ["gpg-sign", "--detach-sign", "--armor", "--output", "#{path}.sig", path],
    output: output,
    error: error
  )
  
  unless status.success?
    # Fallback to gpg directly
    status = Process.run(
      "gpg",
      ["--detach-sign", "--armor", "--output", "#{path}.sig", path],
      output: output,
      error: error
    )
  end
  
  if status.success?
    Log.info { "Signed report: #{path}.sig" }
  else
    Log.warn { "Could not sign report: #{error.to_s.lines.first?}" }
  end
end
```

---

## 7. Error Handling Approach

| Error Scenario | Handling |
|---|---|
| No `shard.lock` file | Raises `Shards::Error` from `Command#locks` (existing behavior) |
| No `shard.yml` file | Raises `Shards::Error` from `Command#spec` (existing behavior) |
| Sub-command (audit/licenses/etc) not available | `try_collect` catches, logs warning, returns `nil` |
| Sub-command fails with non-zero exit | Caught by `try_collect`, section marked as unavailable |
| Unknown format specified | Raises `Shards::Error` with message (caught by top-level handler in `shards.cr`) |
| Custom template file not found | Raises `Shards::Error` with descriptive message |
| GPG signing fails | Logs warning, continues without signature |
| Output directory not writable | Propagates `File::Error` (caught by top-level handler) |
| Archive directory creation fails | Logs warning, continues |

---

## 8. HTML Template Design Specification

The HTML template provides a professional, audit-ready report with these design elements:

**Layout:**
- Fixed header with project name and report metadata
- Executive summary section with status badges at the top
- Collapsible sections for each audit area
- Print-optimized layout with page breaks between sections

**Status Badges:**
- Green badge: "PASS" -- all checks passed
- Yellow badge: "ACTION REQUIRED" -- warnings present
- Red badge: "FAIL" -- violations found
- Gray badge: "UNAVAILABLE" -- check could not be run

**Severity Colors:**
- Critical: `#dc3545` (red)
- High: `#fd7e14` (orange)
- Medium: `#ffc107` (yellow)
- Low: `#17a2b8` (blue/info)
- Pass: `#28a745` (green)

**Sections:**
1. **Executive Summary** -- Always visible, dependency counts, overall status
2. **Software Bill of Materials** -- Expandable dependency table with version, license, source
3. **Vulnerability Audit** -- Findings table with severity, CVE, affected package
4. **License Audit** -- License inventory with policy compliance status
5. **Policy Compliance** -- Rules checked, violations, warnings
6. **Dependency Integrity** -- Checksum verification results per package
7. **Change History** -- Timeline of dependency changes since specified date
8. **Attestation** -- Reviewer info, timestamp, notes

**Print considerations:**
- `@media print` rules expand all collapsed sections
- Remove interactive elements (expand/collapse buttons)
- Use `page-break-before` for major sections
- Black-and-white friendly with text-based status indicators alongside colors

---

## 9. Implementation Sequence

### Step 1: Create the data structures
File: `src/compliance/report_builder.cr`
- Define all structs: `ReportData`, `ProjectInfo`, `Summary`, `VulnerabilityCounts`, `SectionData`, `Attestation`, `IntegrityEntry`
- Implement `ReportBuilder` with `#build` and all `collect_*` methods
- Implement `compute_summary` and `determine_overall_status`

### Step 2: Create the JSON formatter
File: `src/compliance/report_formatter.cr`
- Implement `write_json` with `JSON.build`
- Implement all `serialize_*` private methods

### Step 3: Create the HTML template
File: `src/compliance/html_template.cr`
- Define `DEFAULT` template constant with full HTML/CSS/JS
- Implement `HtmlTemplate.render` with placeholder substitution
- Implement section rendering helpers

### Step 4: Complete the formatter
File: `src/compliance/report_formatter.cr`
- Implement `write_html` using `HtmlTemplate`
- Implement `write_markdown` with all section renderers

### Step 5: Create the CLI command
File: `src/commands/compliance_report.cr`
- Implement `ComplianceReport` class extending `Command`
- Implement `parse_options`, `run`, `sign_report`, `archive_report`, `print_summary`

### Step 6: Register in CLI
File: `src/cli.cr`
- Add to `BUILTIN_COMMANDS`
- Add help text
- Add dispatch case

### Step 7: Write integration tests
File: `spec/integration/compliance_report_spec.cr`

### Step 8: Write unit tests
File: `spec/unit/compliance_report_spec.cr`

---

## 10. Success Criteria

1. **JSON output is valid and machine-parseable**: `JSON.parse` succeeds on the output; the structure matches the specification with `report.version`, `report.summary`, `report.sections`
2. **HTML output opens in a browser**: The file is valid HTML5, renders correctly, and all sections are present and interactive
3. **Markdown output is properly formatted**: Headers, tables, and code blocks render correctly in any Markdown viewer
4. **SBOM section contains complete dependency data**: All locked dependencies appear with name, version, license, and source
5. **Graceful degradation works**: When audit/licenses/policy/diff commands are unavailable, the report still generates successfully with available sections and appropriate warnings
6. **Report archiving works**: A copy is saved to `.shards/audit/reports/` with a timestamp
7. **Section filtering works**: `--sections=sbom,integrity` produces a report with only those sections
8. **Reviewer attestation works**: `--reviewer=NAME` populates the attestation section with timestamp
9. **Custom output path works**: `--output=PATH` writes to the specified location
10. **Error cases are handled**: Missing lock file, unknown format, and missing template all produce clear error messages
11. **Summary computation is correct**: Overall status accurately reflects the aggregate of all section results
12. **All integration tests pass**: The test suite in `spec/integration/compliance_report_spec.cr` passes

---

## 11. Validation Steps

### Step 1: Generate JSON report with all sections
```bash
cd /path/to/project
shards install
shards compliance-report
# Verify: test-compliance-report.json exists
# Verify: JSON.parse succeeds
# Verify: report.sections.sbom is populated
# Verify: report.summary.total_dependencies matches lock file
```

### Step 2: Generate HTML report
```bash
shards compliance-report --format=html
open test-compliance-report.html
# Verify: renders in browser
# Verify: executive summary shows badges
# Verify: sections are expandable
# Verify: print preview shows clean layout
```

### Step 3: Generate Markdown report
```bash
shards compliance-report --format=markdown
# Verify: properly formatted Markdown
# Verify: headers, tables, and code blocks render in viewer
```

### Step 4: Verify all sections contain data
```bash
shards compliance-report --format=json
# Parse JSON and check each section key:
# - sections.sbom: contains spdxVersion or equivalent
# - sections.vulnerability_audit: contains findings array (or null if unavailable)
# - sections.license_audit: contains findings (or null if unavailable)
# - sections.policy_compliance: contains rules_checked (or null if unavailable)
# - sections.integrity: contains all_verified and dependencies array
# - sections.change_history: contains entries (or null if unavailable)
```

### Step 5: Verify graceful degradation
```bash
# In a project where audit/licenses/policy are not yet implemented:
shards compliance-report
# Verify: command succeeds (exit 0)
# Verify: sbom and integrity sections are populated
# Verify: unavailable sections show as null in JSON
# Verify: summary.overall_status still computes from available data
# Verify: log output shows warnings about unavailable sections
```

### Step 6: Verify JSON is externally parseable
```bash
shards compliance-report
# Use external JSON tools:
cat test-compliance-report.json | python3 -m json.tool  # Should succeed
cat test-compliance-report.json | jq '.report.summary'   # Should show summary
```

### Step 7: Verify HTML prints cleanly
```bash
shards compliance-report --format=html
# Open in Chrome, Ctrl+P
# Verify: all sections expanded in print view
# Verify: no interactive elements in print
# Verify: status badges readable in black and white
```

### Step 8: Verify section filtering
```bash
shards compliance-report --sections=sbom,integrity
# Verify: only sbom and integrity sections present
# Verify: other sections are null/absent
```

### Step 9: Verify reviewer attestation
```bash
shards compliance-report --reviewer="Jane Doe <jane@company.com>"
# Verify: report.attestation.reviewer matches
# Verify: report.attestation.reviewed_at is valid timestamp
```

### Step 10: Verify report archiving
```bash
shards compliance-report
ls .shards/audit/reports/
# Verify: timestamped copy exists
```

### Step 11: Run full test suite
```bash
crystal spec spec/integration/compliance_report_spec.cr
crystal spec spec/unit/compliance_report_spec.cr
# Verify: all tests pass
```

---

## 12. Potential Challenges and Mitigations

| Challenge | Mitigation |
|---|---|
| SBOM generation logic is duplicated from `Commands::SBOM` | Extract shared SPDX generation into a module or accept `IO` parameter in SBOM command; alternatively, call SBOM command as subprocess writing to temp file |
| Sub-commands from phases 1-5 may not exist yet | All collection methods use `try_collect` with `Process.run` and subprocess fallback; report works with zero sub-commands available |
| HTML template is large and embedded in binary | Acceptable trade-off for zero external dependencies; Crystal heredoc compiles into the binary efficiently |
| GPG key may not be configured | `sign_report` logs a warning and continues; signing is optional |
| Crystal struct limitations (no default values in some contexts) | Use class with property declarations and explicit initializers where needed |
| Test isolation -- sub-commands not available in test harness | Integration tests verify the command runs successfully and produces valid output; section content from unavailable commands is tested as `nil` |

---

### Critical Files for Implementation
- `/Users/crimsonknight/open_source_coding_projects/shards/src/compliance/report_builder.cr` - Core orchestration logic; defines all data structs and section collectors
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/compliance_report.cr` - CLI command entry point; arg parsing and report lifecycle
- `/Users/crimsonknight/open_source_coding_projects/shards/src/compliance/report_formatter.cr` - JSON/HTML/Markdown output serialization
- `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` - Must be modified to register the new command in BUILTIN_COMMANDS and dispatch
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` - Reference implementation for SPDX generation logic to reuse in SBOM section