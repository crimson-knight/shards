# Implementation Plan: `shards licenses` -- License Compliance Command

## Document: `docs/plans/03-shards-licenses.md`

Below is the full contents of the plan document that should be written to `/Users/crimsonknight/open_source_coding_projects/shards/docs/plans/03-shards-licenses.md`.

---

## 1. Overview

This plan adds a `shards licenses` command to shards-alpha that provides license auditing, compliance checking, and reporting for all project dependencies. It reads license declarations from `shard.yml` files, optionally scans LICENSE files for detection, validates SPDX identifiers, evaluates policy rules, and produces reports in multiple formats.

## 2. Codebase Context

### 2.1 How licenses are currently handled

The `Spec` class at `/Users/crimsonknight/open_source_coding_projects/shards/src/spec.cr` line 123 declares `getter license : String?`. It is parsed at line 148-149 from the YAML `license` key. The `Spec#license_url` method at line 265-273 generates an SPDX URL when the license is not already a URL. The SBOM command at `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` reads `pkg.spec.license` for each dependency and writes it as `licenseDeclared` / `licenseConcluded` in SPDX output, using `"NOASSERTION"` when the license is nil or empty (line 131).

### 2.2 How dependencies are enumerated

The `Command` base class at `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/command.cr` provides:
- `spec` -- the root project `Spec` from `shard.yml`
- `locks` -- the `Lock` object from `shard.lock`, which contains `shards : Array(Package)`
- Each `Package` has a `spec` getter that reads the installed `shard.yml` from `lib/<name>/shard.yml`
- `Package#install_path` returns `File.join(Shards.install_path, name)` where `Shards.install_path` defaults to `lib/`

### 2.3 Command registration pattern

In `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr`:
- Commands are listed in `BUILTIN_COMMANDS` array (line 5-22)
- Help text is listed inline (line 29-44)
- Command dispatch uses a `case` statement with argument parsing per-command (line 95-167)
- The SBOM command pattern (lines 153-164) is the most similar to what we need: parse `--format=`, `--output=` etc from the args array, then call `Commands::SBOM.run(path, ...)`.

### 2.4 Test patterns

Unit tests at `/Users/crimsonknight/open_source_coding_projects/shards/spec/unit/sbom_spec.cr` use `create_git_repository`, set up directories manually with `Dir.cd(tmp_path)`, create `shard.yml` / `shard.lock` / `.shards.info`, instantiate the command directly (`Commands::SBOM.new("project_dir")`), call `run(...)`, and verify output.

Integration tests at `/Users/crimsonknight/open_source_coding_projects/shards/spec/integration/sbom_spec.cr` use `with_shard(metadata)` to set up projects, run CLI commands via `run "shards sbom"`, and verify file output.

## 3. Architecture Design

### 3.1 File Layout

```
src/
  spdx.cr                  -- SPDX identifier database and expression parsing
  license_scanner.cr        -- LICENSE file detection and heuristic matching
  license_policy.cr         -- Policy loading, evaluation, and result types
  commands/
    licenses.cr             -- CLI command implementation

spec/
  unit/
    spdx_spec.cr            -- SPDX parsing tests
    license_scanner_spec.cr -- License file detection tests
    license_policy_spec.cr  -- Policy evaluation tests
  integration/
    licenses_spec.cr        -- End-to-end CLI tests
```

Modification to existing files:
- `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` -- Add `"licenses"` to `BUILTIN_COMMANDS`, add help text, add dispatch case.

### 3.2 Module Dependency Graph

```
commands/licenses.cr
  requires: spdx.cr, license_scanner.cr, license_policy.cr, command.cr, json

license_policy.cr
  requires: spdx.cr

license_scanner.cr
  requires: spdx.cr

spdx.cr
  requires: (none -- standalone)
```

## 4. Detailed File Specifications

### 4.1 `src/spdx.cr`

This file provides SPDX license identifier validation and expression parsing.

