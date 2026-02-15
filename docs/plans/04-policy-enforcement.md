## Implementation Plan: Dependency Policy Enforcement for shards-alpha

### 1. Architecture Overview

The policy enforcement system introduces four new source files and modifies three existing ones. It follows the established patterns in the codebase: YAML parsing uses `YAML::PullParser` (consistent with `Spec`, `Override`, `PostinstallInfo`), commands extend `Command` (consistent with `SBOM`, `MCP`), and the reporting layer separates data from presentation (consistent with how logging is handled via `Shards::Log`).

The design separates concerns into:
- **Policy** (`src/policy.cr`): Data model and YAML parsing for `.shards-policy.yml`
- **PolicyChecker** (`src/policy_checker.cr`): Evaluation engine that checks packages against policy rules
- **PolicyReport** (`src/policy_report.cr`): Violation aggregation, severity classification, and output formatting
- **Commands::Policy** (`src/commands/policy.cr`): CLI entry point with subcommands

### 2. Data Model and YAML Parsing: `src/policy.cr`

This file defines the policy data structures and parses `.shards-policy.yml`. It follows the same pattern as `src/override.cr` and `src/spec.cr`: a top-level class with a `from_file`/`from_yaml` class method that uses `YAML::PullParser`.

**Filename constant** to add to `src/config.cr`:
```crystal
POLICY_FILENAME = ".shards-policy.yml"
```

**Complete structure:**

```crystal
# src/policy.cr
require "./ext/yaml"
require "./config"
require "./errors"

module Shards
  class Policy
    CURRENT_VERSION = "1"

    getter version : String
    getter sources : SourceRules
    getter dependencies : DependencyRules
    getter freshness : FreshnessRules
    getter security : SecurityRules
    getter custom : Array(CustomRule)

    def initialize(
      @version = CURRENT_VERSION,
      @sources = SourceRules.new,
      @dependencies = DependencyRules.new,
      @freshness = FreshnessRules.new,
      @security = SecurityRules.new,
      @custom = [] of CustomRule
    )
    end

    # --- Nested data structures ---

    class SourceRules
      getter allowed_hosts : Array(String)
      getter allowed_orgs : Hash(String, Array(String))
      getter? deny_path_dependencies : Bool

      def initialize(
        @allowed_hosts = [] of String,
        @allowed_orgs = {} of String => Array(String),
        @deny_path_dependencies = false
      )
      end

      def empty?
        allowed_hosts.empty? && allowed_orgs.empty? && !deny_path_dependencies?
      end
    end

    class DependencyRules
      getter blocked : Array(BlockedDep)
      getter minimum_versions : Hash(String, String)

      def initialize(
        @blocked = [] of BlockedDep,
        @minimum_versions = {} of String => String
      )
      end
    end

    class BlockedDep
      getter name : String
      getter reason : String?

      def initialize(@name, @reason = nil)
      end
    end

    class FreshnessRules
      getter max_age_days : Int32?
      getter require_recent_commit : Int32?

      def initialize(
        @max_age_days = nil,
        @require_recent_commit = nil
      )
      end
    end

    class SecurityRules
      getter? require_license : Bool
      getter? require_checksum : Bool
      getter? block_postinstall : Bool
      getter? audit_postinstall : Bool

      def initialize(
        @require_license = false,
        @require_checksum = false,
        @block_postinstall = false,
        @audit_postinstall = false
      )
      end
    end

    class CustomRule
      getter name : String
      getter pattern : Regex
      getter action : Symbol  # :warn or :block
      getter reason : String?

      def initialize(@name, pattern_str : String, action_str : String, @reason = nil)
        @pattern = Regex.new(pattern_str, Regex::Options::IGNORE_CASE)
        @action = action_str == "block" ? :block : :warn
      end
    end

    # --- Parsing (mirrors Override.from_file / Override.from_yaml) ---

    def self.from_file(path : String) : self
      raise Error.new("Missing #{File.basename(path)}") unless File.exists?(path)
      from_yaml(File.read(path), path)
    end

    def self.from_yaml(input : String, filename = POLICY_FILENAME) : self
      parser = YAML::PullParser.new(input)
      parser.read_stream do
        if parser.kind.stream_end?
          return new
        end
        parser.read_document do
          new(parser)
        end
      end
    rescue ex : YAML::ParseException
      raise ParseError.new(ex.message, input, filename, ex.line_number, ex.column_number)
    ensure
      parser.close if parser
    end

    def initialize(pull : YAML::PullParser)
      # Default values
      @version = CURRENT_VERSION
      @sources = SourceRules.new
      @dependencies = DependencyRules.new
      @freshness = FreshnessRules.new
      @security = SecurityRules.new
      @custom = [] of CustomRule

      pull.each_in_mapping do
        case pull.read_scalar
        when "version"
          @version = pull.read_scalar
        when "rules"
          parse_rules(pull)
        else
          pull.skip
        end
      end
    end

    private def parse_rules(pull)
      pull.each_in_mapping do
        case pull.read_scalar
        when "sources"     then @sources = parse_sources(pull)
        when "dependencies" then @dependencies = parse_dependencies(pull)
        when "freshness"   then @freshness = parse_freshness(pull)
        when "security"    then @security = parse_security(pull)
        when "custom"      then @custom = parse_custom(pull)
        else                    pull.skip
        end
      end
    end

    # Each parse_* method reads nested YAML mappings/sequences
    # using pull.each_in_mapping / pull.each_in_sequence
    # following the same idiom used in Spec#initialize
  end
end
```

**Key parsing methods** (abbreviated, each follows the same `pull.each_in_mapping` pattern):

- `parse_sources`: reads `allowed_hosts` as a sequence, `allowed_orgs` as a mapping of host to sequence of org strings, `deny_path_dependencies` as a boolean scalar.
- `parse_dependencies`: reads `blocked` as a sequence of mappings (each with `name` and optional `reason`), `minimum_versions` as a mapping of name to version string.
- `parse_freshness`: reads `max_age_days` and `require_recent_commit` as integer scalars.
- `parse_security`: reads four boolean scalars.
- `parse_custom`: reads a sequence of mappings, each with `name`, `pattern`, `action`, and optional `reason`.

### 3. Policy Evaluation Engine: `src/policy_checker.cr`

This is the core logic. It takes a `Policy` and a list of `Package` objects (from the solver or lockfile) and produces a `PolicyReport`.

**Key design decisions:**
- The checker operates on `Array(Package)` which is the same type returned by `MolinilloSolver#solve` (line 97 of `src/molinillo_solver.cr`) and stored in `Lock#shards` (line 8 of `src/lock.cr`). This means it works identically whether called from `install`, `update`, or standalone `policy check`.
- Source origin extraction uses `Resolver#source` and checks `resolver.is_a?(PathResolver)`, exactly as `Commands::SBOM` does in its `download_location` and `generate_purl` helpers.
- Host extraction uses `URI.parse(resolver.source).host` which works because `GitResolver.normalize_key_source` normalizes all github/gitlab/bitbucket sources to full `https://` URLs (line 131 of `src/resolvers/git.cr`).
- Org extraction parses the URI path to get the first path component (owner), reusing the same approach as `SBOM#parse_owner_repo`.