```
module Shards
  module SPDX

    # Known SPDX license identifiers with metadata
    # Each entry: id, name, is_osi_approved, is_fsf_libre, category
    enum Category
      Permissive
      WeakCopyleft
      StrongCopyleft
      NonCommercial
      PublicDomain
      Proprietary
      Unknown
    end

    record LicenseInfo,
      id : String,
      name : String,
      osi_approved : Bool,
      category : Category

    # Hardcoded database of common SPDX identifiers
    # Approximately 50-60 most commonly used licenses
    LICENSES : Hash(String, LicenseInfo)

    # --- Expression AST ---
    # SPDX expressions follow this grammar:
    #   expression = simple-expression / compound-expression
    #   simple-expression = license-id ["+" ] / "LicenseRef-" idstring
    #   compound-expression = simple-expression ("AND" simple-expression)*
    #                       | simple-expression ("OR" simple-expression)*
    #   with-expression = simple-expression "WITH" exception-id

    abstract class Expression
      abstract def license_ids : Array(String)
      abstract def satisfied_by?(allowed : Set(String)) : Bool
    end

    class SimpleExpression < Expression
      getter id : String
      getter or_later : Bool  # the "+" suffix

      def initialize(@id, @or_later = false)
      end

      def license_ids : Array(String)
        [id]
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        allowed.includes?(id)
      end
    end

    class WithExpression < Expression
      getter license : SimpleExpression
      getter exception : String

      def initialize(@license, @exception)
      end

      def license_ids : Array(String)
        license.license_ids
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        license.satisfied_by?(allowed)
      end
    end

    class AndExpression < Expression
      getter left : Expression
      getter right : Expression

      def initialize(@left, @right)
      end

      def license_ids : Array(String)
        left.license_ids + right.license_ids
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        left.satisfied_by?(allowed) && right.satisfied_by?(allowed)
      end
    end

    class OrExpression < Expression
      getter left : Expression
      getter right : Expression

      def initialize(@left, @right)
      end

      def license_ids : Array(String)
        left.license_ids + right.license_ids
      end

      def satisfied_by?(allowed : Set(String)) : Bool
        left.satisfied_by?(allowed) || right.satisfied_by?(allowed)
      end
    end

    # --- Parser ---
    # Parses SPDX expression strings into Expression AST
    class Parser
      def self.parse(input : String) : Expression
        # Tokenize: split on whitespace, recognize AND, OR, WITH, (, ), +
        # Recursive descent parser:
        #   parse_or -> parse_and -> parse_atom
        #   parse_atom: handles SimpleExpression, WithExpression, parenthesized groups
      end
    end

    # --- Validators ---

    def self.valid_id?(id : String) : Bool
      LICENSES.has_key?(id) || id.starts_with?("LicenseRef-")
    end

    def self.lookup(id : String) : LicenseInfo?
      LICENSES[id]?
    end

    def self.category_for(id : String) : Category
      LICENSES[id]?.try(&.category) || Category::Unknown
    end

    def self.parse(expression : String) : Expression
      Parser.parse(expression)
    end
  end
end
```

**Key design decisions:**
- Hardcode ~50-60 most common licenses rather than loading from an external file. This keeps the binary self-contained and avoids runtime I/O. The list covers all licenses commonly found in Crystal shards.
- Expression parser supports compound expressions but keeps it simple: no operator precedence beyond AND binding tighter than OR (per SPDX spec). Parentheses handle explicit grouping.
- Category classification uses an enum with values matching the requirement: Permissive, WeakCopyleft, StrongCopyleft, NonCommercial, PublicDomain, Proprietary, Unknown.

**License database entries (representative subset):**

| ID | Category |
|---|---|
| MIT | Permissive |
| Apache-2.0 | Permissive |
| BSD-2-Clause | Permissive |
| BSD-3-Clause | Permissive |
| ISC | Permissive |
| Zlib | Permissive |
| Unlicense | PublicDomain |
| 0BSD | Permissive |
| WTFPL | Permissive |
| CC0-1.0 | PublicDomain |
| MPL-2.0 | WeakCopyleft |
| LGPL-2.1-only | WeakCopyleft |
| LGPL-2.1-or-later | WeakCopyleft |
| LGPL-3.0-only | WeakCopyleft |
| LGPL-3.0-or-later | WeakCopyleft |
| EPL-2.0 | WeakCopyleft |
| GPL-2.0-only | StrongCopyleft |
| GPL-2.0-or-later | StrongCopyleft |
| GPL-3.0-only | StrongCopyleft |
| GPL-3.0-or-later | StrongCopyleft |
| AGPL-3.0-only | StrongCopyleft |
| AGPL-3.0-or-later | StrongCopyleft |
| SSPL-1.0 | Proprietary |
| BSL-1.1 | Proprietary |
| CC-BY-NC-4.0 | NonCommercial |
| CC-BY-NC-SA-4.0 | NonCommercial |

### 4.2 `src/license_scanner.cr`

This file scans installed dependency directories for LICENSE files and attempts heuristic license identification.

```
module Shards
  class LicenseScanner

    # License file name patterns, ordered by priority
    LICENSE_FILE_PATTERNS = [
      "LICENSE",
      "LICENSE.md",
      "LICENSE.txt",
      "LICENCE",
      "LICENCE.md",
      "LICENCE.txt",
      "LICENSE-MIT",
      "LICENSE-APACHE",
      "COPYING",
      "COPYING.md",
      "COPYING.txt",
    ]

    # Heuristic patterns to detect license type from file content
    # Each pattern: regex to match, corresponding SPDX ID
    LICENSE_PATTERNS = [
      {/MIT License|Permission is hereby granted, free of charge/i, "MIT"},
      {/Apache License.*Version 2\.0/i, "Apache-2.0"},
      {/BSD 2-Clause|Redistribution and use.*two conditions/i, "BSD-2-Clause"},
      {/BSD 3-Clause|Redistribution and use.*three conditions/i, "BSD-3-Clause"},
      {/ISC License/i, "ISC"},
      {/Mozilla Public License.*2\.0/i, "MPL-2.0"},
      {/GNU General Public License.*version 3/i, "GPL-3.0-only"},
      {/GNU General Public License.*version 2/i, "GPL-2.0-only"},
      {/GNU Lesser General Public License.*version 3/i, "LGPL-3.0-only"},
      {/GNU Lesser General Public License.*version 2\.1/i, "LGPL-2.1-only"},
      {/GNU Affero General Public License.*version 3/i, "AGPL-3.0-only"},
      {/The Unlicense|unlicense\.org/i, "Unlicense"},
      {/Creative Commons Zero|CC0 1\.0/i, "CC0-1.0"},
      {/zlib License/i, "Zlib"},
    ]

    # Scan result for a single dependency
    record ScanResult,
      license_file_path : String?,          # Path to detected license file (relative)
      detected_license : String?,           # SPDX ID detected from file content
      detection_confidence : Symbol          # :high, :medium, :low, :none

    # Scan the install path of a package for license files
    def self.scan(install_path : String) : ScanResult
      # 1. Look for license files in order of LICENSE_FILE_PATTERNS
      # 2. If found, read content and attempt heuristic match
      # 3. Return ScanResult with findings
    end

    # Find the first matching license file in the given directory
    def self.find_license_file(dir : String) : String?
      LICENSE_FILE_PATTERNS.each do |pattern|
        path = File.join(dir, pattern)
        return path if File.exists?(path)
        # Also try case-insensitive on case-sensitive filesystems
      end
      nil
    end

    # Detect SPDX license ID from file content using heuristic patterns
    def self.detect_license(content : String) : {String?, Symbol}
      LICENSE_PATTERNS.each do |regex, spdx_id|
        if content.matches?(regex)
          return {spdx_id, :high}
        end
      end
      {nil, :none}
    end
  end
end
```