```crystal
# src/policy_checker.cr
require "uri"
require "./policy"
require "./policy_report"
require "./package"
require "./resolvers/resolver"
require "./resolvers/path"

module Shards
  class PolicyChecker
    getter policy : Policy
    getter report : PolicyReport

    def initialize(@policy : Policy)
      @report = PolicyReport.new
    end

    # Main entry point: check all packages against all rules
    def check(packages : Array(Package)) : PolicyReport
      @report = PolicyReport.new

      packages.each do |package|
        check_blocked(package)
        check_sources(package)
        check_minimum_version(package)
        check_security(package)
        check_custom(package)
        # Freshness checks are warnings-only and require
        # spec metadata; they are best-effort
        check_freshness(package)
      end

      @report
    end

    private def check_blocked(package : Package)
      policy.dependencies.blocked.each do |blocked|
        if package.name == blocked.name
          reason = blocked.reason || "Blocked by policy"
          @report.add_violation(
            package: package.name,
            rule: "blocked_dependency",
            severity: PolicyReport::Severity::Error,
            message: "Dependency '#{package.name}' is blocked: #{reason}"
          )
        end
      end
    end

    private def check_sources(package : Package)
      return if policy.sources.empty?
      resolver = package.resolver

      # Check path dependency denial
      if resolver.is_a?(PathResolver)
        if policy.sources.deny_path_dependencies?
          @report.add_violation(
            package: package.name,
            rule: "deny_path_dependencies",
            severity: PolicyReport::Severity::Error,
            message: "Path dependencies are not allowed by policy: '#{package.name}' (#{resolver.source})"
          )
        end
        return  # Path deps don't have hosts/orgs to check
      end

      source = resolver.source
      host = extract_host(source)
      return unless host  # Can't determine host, skip

      # Check allowed_hosts (if list is non-empty, it's an allowlist)
      unless policy.sources.allowed_hosts.empty?
        unless policy.sources.allowed_hosts.includes?(host)
          @report.add_violation(
            package: package.name,
            rule: "allowed_hosts",
            severity: PolicyReport::Severity::Error,
            message: "Source host '#{host}' is not in the allowed hosts list for '#{package.name}'"
          )
          return  # No point checking org if host is blocked
        end
      end

      # Check allowed_orgs (if defined for this host)
      if orgs = policy.sources.allowed_orgs[host]?
        owner = extract_owner(source)
        if owner && !orgs.includes?(owner)
          @report.add_violation(
            package: package.name,
            rule: "allowed_orgs",
            severity: PolicyReport::Severity::Error,
            message: "Organization '#{owner}' on '#{host}' is not in the allowed orgs list for '#{package.name}'"
          )
        end
      end
    end

    private def check_minimum_version(package : Package)
      if min_pattern = policy.dependencies.minimum_versions[package.name]?
        req = VersionReq.new(min_pattern)
        unless Versions.matches?(package.version, req)
          @report.add_violation(
            package: package.name,
            rule: "minimum_version",
            severity: PolicyReport::Severity::Error,
            message: "Version #{package.version} of '#{package.name}' does not satisfy minimum version requirement '#{min_pattern}'"
          )
        end
      end
    end

    private def check_security(package : Package)
      sec = policy.security

      if sec.require_license?
        license = package.spec.license
        if license.nil? || license.empty?
          @report.add_violation(
            package: package.name,
            rule: "require_license",
            severity: PolicyReport::Severity::Warning,
            message: "Dependency '#{package.name}' has no license declared"
          )
        end
      end

      if sec.block_postinstall?
        if package.spec.scripts["postinstall"]?
          @report.add_violation(
            package: package.name,
            rule: "block_postinstall",
            severity: PolicyReport::Severity::Error,
            message: "Dependency '#{package.name}' has a postinstall script, which is blocked by policy"
          )
        end
      elsif sec.audit_postinstall?
        if package.spec.scripts["postinstall"]?
          @report.add_violation(
            package: package.name,
            rule: "audit_postinstall",
            severity: PolicyReport::Severity::Warning,
            message: "Dependency '#{package.name}' has a postinstall script that should be reviewed: #{package.spec.scripts["postinstall"]}"
          )
        end
      end

      # require_checksum is a placeholder for Phase 2
      # (checksum pinning is not yet implemented in shards)
    end

    private def check_freshness(package : Package)
      # Freshness checks are inherently warnings because shards
      # doesn't track release dates. These checks are best-effort
      # based on available metadata. For now, these generate
      # informational warnings that can be acted upon externally.
      # Full freshness checking would require querying the
      # resolver for tag dates, which is expensive. Mark as TODO
      # for Phase 2 with caching.
    end

    private def check_custom(package : Package)
      policy.custom.each do |rule|
        if rule.pattern.matches?(package.name)
          severity = rule.action == :block ?
            PolicyReport::Severity::Error :
            PolicyReport::Severity::Warning
          reason = rule.reason || "Matched custom rule '#{rule.name}'"
          @report.add_violation(
            package: package.name,
            rule: "custom:#{rule.name}",
            severity: severity,
            message: "Dependency '#{package.name}' matched custom rule '#{rule.name}': #{reason}"
          )
        end
      end
    end

    # --- Host/owner extraction helpers ---

    private def extract_host(source : String) : String?
      URI.parse(source).host.try(&.downcase)
    rescue
      nil
    end

    private def extract_owner(source : String) : String?
      uri = URI.parse(source)
      path = uri.path
      return nil unless path
      path = path.lchop('/')
      path = path.rchop(".git") if path.ends_with?(".git")
      parts = path.split('/')
      parts.first? if parts.size >= 2
    rescue
      nil
    end
  end
end
```