**Key design decisions:**
- Scanner is stateless with class methods for simplicity.
- Detection confidence levels allow UI to indicate reliability. `:high` means a clear license header was found. `:medium` would be used for partial matches. `:low` for very fuzzy matches. `:none` for no match.
- File detection stops at the first match in priority order, which is the standard convention.

### 4.3 `src/license_policy.cr`

This file handles loading, evaluating, and reporting on license policies.

```
module Shards
  class LicensePolicy

    DEFAULT_POLICY_FILENAME = ".shards-license-policy.yml"

    # Policy configuration loaded from YAML
    record PolicyConfig,
      allowed : Set(String),
      denied : Set(String),
      require_license : Bool,
      overrides : Hash(String, Override)

    record Override,
      license : String,
      reason : String?

    # Per-dependency evaluation result
    enum Verdict
      Allowed
      Denied
      Unlicensed
      Unknown     # Not in allowed or denied list
      Overridden  # Manual override applied
    end

    record DependencyResult,
      name : String,
      version : String,
      declared_license : String?,     # From shard.yml
      detected_license : String?,     # From LICENSE file scan
      effective_license : String?,    # Final resolved license
      license_source : Symbol,        # :declared, :detected, :override, :none
      verdict : Verdict,
      override_reason : String?,      # Reason from policy override
      spdx_valid : Bool,              # Whether the license is a valid SPDX id/expression
      category : SPDX::Category,
      scan_result : LicenseScanner::ScanResult?

    record PolicyReport,
      root_name : String,
      root_version : String,
      root_license : String?,
      dependencies : Array(DependencyResult),
      policy_used : Bool,
      summary : Summary

    record Summary,
      total : Int32,
      allowed : Int32,
      denied : Int32,
      unlicensed : Int32,
      unknown : Int32,
      overridden : Int32

    # --- Loading ---

    def self.load_policy(path : String?) : PolicyConfig?
      actual_path = path || DEFAULT_POLICY_FILENAME
      return nil unless File.exists?(actual_path)

      yaml = YAML.parse(File.read(actual_path))
      policy = yaml["policy"]?
      return nil unless policy

      allowed = Set(String).new
      if list = policy["allowed"]?.try(&.as_a?)
        list.each { |v| allowed << v.as_s }
      end

      denied = Set(String).new
      if list = policy["denied"]?.try(&.as_a?)
        list.each { |v| denied << v.as_s }
      end

      require_license = policy["require_license"]?.try(&.as_bool?) || false

      overrides = Hash(String, Override).new
      if ovr = policy["overrides"]?.try(&.as_h?)
        ovr.each do |name, config|
          license = config["license"]?.try(&.as_s?) || ""
          reason = config["reason"]?.try(&.as_s?)
          overrides[name] = Override.new(license, reason)
        end
      end

      PolicyConfig.new(allowed, denied, require_license, overrides)
    end

    # --- Evaluation ---

    def self.evaluate(
      packages : Array(Package),
      root_spec : Spec,
      policy : PolicyConfig?,
      detect : Bool = false
    ) : PolicyReport
      results = packages.map do |pkg|
        evaluate_package(pkg, policy, detect)
      end

      summary = compute_summary(results)
      PolicyReport.new(
        root_name: root_spec.name,
        root_version: root_spec.version.to_s,
        root_license: root_spec.license,
        dependencies: results,
        policy_used: !policy.nil?,
        summary: summary
      )
    end

    private def self.evaluate_package(
      pkg : Package,
      policy : PolicyConfig?,
      detect : Bool
    ) : DependencyResult
      declared = pkg.spec.license
      declared = nil if declared.try(&.empty?)

      # Check for policy override first
      if policy && (ovr = policy.overrides[pkg.name]?)
        return build_result(pkg, declared, nil,
          effective: ovr.license,
          source: :override,
          verdict: Verdict::Overridden,
          override_reason: ovr.reason,
          scan_result: nil)
      end

      # Scan for LICENSE file if requested
      scan_result : LicenseScanner::ScanResult? = nil
      detected : String? = nil
      if detect && pkg.installed?
        scan_result = LicenseScanner.scan(pkg.install_path)
        detected = scan_result.detected_license
      end

      # Determine effective license
      effective = declared || detected
      source = if declared
                 :declared
               elsif detected
                 :detected
               else
                 :none
               end

      # Determine verdict
      verdict = if effective.nil?
                  Verdict::Unlicensed
                elsif policy
                  evaluate_against_policy(effective, policy)
                else
                  Verdict::Unknown
                end

      build_result(pkg, declared, detected,
        effective: effective,
        source: source,
        verdict: verdict,
        override_reason: nil,
        scan_result: scan_result)
    end

    private def self.evaluate_against_policy(
      license : String,
      policy : PolicyConfig
    ) : Verdict
      # Parse the license as an SPDX expression
      begin
        expr = SPDX.parse(license)
        ids = expr.license_ids

        # Check denied first (deny takes priority)
        ids.each do |id|
          return Verdict::Denied if policy.denied.includes?(id)
        end

        # Check if expression is satisfiable by allowed set
        if policy.allowed.empty?
          # No allowlist = everything not denied is allowed
          Verdict::Allowed
        elsif expr.satisfied_by?(policy.allowed)
          Verdict::Allowed
        else
          Verdict::Unknown
        end
      rescue
        # Unparseable expression -- check as simple string
        if policy.denied.includes?(license)
          Verdict::Denied
        elsif policy.allowed.includes?(license)
          Verdict::Allowed
        else
          Verdict::Unknown
        end
      end
    end

    private def self.build_result(...) : DependencyResult
      # Construct DependencyResult with SPDX validation and category lookup
    end

    private def self.compute_summary(results : Array(DependencyResult)) : Summary
      Summary.new(
        total: results.size,
        allowed: results.count(&.verdict.allowed?),
        denied: results.count(&.verdict.denied?),
        unlicensed: results.count(&.verdict.unlicensed?),
        unknown: results.count(&.verdict.unknown?),
        overridden: results.count(&.verdict.overridden?)
      )
    end
  end
end
```

**Key design decisions:**
- Denied licenses take priority over allowed. If a compound expression contains both an allowed and a denied license, the denied verdict wins.
- When no policy file is present, the command still works as a reporting tool -- all licenses show as `Unknown` verdict but the license listing is still useful.
- Override mechanism lets users manually specify licenses for shards that lack declarations, with a reason field for audit trail.
- SPDX expression evaluation for OR expressions: if either side is satisfied by the allowed set, the whole expression is allowed. For AND expressions, both sides must be satisfied.

### 4.4 `src/commands/licenses.cr`

```
require "./command"
require "../spdx"
require "../license_scanner"
require "../license_policy"
require "json"

module Shards
  module Commands
    class Licenses < Command

      def run(
        format : String = "terminal",
        policy_path : String? = nil,
        check : Bool = false,
        include_dev : Bool = false,
        detect : Bool = false
      )
        packages = locks.shards

        # Optionally include dev dependencies
        # (dev deps are in the lock file but we filter to only
        # direct + transitive production deps by default)
        # For now, locks.shards contains all locked packages.
        # The include_dev flag controls whether we filter.

        root_spec = spec
        policy = LicensePolicy.load_policy(policy_path)

        report = LicensePolicy.evaluate(packages, root_spec, policy, detect)

        case format
        when "terminal"
          render_terminal(report)
        when "json"
          render_json(report)
        when "csv"
          render_csv(report)
        when "markdown"
          render_markdown(report)
        else
          raise Error.new("Unknown format: #{format}. Use: terminal, json, csv, markdown")
        end

        # In --check mode, exit non-zero if violations found
        if check && (report.summary.denied > 0 || report.summary.unlicensed > 0)
          denied_count = report.summary.denied
          unlicensed_count = report.summary.unlicensed
          msgs = [] of String
          msgs << "#{denied_count} denied" if denied_count > 0
          msgs << "#{unlicensed_count} unlicensed" if unlicensed_count > 0
          raise Error.new("License policy violations: #{msgs.join(", ")}")
        end
      end

      # --- Terminal Output ---
      private def render_terminal(report : LicensePolicy::PolicyReport)
        puts "License Report for #{report.root_name} (#{report.root_version})"
        puts "Root license: #{report.root_license || "not declared"}"
        puts ""

        if report.dependencies.empty?
          puts "No dependencies."
          return
        end

        # Calculate column widths
        max_name = report.dependencies.max_of(&.name.size)
        max_name = {max_name, 4}.max  # "Name" header
        max_ver = report.dependencies.max_of(&.version.size)
        max_ver = {max_ver, 7}.max  # "Version"
        max_lic = report.dependencies.max_of { |d| (d.effective_license || "none").size }
        max_lic = {max_lic, 7}.max  # "License"

        # Header
        header = String.build do |s|
          s << "  " << "Name".ljust(max_name)
          s << "  " << "Version".ljust(max_ver)
          s << "  " << "License".ljust(max_lic)
          s << "  " << "Source"
          s << "  " << "Status" if report.policy_used
        end
        puts header
        puts "  " + "-" * (header.size - 2)

        # Rows
        report.dependencies.sort_by(&.name).each do |dep|
          line = String.build do |s|
            s << "  " << dep.name.ljust(max_name)
            s << "  " << dep.version.ljust(max_ver)
            s << "  " << (dep.effective_license || "none").ljust(max_lic)
            s << "  " << dep.license_source.to_s
            if report.policy_used
              s << "  " << verdict_label(dep.verdict)
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

          # Show override reason if applicable
          if dep.override_reason
            puts "    override reason: #{dep.override_reason}"
          end

          # Show SPDX validity warning
          unless dep.spdx_valid || dep.effective_license.nil?
            puts "    warning: not a valid SPDX identifier"
          end
        end

        # Summary
        puts ""
        puts "Summary: #{report.summary.total} dependencies"
        if report.policy_used
          parts = [] of String
          parts << "#{report.summary.allowed} allowed" if report.summary.allowed > 0
          parts << "#{report.summary.denied} denied" if report.summary.denied > 0
          parts << "#{report.summary.unlicensed} unlicensed" if report.summary.unlicensed > 0
          parts << "#{report.summary.unknown} unknown" if report.summary.unknown > 0
          parts << "#{report.summary.overridden} overridden" if report.summary.overridden > 0
          puts "  #{parts.join(", ")}"
        end
      end

      private def verdict_label(verdict : LicensePolicy::Verdict) : String
        case verdict
        when .allowed?    then "ALLOWED"
        when .denied?     then "DENIED"
        when .unlicensed? then "UNLICENSED"
        when .unknown?    then "UNKNOWN"
        when .overridden? then "OVERRIDDEN"
        else                   verdict.to_s
        end
      end

      # --- JSON Output ---
      private def render_json(report : LicensePolicy::PolicyReport)
        JSON.build(STDOUT, indent: 2) do |json|
          json.object do
            json.field "project", report.root_name
            json.field "version", report.root_version
            json.field "license", report.root_license

            json.field "dependencies" do
              json.array do
                report.dependencies.sort_by(&.name).each do |dep|
                  json.object do
                    json.field "name", dep.name
                    json.field "version", dep.version
                    json.field "declared_license", dep.declared_license
                    json.field "detected_license", dep.detected_license
                    json.field "effective_license", dep.effective_license
                    json.field "license_source", dep.license_source.to_s
                    json.field "spdx_valid", dep.spdx_valid
                    json.field "category", dep.category.to_s
                    json.field "verdict", dep.verdict.to_s.downcase
                    if dep.override_reason
                      json.field "override_reason", dep.override_reason
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
        puts  # trailing newline
      end

      # --- CSV Output ---
      private def render_csv(report : LicensePolicy::PolicyReport)
        puts "Name,Version,Declared License,Detected License,Effective License,Source,SPDX Valid,Category,Verdict"
        report.dependencies.sort_by(&.name).each do |dep|
          fields = [
            csv_escape(dep.name),
            csv_escape(dep.version),
            csv_escape(dep.declared_license || ""),
            csv_escape(dep.detected_license || ""),
            csv_escape(dep.effective_license || ""),
            dep.license_source.to_s,
            dep.spdx_valid.to_s,
            dep.category.to_s,
            dep.verdict.to_s.downcase,
          ]
          puts fields.join(",")
        end
      end

      private def csv_escape(value : String) : String
        if value.includes?(",") || value.includes?("\"") || value.includes?("\n")
          "\"#{value.gsub("\"", "\"\"")}\""
        else
          value
        end
      end

      # --- Markdown Output ---
      private def render_markdown(report : LicensePolicy::PolicyReport)
        puts "# License Report: #{report.root_name} #{report.root_version}"
        puts ""
        puts "Root license: #{report.root_license || "not declared"}"
        puts ""
        puts "| Dependency | Version | License | Source | Category | Status |"
        puts "|---|---|---|---|---|---|"

        report.dependencies.sort_by(&.name).each do |dep|
          verdict_str = report.policy_used ? dep.verdict.to_s.downcase : "-"
          puts "| #{dep.name} | #{dep.version} | #{dep.effective_license || "none"} | #{dep.license_source} | #{dep.category.to_s.downcase} | #{verdict_str} |"
        end

        puts ""
        puts "**Total:** #{report.summary.total} dependencies"
        if report.policy_used
          puts ""
          puts "| Verdict | Count |"
          puts "|---|---|"
          puts "| Allowed | #{report.summary.allowed} |"
          puts "| Denied | #{report.summary.denied} |"
          puts "| Unlicensed | #{report.summary.unlicensed} |"
          puts "| Unknown | #{report.summary.unknown} |"
          puts "| Overridden | #{report.summary.overridden} |"
        end
      end
    end
  end
end
```