**Why this approach works for all resolver types:**
- `GitResolver` normalizes github/gitlab/bitbucket/codeberg sources to `https://host.com/owner/repo.git` in `normalize_key_source` (lines 114-137 of `src/resolvers/git.cr`), so `URI.parse` reliably extracts host and path.
- `PathResolver` is detected via `is_a?(PathResolver)` and handled separately.
- `FossilResolver` and `HgResolver` use raw source URLs that `URI.parse` handles.

### 4. Violation Reporting: `src/policy_report.cr`

```crystal
# src/policy_report.cr
require "json"

module Shards
  class PolicyReport
    enum Severity
      Error   # Blocks install/update
      Warning # Informational, can be promoted to error with --strict
    end

    record Violation,
      package : String,
      rule : String,
      severity : Severity,
      message : String

    getter violations : Array(Violation)

    def initialize
      @violations = [] of Violation
    end

    def add_violation(package : String, rule : String, severity : Severity, message : String)
      @violations << Violation.new(
        package: package,
        rule: rule,
        severity: severity,
        message: message
      )
    end

    def errors
      @violations.select(&.severity.error?)
    end

    def warnings
      @violations.select(&.severity.warning?)
    end

    def clean?
      @violations.empty?
    end

    def has_errors?
      @violations.any?(&.severity.error?)
    end

    def has_warnings?
      @violations.any?(&.severity.warning?)
    end

    # Exit code: 0 = clean, 1 = errors, 2 = warnings only
    def exit_code(strict : Bool = false) : Int32
      if has_errors?
        1
      elsif has_warnings? && strict
        1
      elsif has_warnings?
        2
      else
        0
      end
    end

    # Terminal-colored output
    def to_terminal(io : IO, colors : Bool = Shards.colors?)
      if clean?
        msg = "Policy check passed: no violations found"
        io.puts colors ? msg.colorize(:green) : msg
        return
      end

      errors.each do |v|
        prefix = colors ? "ERROR".colorize(:red).bold : "ERROR"
        io.puts "  #{prefix} [#{v.rule}] #{v.message}"
      end

      warnings.each do |v|
        prefix = colors ? "WARN".colorize(:yellow) : "WARN"
        io.puts "  #{prefix}  [#{v.rule}] #{v.message}"
      end

      summary_parts = [] of String
      summary_parts << "#{errors.size} error(s)" if errors.any?
      summary_parts << "#{warnings.size} warning(s)" if warnings.any?
      io.puts
      io.puts "Policy check: #{summary_parts.join(", ")}"
    end

    # JSON output for CI/tooling integration
    def to_json_output(io : IO)
      JSON.build(io, indent: 2) do |json|
        json.object do
          json.field "violations" do
            json.array do
              @violations.each do |v|
                json.object do
                  json.field "package", v.package
                  json.field "rule", v.rule
                  json.field "severity", v.severity.to_s.downcase
                  json.field "message", v.message
                end
              end
            end
          end
          json.field "summary" do
            json.object do
              json.field "errors", errors.size
              json.field "warnings", warnings.size
              json.field "total", @violations.size
            end
          end
        end
      end
    end
  end
end
```

### 5. CLI Command: `src/commands/policy.cr`

This follows the pattern established by `Commands::MCP` (subcommand routing) and `Commands::SBOM` (argument parsing).