**Key design decisions:**
- The command follows the same `run` signature pattern as SBOM: `def run(format, policy_path, check, include_dev, detect)`.
- Terminal output uses colorized output when `Shards.colors?` is true, matching the existing logger pattern.
- `--check` mode raises `Shards::Error` which the CLI catches and exits with code 1, matching all other command error handling.
- JSON output writes to STDOUT (not a file) since license reports are typically piped or consumed by tools, unlike SBOMs which produce artifacts.

### 4.5 Modifications to `src/cli.cr`

**Changes required:**

1. Add `"licenses"` to `BUILTIN_COMMANDS` array (after `"sbom"`).

2. Add help text line:
```
          licenses [options]                     - List dependency licenses and check compliance.
```

3. Add case branch in the command dispatch (after the `"sbom"` case):
```crystal
when "licenses"
  lic_format = "terminal"
  lic_policy = nil : String?
  lic_check = false
  lic_include_dev = false
  lic_detect = false
  args[1..-1].each do |arg|
    case arg
    when .starts_with?("--format=") then lic_format = arg.split("=", 2).last
    when .starts_with?("--policy=") then lic_policy = arg.split("=", 2).last
    when "--check"                  then lic_check = true
    when "--include-dev"            then lic_include_dev = true
    when "--detect"                 then lic_detect = true
    end
  end
  Commands::Licenses.run(path, lic_format, lic_policy, lic_check, lic_include_dev, lic_detect)
```