```crystal
# src/commands/policy.cr
require "./command"
require "../policy"
require "../policy_checker"
require "../policy_report"

module Shards
  module Commands
    class Policy < Command
      @policy_path : String?
      @strict : Bool = false
      @format : String = "terminal"

      def run(args : Array(String))
        # Parse options from args
        remaining = [] of String
        args.each do |arg|
          case arg
          when .starts_with?("--policy=")
            @policy_path = arg.split("=", 2).last
          when "--strict"
            @strict = true
          when .starts_with?("--format=")
            @format = arg.split("=", 2).last
          else
            remaining << arg unless arg.starts_with?("--")
          end
        end

        subcommand = remaining[0]? || "check"

        case subcommand
        when "check"
          run_check
        when "init"
          run_init
        when "show"
          run_show
        else
          raise Error.new(
            "Unknown policy subcommand: #{subcommand}. " \
            "Use: check, init, show"
          )
        end
      end

      private def policy_file_path : String
        @policy_path || File.join(path, POLICY_FILENAME)
      end

      private def load_policy : Policy
        ppath = policy_file_path
        unless File.exists?(ppath)
          raise Error.new(
            "No policy file found at #{ppath}. " \
            "Run 'shards policy init' to create one."
          )
        end
        Policy.from_file(ppath)
      end

      private def run_check
        policy = load_policy
        checker = PolicyChecker.new(policy)

        # Load packages from lockfile
        packages = locks.shards

        report = checker.check(packages)
        output_report(report)

        code = report.exit_code(strict: @strict)
        exit code unless code == 0
      end

      private def run_init
        target = policy_file_path
        if File.exists?(target)
          raise Error.new("Policy file already exists: #{target}")
        end

        File.write(target, DEFAULT_POLICY_TEMPLATE)
        Log.info { "Created #{target}" }
      end

      private def run_show
        policy = load_policy
        puts "Policy: #{policy_file_path}"
        puts "Version: #{policy.version}"
        puts

        unless policy.sources.empty?
          puts "Source Rules:"
          unless policy.sources.allowed_hosts.empty?
            puts "  Allowed hosts: #{policy.sources.allowed_hosts.join(", ")}"
          end
          policy.sources.allowed_orgs.each do |host, orgs|
            puts "  Allowed orgs on #{host}: #{orgs.join(", ")}"
          end
          if policy.sources.deny_path_dependencies?
            puts "  Path dependencies: denied"
          end
          puts
        end

        unless policy.dependencies.blocked.empty?
          puts "Blocked dependencies:"
          policy.dependencies.blocked.each do |b|
            reason = b.reason ? " (#{b.reason})" : ""
            puts "  - #{b.name}#{reason}"
          end
          puts
        end

        unless policy.dependencies.minimum_versions.empty?
          puts "Minimum versions:"
          policy.dependencies.minimum_versions.each do |name, ver|
            puts "  #{name}: #{ver}"
          end
          puts
        end

        sec = policy.security
        if sec.require_license? || sec.block_postinstall? || sec.audit_postinstall?
          puts "Security:"
          puts "  Require license: #{sec.require_license?}" if sec.require_license?
          puts "  Block postinstall: #{sec.block_postinstall?}" if sec.block_postinstall?
          puts "  Audit postinstall: #{sec.audit_postinstall?}" if sec.audit_postinstall?
          puts
        end

        unless policy.custom.empty?
          puts "Custom rules:"
          policy.custom.each do |r|
            puts "  #{r.name}: /#{r.pattern.source}/ (#{r.action})"
          end
        end
      end

      private def output_report(report : PolicyReport)
        case @format
        when "json"
          report.to_json_output(STDOUT)
          puts
        else
          report.to_terminal(STDOUT)
        end
      end

      DEFAULT_POLICY_TEMPLATE = <<-YAML
      version: 1

      rules:
        # Source restrictions - only allow deps from approved origins
        sources:
          allowed_hosts: []
          # allowed_orgs:
          #   github.com:
          #     - my-org
          deny_path_dependencies: false

        # Dependency restrictions
        dependencies:
          blocked: []
          # - name: malicious_shard
          #   reason: "Known supply chain compromise"
          minimum_versions: {}
          # some_shard: ">= 2.0.0"

        # Security requirements
        security:
          require_license: false
          block_postinstall: false
          audit_postinstall: false

        # Custom rules (regex-based)
        # custom:
        #   - name: "no-crypto-libs"
        #     pattern: "crypto|cipher|encrypt"
        #     action: warn
        #     reason: "Crypto libraries require security review"
      YAML
    end
  end
end
```

### 6. Modifications to Existing Files

#### 6.1 `src/config.cr` -- Add constant

Add after line 8 (after `OVERRIDE_FILENAME`):
```crystal
POLICY_FILENAME = ".shards-policy.yml"
```

#### 6.2 `src/cli.cr` -- Register the command and wire it up

**Step 1**: Add `"policy"` to `BUILTIN_COMMANDS` array (line 5-22). Insert it alphabetically, e.g. after `"outdated"`.

**Step 2**: Add help text in `display_help_and_exit` (around line 38):
```crystal
          policy [check|init|show]               - Manage dependency policies.
```

**Step 3**: Add the `when "policy"` case in the command dispatch (after line 126, following the pattern of `mcp`):
```crystal
when "policy"
  Commands::Policy.run(
    path,
    args[1..-1]
  )
```