This follows the exact same pattern used by the SBOM command at lines 153-164 of `cli.cr`.

## 5. Data Flow

```
CLI (cli.cr)
  |
  v  parse args
Commands::Licenses.run(path, format, policy_path, check, include_dev, detect)
  |
  |--- locks.shards -> Array(Package)
  |--- spec -> root Spec
  |
  |--- LicensePolicy.load_policy(policy_path) -> PolicyConfig?
  |
  |--- LicensePolicy.evaluate(packages, root_spec, policy, detect)
  |      |
  |      |--- for each Package:
  |      |      |--- pkg.spec.license -> declared license
  |      |      |--- if detect: LicenseScanner.scan(pkg.install_path) -> ScanResult
  |      |      |--- check policy overrides
  |      |      |--- SPDX.valid_id?(license) -> Bool
  |      |      |--- SPDX.category_for(license) -> Category
  |      |      |--- evaluate_against_policy(license, policy) -> Verdict
  |      |      |      |--- SPDX.parse(license) -> Expression
  |      |      |      |--- Expression#satisfied_by?(allowed) -> Bool
  |      |      |      |--- check denied list
  |      |      v
  |      |      DependencyResult
  |      |
  |      v
  |      PolicyReport (with Summary)
  |
  v  render by format
  render_terminal / render_json / render_csv / render_markdown
  |
  v  if --check
  raise Error if violations found (exit 1)
```

## 6. Error Handling

| Error Condition | Behavior |
|---|---|
| Missing shard.lock | Raise `Error.new("Missing shard.lock. Please run 'shards install'")` -- inherited from `Command#locks` |
| Missing shard.yml | Raise `Error.new("Missing shard.yml. Please run 'shards init'")` -- inherited from `Command#spec` |
| Invalid policy YAML | Raise `Error.new("Invalid license policy file: <path>: <parse error>")` |
| Unknown output format | Raise `Error.new("Unknown format: <f>. Use: terminal, json, csv, markdown")` |
| Policy violations with --check | Raise `Error.new("License policy violations: N denied, M unlicensed")` |
| Unparseable SPDX expression | Log warning, treat as simple string for policy checking, mark `spdx_valid: false` |
| Unreadable LICENSE file | Log debug message, return `ScanResult` with `detected_license: nil` |
| Dependency not installed | Use `pkg.spec` which falls back to resolver (same as SBOM behavior); `LicenseScanner.scan` skips if not `pkg.installed?` |

All errors use `Shards::Error` which the CLI catches at `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` lines 229-231 and exits with code 1.

## 7. Test Plan

### 7.1 `spec/unit/spdx_spec.cr`