This follows exactly the pattern used for `mcp` (lines 148-152) and `sbom` (lines 153-164).

#### 6.3 `src/commands/install.cr` -- Add policy check hook

The hook goes after dependency resolution (after `packages = handle_resolver_errors { solver.solve }` on line 25) and before the `install(packages)` call on line 31. This is the correct point because:
- Packages are fully resolved with concrete versions
- Nothing has been installed yet, so the check can block the process
- The `validate` call for frozen mode (line 28) has already passed

```crystal
# After line 25 and before the frozen check on line 27:
packages = handle_resolver_errors { solver.solve }

# Add policy check hook here:
check_policy(packages)

if Shards.frozen?
  validate(packages)
end

install(packages)
```

The `check_policy` method is added to the `Command` base class (see below) so both `Install` and `Update` share the same logic.

#### 6.4 `src/commands/update.cr` -- Add policy check hook

Similarly, insert after line 23 (`packages = handle_resolver_errors { solver.solve }`), before line 24 (`install(packages)`):

```crystal
packages = handle_resolver_errors { solver.solve }
check_policy(packages)
install(packages)
```

#### 6.5 `src/commands/command.cr` -- Add shared policy check method

Add a protected method to the `Command` base class. This is a shared convenience so that both `Install` and `Update` can call it without duplicating code. The method is a no-op when no policy file exists, which is the default behavior (policy is opt-in).

```crystal
# Add to Command class, after check_crystal_version method:

protected def check_policy(packages : Array(Package))
  policy_path = File.join(path, POLICY_FILENAME)
  return unless File.exists?(policy_path)

  Log.info { "Checking dependency policies" }

  policy = Policy.from_file(policy_path)
  checker = PolicyChecker.new(policy)
  report = checker.check(packages)

  unless report.clean?
    report.to_terminal(STDERR)
  end

  if report.has_errors?
    raise Error.new("Policy violations found. Use 'shards policy check' for details.")
  end
end
```

The method also needs these requires added to the top of `command.cr`:
```crystal
require "../policy"
require "../policy_checker"
require "../policy_report"
```

**Design rationale for placing the hook in the base class**: This avoids code duplication between `Install` and `Update`. The method checks for policy file existence first (no-op if absent), so it has zero impact on projects that do not use policies. Errors are raised as `Shards::Error`, which is already caught by the top-level error handler in `cli.cr` (line 230) and results in exit code 1.

### 7. Test Strategy

#### 7.1 Unit Tests: `spec/unit/policy_spec.cr`

Tests the YAML parsing layer in isolation, following the pattern of `spec/unit/override_spec.cr`.

```crystal
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
        security:
          require_license: true
          block_postinstall: false
          audit_postinstall: true
        custom:
          - name: "no-crypto"
            pattern: "crypto|cipher"
            action: warn
            reason: "Needs review"
      YAML

      policy.version.should eq("1")
      policy.sources.allowed_hosts.should eq(["github.com", "gitlab.com"])
      policy.sources.allowed_orgs["github.com"].should eq(["crystal-lang", "my-company"])
      policy.sources.deny_path_dependencies?.should be_true
      policy.dependencies.blocked.size.should eq(1)
      policy.dependencies.blocked[0].name.should eq("malicious_shard")
      policy.dependencies.blocked[0].reason.should eq("Known supply chain compromise")
      policy.dependencies.minimum_versions["some_shard"].should eq(">= 2.0.0")
      policy.security.require_license?.should be_true
      policy.security.block_postinstall?.should be_false
      policy.security.audit_postinstall?.should be_true
      policy.custom.size.should eq(1)
      policy.custom[0].name.should eq("no-crypto")
      policy.custom[0].action.should eq(:warn)
    end

    it "parses empty policy" do
      policy = Policy.from_yaml("version: 1\n")
      policy.version.should eq("1")
      policy.sources.empty?.should be_true
      policy.dependencies.blocked.should be_empty
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
    end

    it "skips unknown attributes" do
      policy = Policy.from_yaml <<-YAML
      version: 1
      unknown_key: test
      rules:
        sources:
          allowed_hosts:
            - github.com
          unknown_field: value
      YAML
      policy.sources.allowed_hosts.should eq(["github.com"])
    end
  end
end
```

#### 7.2 Unit Tests: `spec/unit/policy_checker_spec.cr`

Tests the evaluation engine against mock packages. Uses `create_git_repository` from factories to build real `Package` objects.

```crystal
require "./spec_helper"
require "../../src/policy"
require "../../src/policy_checker"
require "../../src/policy_report"

module Shards
  describe PolicyChecker do
    describe "#check_blocked" do
      it "flags blocked dependencies" do
        # Create a Package with a GitResolver for github.com
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
    end

    describe "#check_sources" do
      it "flags dependencies from unapproved hosts" do
        create_git_repository "unapproved", "1.0.0"
        # GitResolver with a non-github source
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
        resolver = PathResolver.new("local_dep", "/tmp/local_dep")
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
    end

    # Additional tests for security rules, custom rules, etc.
  end
end
```

#### 7.3 Integration Tests: `spec/integration/policy_spec.cr`

Tests the full CLI flow using `with_shard` and `run "shards policy ..."`.

```crystal
require "./spec_helper"

describe "policy" do
  it "blocks install when dependency from unapproved source" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      # Create policy that only allows gitlab.com
      File.write ".shards-policy.yml", <<-YAML
      version: 1
      rules:
        sources:
          allowed_hosts:
            - gitlab.com
      YAML

      # Install should fail because web is from a file:// git URL
      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      ex.stdout.should contain("Policy violations found")
    end
  end

  it "blocks install for blocked dependency" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      File.write ".shards-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          blocked:
            - name: web
              reason: "Known issue"
      YAML

      ex = expect_raises(FailedCommand) { run "shards install --no-color" }
      ex.stdout.should contain("Policy violations found")
    end
  end

  it "passes with compliant dependencies" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      # Empty policy = everything passes
      File.write ".shards-policy.yml", "version: 1\n"
      run "shards install"
      assert_installed "web"
    end
  end

  it "standalone policy check works against lockfile" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"

      File.write ".shards-policy.yml", <<-YAML
      version: 1
      rules:
        dependencies:
          blocked:
            - name: web
              reason: "Test block"
      YAML

      ex = expect_raises(FailedCommand) { run "shards policy check --no-color" }
      ex.stdout.should contain("blocked")
    end
  end

  it "policy init creates starter file" do
    with_shard({} of Symbol => String) do
      run "shards policy init"
      File.exists?(".shards-policy.yml").should be_true
    end
  end

  it "strict mode treats warnings as errors" do
    metadata = {dependencies: {web: "*"}}
    with_shard(metadata) do
      run "shards install"

      # Security rule that produces a warning
      File.write ".shards-policy.yml", <<-YAML
      version: 1
      rules:
        security:
          require_license: true
      YAML

      # Without --strict, warnings are exit code 2 (which run helper treats as success)
      # With --strict, warnings become exit code 1
      ex = expect_raises(FailedCommand) { run "shards policy check --strict --no-color" }
      ex.stdout.should contain("WARN") | ex.stdout.should contain("ERROR")
    end
  end
end
```

### 8. Implementation Sequence

The implementation should proceed in this order to maintain a compilable project at each step:

1. **`src/config.cr`** -- Add `POLICY_FILENAME` constant (1 line change)
2. **`src/policy.cr`** -- Create the data model and YAML parser (self-contained, no dependencies on new code)
3. **`spec/unit/policy_spec.cr`** -- Write and verify parsing tests
4. **`src/policy_report.cr`** -- Create the violation reporting module (depends only on standard lib + `Shards.colors?`)
5. **`src/policy_checker.cr`** -- Create the evaluation engine (depends on `Policy`, `PolicyReport`, and existing `Package`/`Resolver` types)
6. **`spec/unit/policy_checker_spec.cr`** -- Write and verify checker tests
7. **`src/commands/policy.cr`** -- Create the CLI command (depends on all three new modules)
8. **`src/commands/command.cr`** -- Add `check_policy` protected method with requires
9. **`src/commands/install.cr`** -- Add one-line `check_policy(packages)` call
10. **`src/commands/update.cr`** -- Add one-line `check_policy(packages)` call
11. **`src/cli.cr`** -- Register `"policy"` in `BUILTIN_COMMANDS`, add help text, add dispatch case
12. **`spec/integration/policy_spec.cr`** -- Write and verify integration tests

### 9. Success Criteria