```crystal
require "./spec_helper"
require "../../src/spdx"

module Shards
  describe SPDX do
    describe ".valid_id?" do
      it "recognizes standard SPDX identifiers" do
        SPDX.valid_id?("MIT").should be_true
        SPDX.valid_id?("Apache-2.0").should be_true
        SPDX.valid_id?("GPL-3.0-only").should be_true
      end

      it "rejects unknown identifiers" do
        SPDX.valid_id?("NotALicense").should be_false
      end

      it "accepts LicenseRef- prefixed identifiers" do
        SPDX.valid_id?("LicenseRef-custom").should be_true
      end
    end

    describe ".lookup" do
      it "returns license info for known IDs" do
        info = SPDX.lookup("MIT")
        info.should_not be_nil
        info.not_nil!.category.should eq(SPDX::Category::Permissive)
        info.not_nil!.osi_approved.should be_true
      end

      it "returns nil for unknown IDs" do
        SPDX.lookup("Unknown-1.0").should be_nil
      end
    end

    describe ".category_for" do
      it "returns Permissive for MIT" do
        SPDX.category_for("MIT").should eq(SPDX::Category::Permissive)
      end

      it "returns StrongCopyleft for GPL-3.0-only" do
        SPDX.category_for("GPL-3.0-only").should eq(SPDX::Category::StrongCopyleft)
      end

      it "returns Unknown for unrecognized licenses" do
        SPDX.category_for("FooBar").should eq(SPDX::Category::Unknown)
      end
    end

    describe "Parser" do
      it "parses simple license ID" do
        expr = SPDX.parse("MIT")
        expr.should be_a(SPDX::SimpleExpression)
        expr.license_ids.should eq(["MIT"])
      end

      it "parses OR expression" do
        expr = SPDX.parse("MIT OR Apache-2.0")
        expr.should be_a(SPDX::OrExpression)
        expr.license_ids.sort.should eq(["Apache-2.0", "MIT"])
      end

      it "parses AND expression" do
        expr = SPDX.parse("MIT AND Apache-2.0")
        expr.should be_a(SPDX::AndExpression)
        expr.license_ids.sort.should eq(["Apache-2.0", "MIT"])
      end

      it "parses WITH expression" do
        expr = SPDX.parse("GPL-3.0-only WITH Classpath-exception-2.0")
        expr.should be_a(SPDX::WithExpression)
        expr.license_ids.should eq(["GPL-3.0-only"])
      end

      it "parses parenthesized expressions" do
        expr = SPDX.parse("(MIT OR Apache-2.0) AND BSD-3-Clause")
        expr.should be_a(SPDX::AndExpression)
        expr.license_ids.sort.should eq(["Apache-2.0", "BSD-3-Clause", "MIT"])
      end

      it "handles or-later suffix" do
        expr = SPDX.parse("GPL-3.0+")
        expr.should be_a(SPDX::SimpleExpression)
        expr.as(SPDX::SimpleExpression).or_later.should be_true
      end
    end

    describe "Expression#satisfied_by?" do
      it "simple expression satisfied when in allowed set" do
        expr = SPDX.parse("MIT")
        expr.satisfied_by?(Set{"MIT"}).should be_true
        expr.satisfied_by?(Set{"Apache-2.0"}).should be_false
      end

      it "OR expression satisfied when either side is allowed" do
        expr = SPDX.parse("MIT OR GPL-3.0-only")
        expr.satisfied_by?(Set{"MIT"}).should be_true
        expr.satisfied_by?(Set{"GPL-3.0-only"}).should be_true
        expr.satisfied_by?(Set{"Apache-2.0"}).should be_false
      end

      it "AND expression requires both sides allowed" do
        expr = SPDX.parse("MIT AND Apache-2.0")
        expr.satisfied_by?(Set{"MIT", "Apache-2.0"}).should be_true
        expr.satisfied_by?(Set{"MIT"}).should be_false
      end
    end
  end
end
```

### 7.2 `spec/unit/license_scanner_spec.cr`

Tests for license file detection and heuristic matching. Would use `Dir.cd(tmp_path)` to create temporary directories with LICENSE files of various formats and content, then call `LicenseScanner.scan` and verify results.

Key test cases:
- Detects MIT from a standard MIT LICENSE file
- Detects Apache-2.0 from LICENSE-APACHE
- Returns nil when no license file exists
- Handles LICENCE (British spelling)
- Handles LICENSE.md with markdown formatting
- Returns correct confidence levels

### 7.3 `spec/unit/license_policy_spec.cr`

Tests for policy loading and evaluation. Key test cases:
- Loading valid policy YAML
- Loading policy with overrides
- Missing policy file returns nil (no-policy mode)
- Evaluating allowed licenses
- Evaluating denied licenses
- Denied takes priority over allowed in compound expressions
- Override applies for specific packages
- Unlicensed verdict when no license found and require_license is true
- Summary computation

### 7.4 `spec/integration/licenses_spec.cr`

End-to-end tests following the pattern from `spec/integration/sbom_spec.cr`:

```crystal
require "./spec_helper"
require "json"

describe "licenses" do
  it "lists dependency licenses" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses"
      output.should contain("License Report")
      output.should contain("web")
    end
  end

  it "outputs JSON format" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --format=json"
      json = JSON.parse(output)
      json["project"].should eq("test")
      json["dependencies"].as_a.size.should be >= 1
    end
  end

  it "outputs CSV format" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --format=csv"
      output.should contain("Name,Version")
      output.should contain("web")
    end
  end

  it "outputs markdown format" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      output = run "shards licenses --format=markdown"
      output.should contain("# License Report")
      output.should contain("| Dependency |")
    end
  end

  it "fails with --check when policy has violations" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      # Create policy that denies everything
      File.write ".shards-license-policy.yml", <<-YAML
      policy:
        denied:
          - MIT
          - Apache-2.0
        require_license: true
      YAML
      ex = expect_raises(FailedCommand) { run "shards licenses --check --no-color" }
      ex.stdout.should contain("License policy violations")
    end
  end

  it "passes with --check when all licenses allowed" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      File.write ".shards-license-policy.yml", <<-YAML
      policy:
        allowed:
          - MIT
          - Apache-2.0
          - BSD-2-Clause
          - BSD-3-Clause
          - ISC
      YAML
      run "shards licenses --check"
    end
  end

  it "fails without lock file" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      ex = expect_raises(FailedCommand) { run "shards licenses --no-color" }
      ex.stdout.should contain("Missing shard.lock")
    end
  end

  it "fails with unknown format" do
    metadata = {
      dependencies: {web: "*"},
    }
    with_shard(metadata) do
      run "shards install"
      ex = expect_raises(FailedCommand) { run "shards licenses --format=xml --no-color" }
      ex.stdout.should contain("Unknown format")
    end
  end
end
```

## 8. Implementation Sequence

### Phase 1: Core SPDX Module
1. Create `src/spdx.cr` with the license database, Category enum, Expression AST, and Parser.
2. Create `spec/unit/spdx_spec.cr` with comprehensive tests.
3. Verify: `crystal spec spec/unit/spdx_spec.cr`

### Phase 2: License Scanner
1. Create `src/license_scanner.cr` with file detection and heuristic matching.
2. Create `spec/unit/license_scanner_spec.cr`.
3. Verify: `crystal spec spec/unit/license_scanner_spec.cr`

### Phase 3: License Policy
1. Create `src/license_policy.cr` with policy loading and evaluation.
2. Create `spec/unit/license_policy_spec.cr`.
3. Verify: `crystal spec spec/unit/license_policy_spec.cr`

### Phase 4: Command Implementation
1. Create `src/commands/licenses.cr` with all four output renderers.
2. Modify `src/cli.cr` to register the command.
3. Create `spec/integration/licenses_spec.cr`.
4. Verify: `crystal spec spec/integration/licenses_spec.cr`

### Phase 5: Polish and Edge Cases
1. Test with real-world Crystal projects that have diverse dependency trees.
2. Ensure `--detect` mode works with PATH dependencies (symlinked dirs).
3. Test policy override workflow.
4. Run `crystal tool format` on all new files.
5. Full test suite: `crystal spec`

## 9. Success Criteria

1. **Basic listing works**: `shards licenses` produces a formatted table showing all locked dependencies with their declared licenses.
2. **JSON output is valid**: `shards licenses --format=json | jq .` succeeds and contains all required fields.
3. **CSV output is valid**: Output can be imported into a spreadsheet.
4. **Markdown output is valid**: Output renders correctly as a markdown table.
5. **Policy allow works**: With a policy file listing only `MIT`, a project with all MIT dependencies passes `--check`.
6. **Policy deny works**: With a policy file denying `GPL-3.0-only`, a project with a GPL dependency fails `--check` with exit code 1.
7. **Override works**: A dependency with no license can be overridden in the policy file and shows as `OVERRIDDEN`.
8. **File detection works**: With `--detect`, a dependency that has no `license` in `shard.yml` but has a `LICENSE` file with MIT content is detected as MIT.
9. **SPDX validation works**: Invalid SPDX identifiers are flagged with a warning.
10. **SPDX expressions work**: `MIT OR Apache-2.0` is correctly evaluated against allow/deny lists.
11. **No regressions**: The full existing test suite (`crystal spec`) passes.
12. **Exit codes**: `--check` exits 0 on pass, 1 on failure.

## 10. Validation Steps

1. Build the project: `crystal build src/shards.cr -o bin/shards`
2. In a Crystal project with dependencies:
   ```
   shards licenses                          # Should show table
   shards licenses --format=json            # Should show valid JSON
   shards licenses --format=csv             # Should show CSV
   shards licenses --format=markdown        # Should show markdown table
   shards licenses --detect                 # Should scan LICENSE files
   ```
3. Create `.shards-license-policy.yml` with allowed list:
   ```
   shards licenses --check                  # Should pass
   ```
4. Add a dependency's license to the denied list:
   ```
   shards licenses --check                  # Should fail with exit 1
   ```
5. Add an override for a dependency:
   ```
   shards licenses                          # Should show OVERRIDDEN status
   ```
6. Run the full test suite:
   ```
   crystal spec
   ```

## 11. Potential Challenges

1. **License field is optional in shard.yml**: Many Crystal shards do not declare a license. The `--detect` flag mitigates this but heuristic detection is imperfect. The override mechanism provides a manual escape hatch.

2. **SPDX expression complexity**: The full SPDX expression spec allows nested parentheses and combinations. The parser needs to handle this correctly. Testing with real-world expressions from the SPDX ecosystem is important.

3. **Dev dependency filtering**: The current lock file does not distinguish between production and development transitive dependencies. The `include_dev` flag may need to rely on the root `shard.yml`'s `development_dependencies` list and trace only those subtrees. For the initial implementation, a simple approach is acceptable: if `--include-dev` is not set, we skip packages that are only reachable through `development_dependencies`. However, this requires building a dependency graph similar to what the SBOM command does. A simpler initial approach: always show all locked packages (since they are all needed at some point) and note in the output which are dev-only. This can be refined later.

4. **Crystal compile time**: Adding three new source files with a license database hash map should have negligible impact on compile time since it is all static data.

---

### Critical Files for Implementation
- `/Users/crimsonknight/open_source_coding_projects/shards/src/spdx.cr` - New file: SPDX identifier database, expression parser, and category classification (foundational module)
- `/Users/crimsonknight/open_source_coding_projects/shards/src/license_policy.cr` - New file: Policy loading, evaluation engine, and report types (core business logic)
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/licenses.cr` - New file: CLI command with all four output renderers (user-facing interface)
- `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` - Existing file to modify: register "licenses" in BUILTIN_COMMANDS, add help text, add dispatch case (lines 5-22 and 95-167)
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` - Existing file: primary reference pattern for how commands enumerate packages, read license fields, and produce structured output