1. **Parsing**: `Policy.from_yaml` correctly loads all rule types from a `.shards-policy.yml` file, with graceful handling of missing/unknown fields.
2. **Blocked deps**: A dependency listed in `dependencies.blocked` produces an error-level violation and blocks `shards install`.
3. **Source restriction**: A dependency from a host not in `sources.allowed_hosts` produces an error-level violation and blocks `shards install`.
4. **Org restriction**: A dependency from an unapproved org on an approved host produces an error-level violation.
5. **Path denial**: When `deny_path_dependencies: true`, path dependencies produce error-level violations.
6. **Minimum version**: A dependency below the minimum version produces an error-level violation.
7. **License requirement**: When `require_license: true`, a dependency without a license produces a warning.
8. **Postinstall blocking**: When `block_postinstall: true`, dependencies with postinstall scripts produce errors.
9. **Custom rules**: Regex-based custom rules match dependency names and produce the configured severity level.
10. **Install integration**: `shards install` with a policy file runs checks after resolution and before installation; violations block the install.
11. **Update integration**: `shards update` with a policy file runs checks after resolution.
12. **Standalone check**: `shards policy check` reads the lockfile and evaluates all policies.
13. **Strict mode**: `--strict` causes warnings to be treated as errors (exit code 1 instead of 2).
14. **JSON output**: `--format=json` produces structured JSON output suitable for CI parsing.
15. **Init command**: `shards policy init` creates a commented starter policy file.
16. **No-op without file**: When no `.shards-policy.yml` exists, `shards install` and `shards update` behave identically to before.

### 10. Validation Steps

1. Create a test project with `shard.yml` listing a GitHub dependency.
2. Run `shards install` -- verify it works normally (no policy file = no change).
3. Run `shards policy init` -- verify `.shards-policy.yml` is created.
4. Edit the policy to add the dependency's name to `blocked` list.
5. Run `shards install` -- verify it fails with a policy violation error.
6. Run `shards policy check` -- verify it reports the blocked dependency.
7. Run `shards policy check --format=json` -- verify JSON output.
8. Edit the policy to set `allowed_hosts: [gitlab.com]` (dependency is from github.com).
9. Run `shards policy check` -- verify source host violation.
10. Edit the policy to set `allowed_hosts: [github.com]` and add `allowed_orgs` restricting to a different org.
11. Run `shards policy check` -- verify org violation.
12. Add `require_license: true` to the security section.
13. Run `shards policy check` -- verify warning for unlicensed dependency.
14. Run `shards policy check --strict` -- verify warning becomes error (exit code 1).
15. Add a custom rule matching the dependency name pattern.
16. Run `shards policy check` -- verify custom rule match.
17. Run `shards policy show` -- verify policy summary display.

### 11. Edge Cases and Error Handling

- **Malformed policy YAML**: Handled by the `rescue YAML::ParseException` pattern, same as `Spec`/`Override`. Produces a `ParseError` with line/column info.
- **Missing lockfile for standalone check**: The `Command#locks` method already raises `Error.new("Missing #{LOCK_FILENAME}...")` which is caught by the top-level handler.
- **Empty allowed_hosts**: When the array is empty, no host restriction is applied (opt-in allowlist behavior).
- **Dependency not in minimum_versions hash**: Simply not checked -- hash lookup returns nil.
- **Spec reading failures during security checks**: `package.spec` may fail to load the spec for some packages. The checker should rescue and skip spec-dependent checks gracefully.
- **Non-git resolvers**: FossilResolver and HgResolver have different URL schemes. The `extract_host` and `extract_owner` helpers use `URI.parse` which handles them, falling back to `nil` if parsing fails.

### Critical Files for Implementation
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/command.cr` - Base class where the shared `check_policy` hook method must be added
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/install.cr` - Must insert `check_policy(packages)` call after solver resolution
- `/Users/crimsonknight/open_source_coding_projects/shards/src/cli.cr` - Must register the `policy` command in BUILTIN_COMMANDS and dispatch
- `/Users/crimsonknight/open_source_coding_projects/shards/src/resolvers/git.cr` - Reference for how source URLs are normalized (critical for host/org extraction logic)
- `/Users/crimsonknight/open_source_coding_projects/shards/src/commands/sbom.cr` - Pattern reference for Package iteration, source extraction, and purl/host parsing