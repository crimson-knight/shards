module Shards
  module ClaudeConfig
    # All .claude/ files to install into a project.
    # Keys are relative paths from the project root.
    # Values are file contents.
    # Existing files are never overwritten.

    FILES = {
      ".claude/CLAUDE.md"                                       => CLAUDE_MD,
      ".claude/settings.json"                                   => SETTINGS_JSON,
      ".claude/skills/audit/SKILL.md"                           => SKILL_AUDIT,
      ".claude/skills/licenses/SKILL.md"                        => SKILL_LICENSES,
      ".claude/skills/policy-check/SKILL.md"                    => SKILL_POLICY_CHECK,
      ".claude/skills/diff-deps/SKILL.md"                       => SKILL_DIFF_DEPS,
      ".claude/skills/compliance-report/SKILL.md"               => SKILL_COMPLIANCE_REPORT,
      ".claude/skills/sbom/SKILL.md"                            => SKILL_SBOM,
      ".claude/skills/shards-cli/SKILL.md"                      => SKILL_SHARDS_CLI,
      ".claude/skills/shards-cli/reference/commands.md"         => REF_COMMANDS,
      ".claude/skills/shards-cli/reference/shard-yml-format.md" => REF_SHARD_YML,
      ".claude/skills/shards-cli/reference/ai-docs-guide.md"    => REF_AI_DOCS,
      ".claude/agents/compliance-checker.md"                    => AGENT_COMPLIANCE_CHECKER,
      ".claude/agents/security-reviewer.md"                     => AGENT_SECURITY_REVIEWER,
    }

    def self.install(path : String) : Array(String)
      installed = [] of String

      FILES.each do |relative_path, content|
        full_path = File.join(path, relative_path)
        dir = File.dirname(full_path)
        Dir.mkdir_p(dir) unless Dir.exists?(dir)

        if File.exists?(full_path)
          next
        end

        File.write(full_path, content)
        installed << relative_path
      end

      installed
    end

    CLAUDE_MD = <<-'CONTENT'
    # Shards-Alpha: Supply Chain Compliance for Crystal

    This project uses shards-alpha, a Crystal package manager with built-in supply chain compliance tools.

    ## Available Commands

    | Command | Description |
    |---------|-------------|
    | `shards-alpha install` | Install dependencies from shard.yml |
    | `shards-alpha update` | Update dependencies to latest compatible versions |
    | `shards-alpha audit` | Scan dependencies for known vulnerabilities (OSV database) |
    | `shards-alpha licenses` | List dependency licenses with SPDX compliance checking |
    | `shards-alpha policy check` | Check dependencies against policy rules |
    | `shards-alpha diff` | Show dependency changes between lockfile states |
    | `shards-alpha compliance-report` | Generate unified compliance report |
    | `shards-alpha sbom` | Generate Software Bill of Materials (SPDX/CycloneDX) |

    ## Quick Compliance Check

    ```sh
    shards-alpha audit                    # Check for vulnerabilities
    shards-alpha licenses --check         # Verify license compliance
    shards-alpha policy check             # Enforce dependency policies
    ```

    ## Key Files

    | File | Purpose |
    |------|---------|
    | `shard.yml` | Dependency specification |
    | `shard.lock` | Locked dependency versions |
    | `.shards-policy.yml` | Dependency policy rules (optional) |
    | `.shards-audit-ignore` | Suppressed vulnerability IDs (optional) |

    ## MCP Compliance Server

    An MCP server exposes all compliance tools for AI agent integration:

    ```sh
    shards-alpha mcp-server              # Start stdio MCP server
    shards-alpha mcp-server --interactive # Manual testing mode
    ```

    Supports MCP protocol versions: 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05.
    CONTENT

    SETTINGS_JSON = <<-'CONTENT'
    {
      "permissions": {
        "allow": [
          "Bash(shards-alpha audit *)",
          "Bash(shards-alpha licenses *)",
          "Bash(shards-alpha policy *)",
          "Bash(shards-alpha diff *)",
          "Bash(shards-alpha compliance-report *)",
          "Bash(shards-alpha sbom *)",
          "Bash(shards-alpha mcp-server *)",
          "Bash(crystal build *)",
          "Bash(crystal spec *)",
          "Bash(crystal tool format *)"
        ]
      }
    }
    CONTENT

    SKILL_AUDIT = <<-'CONTENT'
    ---
    name: audit
    description: Scan project dependencies for known security vulnerabilities using the OSV database. Use when reviewing dependencies for security issues.
    allowed-tools: Bash, Read, Grep
    user-invocable: true
    argument-hint: [--severity=high] [--offline]
    ---

    # Audit Dependencies for Vulnerabilities

    Run a vulnerability scan against all locked dependencies using the OSV database.

    ## Steps

    1. Verify that `shard.lock` exists in the project root. If it does not, inform the user they need to run `shards-alpha install` first.

    2. Run the audit command with the user's requested options:
       ```sh
       shards-alpha audit [OPTIONS]
       ```

       Common options to pass through from user arguments:
       - `--severity=LEVEL` — Filter results to only show vulnerabilities at or above this severity (low, medium, high, critical)
       - `--format=FORMAT` — Output format: `terminal` (default), `json`, `sarif`
       - `--fail-above=LEVEL` — Only exit non-zero for vulnerabilities at or above this severity
       - `--ignore=ID[,ID]` — Comma-separated advisory IDs to suppress
       - `--ignore-file=PATH` — Path to ignore file (default: `.shards-audit-ignore`)
       - `--offline` — Use cached vulnerability data only, no network requests
       - `--update-db` — Force a cache refresh before scanning

    3. Interpret the exit code:
       - Exit 0: No vulnerabilities found (or all filtered/ignored). Report this as a clean scan.
       - Exit 1: Vulnerabilities found matching the severity threshold.

    4. If vulnerabilities are found, summarize the results:
       - Group findings by severity (critical, high, medium, low)
       - For each vulnerability, report: advisory ID, affected dependency, affected versions, severity, and summary
       - Highlight any critical or high severity issues first

    5. Provide remediation advice:
       - Check if newer versions of affected dependencies are available that fix the vulnerability
       - Suggest specific version bumps in `shard.yml` where applicable
       - If a vulnerability cannot be fixed by upgrading, suggest adding it to `.shards-audit-ignore` with a reason and expiry date
       - Mention the `--fail-above` flag for CI pipelines that should only block on critical issues

    6. For JSON output (`--format=json`), parse the structured data to provide a more detailed breakdown. For SARIF output (`--format=sarif`), note that this is designed for GitHub Code Scanning integration.

    ## Example Invocations

    ```sh
    # Basic scan
    shards-alpha audit

    # Only show high and critical vulnerabilities
    shards-alpha audit --severity=high

    # CI-friendly: fail only on critical, output SARIF for GitHub
    shards-alpha audit --format=sarif --fail-above=critical

    # Offline scan with cached data
    shards-alpha audit --offline
    ```
    CONTENT

    SKILL_LICENSES = <<-'CONTENT'
    ---
    name: licenses
    description: List and check dependency licenses for SPDX compliance. Use when auditing license compatibility or checking policy.
    allowed-tools: Bash, Read, Grep
    user-invocable: true
    argument-hint: [--check] [--detect]
    ---

    # List and Check Dependency Licenses

    Audit all locked dependency licenses for SPDX compliance and policy conformance.

    ## Steps

    1. Verify that `shard.lock` exists in the project root. If it does not, inform the user they need to run `shards-alpha install` first.

    2. Run the licenses command with the user's requested options:
       ```sh
       shards-alpha licenses [OPTIONS]
       ```

       Available options to pass through:
       - `--format=FORMAT` — Output format: `terminal` (default), `json`, `csv`, `markdown`
       - `--check` — Exit 1 if any license policy violations are found
       - `--detect` — Use heuristic detection to identify licenses from LICENSE/COPYING files when shard.yml does not declare one
       - `--include-dev` — Include development dependencies in the scan
       - `--policy=PATH` — Path to a license policy YAML file

    3. Interpret the output:
       - Each dependency is listed with its name, version, declared license, and SPDX validity status
       - SPDX validation checks against 52 common SPDX identifiers and supports compound expressions (AND, OR, WITH operators)

    4. Summarize the findings:
       - Total number of dependencies scanned
       - Count of dependencies with valid SPDX licenses
       - Count of dependencies with missing or invalid licenses
       - Any policy violations if `--check` was used

    5. Flag potential issues:
       - Dependencies with no declared license (legal risk for commercial projects)
       - Dependencies with non-standard or unrecognized license identifiers
       - Copyleft licenses (GPL, AGPL) that may be incompatible with proprietary projects
       - If `--detect` was used, note which licenses were detected heuristically vs declared

    6. Provide recommendations:
       - For missing licenses, suggest the user contact the dependency maintainer or check the repository directly
       - For policy violations, explain which rule was violated and how to resolve it
       - For CSV or markdown output, note these formats are useful for legal review or PR descriptions

    ## Example Invocations

    ```sh
    # Basic license listing
    shards-alpha licenses

    # Check against policy, fail on violations
    shards-alpha licenses --check

    # Detect licenses from LICENSE files when not declared
    shards-alpha licenses --detect

    # Generate CSV for legal team review
    shards-alpha licenses --format=csv

    # Full scan including dev dependencies with detection
    shards-alpha licenses --detect --include-dev --format=json
    ```
    CONTENT

    SKILL_POLICY_CHECK = <<-'CONTENT'
    ---
    name: policy-check
    description: Check dependencies against policy rules in .shards-policy.yml. Use when verifying compliance before releases.
    allowed-tools: Bash, Read, Grep, Write
    user-invocable: true
    argument-hint: [--strict]
    ---

    # Check Dependencies Against Policy Rules

    Evaluate all locked dependencies against the rules defined in `.shards-policy.yml`.

    ## Steps

    1. Check if `.shards-policy.yml` exists in the project root:
       - If it exists, read it to understand the active policy rules before running the check.
       - If it does not exist, ask the user if they want to create one with `shards-alpha policy init`, which generates a starter policy file.

    2. Run the policy check with the user's requested options:
       ```sh
       shards-alpha policy check [OPTIONS]
       ```

       Available options:
       - `--strict` — Treat warnings as errors (useful for CI gates)
       - `--format=FORMAT` — Output format: `terminal` (default), `json`

       Other policy subcommands:
       - `shards-alpha policy init` — Create a starter `.shards-policy.yml`
       - `shards-alpha policy show` — Display a summary of the current policy

    3. Interpret the results:
       - **Error violations** block installation: blocked dependencies, denied sources, minimum version failures
       - **Warning violations** are displayed but do not block: missing licenses, postinstall script auditing

    4. Summarize the findings:
       - Total rules evaluated
       - Number of errors (blocking violations)
       - Number of warnings (non-blocking violations)
       - List each violation with the dependency name, rule that was violated, and the reason

    5. For each violation, suggest a fix:
       - **Blocked dependency**: Remove it from shard.yml or update the policy to allow it with a documented reason
       - **Disallowed source host**: Move the dependency to an allowed host or add the host to `rules.sources.allowed_hosts`
       - **Disallowed organization**: Add the org to `rules.sources.allowed_orgs` for that host
       - **Minimum version failure**: Update the dependency version in shard.yml to meet the minimum
       - **Missing license**: Add a license to the dependency's shard.yml or set `rules.security.require_license: false`
       - **Postinstall script warning**: Review the script for safety, then either allow it or set `rules.security.block_postinstall: true` to block

    6. If the user wants to modify the policy, offer to edit `.shards-policy.yml` directly with the needed changes.

    ## Policy File Structure

    The policy file `.shards-policy.yml` supports these rule categories:
    - `rules.sources` — Allowed hosts, allowed organizations, deny path dependencies
    - `rules.dependencies` — Blocked dependencies with reasons, minimum version requirements
    - `rules.security` — Require licenses, block/audit postinstall scripts
    - `rules.custom` — Regex patterns to allow or block dependency names

    ## Example Invocations

    ```sh
    # Basic policy check
    shards-alpha policy check

    # Strict mode for CI (warnings become errors)
    shards-alpha policy check --strict

    # JSON output for tooling
    shards-alpha policy check --format=json

    # Create a starter policy
    shards-alpha policy init

    # View current policy summary
    shards-alpha policy show
    ```
    CONTENT

    SKILL_DIFF_DEPS = <<-'CONTENT'
    ---
    name: diff-deps
    description: Show dependency changes between lockfile states. Use when reviewing what changed after updates.
    allowed-tools: Bash, Read, Grep
    user-invocable: true
    argument-hint: [--from=HEAD --to=current]
    ---

    # Show Dependency Changes Between Lockfile States

    Compare two states of shard.lock to see what dependencies were added, removed, or updated.

    ## Steps

    1. Verify that `shard.lock` exists in the project root. If it does not, inform the user there is nothing to diff.

    2. Run the diff command with the user's requested options:
       ```sh
       shards-alpha diff [OPTIONS]
       ```

       Available options:
       - `--from=REF` — Starting state (default: `HEAD`). Can be a git ref, file path ending in `.lock`, or `current`
       - `--to=REF` — Ending state (default: `current`). Same ref types as `--from`
       - `--format=FORMAT` — Output format: `terminal` (default), `json`, `markdown`

    3. Interpret the reference types:
       - `current` — Reads the current `shard.lock` from disk
       - A git ref (`HEAD`, `main`, `v1.0.0`, a commit SHA) — Extracts `shard.lock` from that point in git history via `git show`
       - A file path ending in `.lock` — Reads from an arbitrary lockfile on disk

    4. Summarize the changes:
       - **Added dependencies**: New dependencies not present in the "from" state. Report name, version, and source.
       - **Removed dependencies**: Dependencies present in "from" but absent in "to". Report name and previous version.
       - **Updated dependencies**: Dependencies present in both states but with different versions. Report name, old version, new version, and whether it was an upgrade or downgrade.
       - **Unchanged count**: How many dependencies remained the same.

    5. Provide context for the changes:
       - For major version bumps, warn about potential breaking changes
       - For added dependencies, note if they are transitive (pulled in by another dependency)
       - For removed dependencies, note if the removal might affect other parts of the project

    6. For markdown output (`--format=markdown`), mention this format is useful for including in PR descriptions to document dependency changes.

    ## Example Invocations

    ```sh
    # What changed since the last commit?
    shards-alpha diff

    # What changed since a release tag?
    shards-alpha diff --from=v1.0.0

    # Compare two specific lockfiles
    shards-alpha diff --from=before.lock --to=after.lock

    # Generate markdown for a PR description
    shards-alpha diff --from=main --format=markdown

    # JSON output for tooling
    shards-alpha diff --format=json
    ```
    CONTENT

    SKILL_COMPLIANCE_REPORT = <<-'CONTENT'
    ---
    name: compliance-report
    description: Generate comprehensive supply-chain compliance reports. Use before releases or for audit documentation.
    allowed-tools: Bash, Read, Grep, Write
    user-invocable: true
    argument-hint: [--sections=sbom,audit,licenses] [--reviewer=email]
    ---

    # Generate Supply-Chain Compliance Report

    Produce a unified compliance report combining SBOM, vulnerability audit, license compliance, policy evaluation, integrity verification, and change history into a single document suitable for SOC2 and ISO 27001 auditors.

    ## Steps

    1. Verify prerequisites:
       - `shard.yml` must exist in the project root
       - `shard.lock` must exist (run `shards-alpha install` if missing)
       - For policy sections, `.shards-policy.yml` should exist (optional but recommended)

    2. Run the compliance report command with the user's requested options:
       ```sh
       shards-alpha compliance-report [OPTIONS]
       ```

       Available options:
       - `--format=FORMAT` — Output format: `json` (default), `html`, `markdown`
       - `--output=PATH` — Output file path (default: `{project}-compliance-report.{ext}`)
       - `--sections=LIST` — Comma-separated sections to include (default: `all`)
       - `--reviewer=EMAIL` — Add reviewer attestation with timestamp to the report
       - `--since=DATE` — Filter change history to entries after this date
       - `--sign` — Create a detached GPG signature (`.sig` file)

    3. Available sections:

       | Section | Description |
       |---------|-------------|
       | `sbom` | SPDX 2.3 dependency inventory |
       | `audit` | OSV vulnerability scan results |
       | `licenses` | License inventory and compliance |
       | `policy` | Policy rule evaluation results |
       | `integrity` | SHA-256 checksum verification |
       | `changelog` | Dependency change history |

    4. Interpret the overall status:
       - **PASS** — No vulnerabilities, no policy violations, integrity verified
       - **ACTION_REQUIRED** — Medium-severity findings or warnings present
       - **FAIL** — Critical or high vulnerabilities, or policy/license failures

    5. Summarize the report for the user:
       - Overall compliance status
       - Total dependency count (direct and transitive)
       - Vulnerability summary by severity
       - License compliance status
       - Policy evaluation results

    ## Example Invocations

    ```sh
    # Full compliance report in HTML for auditors
    shards-alpha compliance-report --format=html --reviewer=security@company.com

    # Quick check with just SBOM and integrity sections
    shards-alpha compliance-report --sections=sbom,integrity

    # JSON report for CI artifact archival
    shards-alpha compliance-report --output=compliance-report.json

    # Markdown report for documentation
    shards-alpha compliance-report --format=markdown
    ```
    CONTENT

    SKILL_SBOM = <<-'CONTENT'
    ---
    name: sbom
    description: Generate a Software Bill of Materials (SBOM) in SPDX or CycloneDX format. Use for supply-chain transparency.
    allowed-tools: Bash, Read
    user-invocable: true
    argument-hint: [--format=spdx|cyclonedx]
    ---

    # Generate Software Bill of Materials (SBOM)

    Produce a complete inventory of all project dependencies in an industry-standard SBOM format.

    ## Steps

    1. Verify that `shard.lock` exists in the project root. If it does not, inform the user they need to run `shards-alpha install` first.

    2. Run the SBOM generation command:
       ```sh
       shards-alpha sbom [OPTIONS]
       ```

       Available options:
       - `--format=FORMAT` — SBOM format: `spdx` (default) or `cyclonedx`
       - `--output=FILE` — Output file path
       - `--include-dev` — Include development dependencies in the SBOM

    3. Supported formats:

       **SPDX 2.3 (default)**: Linux Foundation standard, required by US EO 14028.
       **CycloneDX 1.6**: OWASP standard focused on security and risk analysis.

    4. Summarize the generated SBOM:
       - Total number of components listed
       - Document creation timestamp
       - Output file location
       - Whether dev dependencies were included or excluded

    ## Example Invocations

    ```sh
    # Generate SPDX SBOM (default)
    shards-alpha sbom

    # Generate CycloneDX SBOM
    shards-alpha sbom --format=cyclonedx

    # Custom output path
    shards-alpha sbom --output=artifacts/sbom.spdx.json

    # Include development dependencies
    shards-alpha sbom --include-dev
    ```
    CONTENT

    SKILL_SHARDS_CLI = <<-'CONTENT'
    ---
    name: shards-cli
    description: Crystal Shards package manager CLI reference. Provides guidance on shard.yml format, dependency management, installation, building, and AI docs distribution.
    user-invocable: false
    ---

    # Crystal Shards CLI

    Shards is the dependency manager for Crystal. It reads `shard.yml` to resolve, install, and update dependencies from source repositories.

    ## Common Workflows

    ### Install dependencies
    ```
    shards install                  # Install from shard.yml, using shard.lock if present
    shards install --production     # Frozen + without development dependencies
    shards install --skip-ai-docs   # Skip AI documentation installation
    ```

    ### Update dependencies
    ```
    shards update                   # Update all to latest compatible versions
    shards update kemal             # Update only kemal
    ```

    ### Build targets
    ```
    shards build                    # Build all targets
    shards build my_app             # Build specific target
    shards build --release          # Build with --release flag
    ```

    ### Supply chain compliance
    ```
    shards audit                    # Vulnerability scan
    shards licenses                 # License compliance
    shards policy check             # Policy enforcement
    shards diff                     # Dependency changes
    shards compliance-report        # Full compliance report
    shards sbom                     # Software Bill of Materials
    ```

    ### Other commands
    ```
    shards check                    # Verify all dependencies are installed
    shards list                     # List installed dependencies
    shards list --tree              # List with dependency tree
    shards outdated                 # Show outdated dependencies
    shards prune                    # Remove unused dependencies from lib/
    shards version                  # Print shard version
    shards init                     # Generate a new shard.yml
    ```

    ## Key Flags

    | Flag | Description |
    |------|-------------|
    | `--frozen` | Strictly install locked versions from shard.lock |
    | `--without-development` | Skip development dependencies |
    | `--production` | Same as `--frozen --without-development` |
    | `--skip-postinstall` | Skip postinstall scripts |
    | `--skip-ai-docs` | Skip AI documentation installation |
    | `--jobs=N` | Parallel downloads (default: 8) |

    ## Reference

    - [shard.yml format](reference/shard-yml-format.md)
    - [All CLI commands](reference/commands.md)
    - [AI docs distribution guide](reference/ai-docs-guide.md)
    CONTENT

    REF_COMMANDS = <<-'CONTENT'
    # Shards CLI Commands Reference

    ## shards install

    Install dependencies from `shard.yml`. Creates `shard.lock` if it doesn't exist.

    ```
    shards install [options]
    ```

    ## shards update

    Update dependencies to latest compatible versions.

    ```
    shards update [shard_names...] [options]
    ```

    ## shards build

    Build targets defined in `shard.yml`.

    ```
    shards build [targets...] [-- build_options...]
    ```

    ## shards check

    Verify all dependencies are installed and match `shard.lock`.

    ## shards list

    List installed dependencies.

    ```
    shards list [--tree]
    ```

    ## shards lock

    Lock dependencies without installing.

    ```
    shards lock [--print] [--update [shards...]]
    ```

    ## shards outdated

    Show outdated dependencies.

    ```
    shards outdated [--pre]
    ```

    ## shards prune

    Remove unused dependencies from `lib/`.

    ## shards init

    Generate a new `shard.yml`.

    ## shards version

    Print the shard version from `shard.yml`.

    ```
    shards version [path]
    ```

    ## shards audit

    Scan dependencies for known vulnerabilities via OSV database.

    ```
    shards audit [--severity=LEVEL] [--format=FORMAT] [--fail-above=LEVEL] [--offline]
    ```

    ## shards licenses

    List dependency licenses with SPDX validation.

    ```
    shards licenses [--check] [--detect] [--format=FORMAT] [--include-dev]
    ```

    ## shards policy

    Manage dependency policies.

    ```
    shards policy check [--strict] [--format=FORMAT]
    shards policy init
    shards policy show
    ```

    ## shards diff

    Show dependency changes between lockfile states.

    ```
    shards diff [--from=REF] [--to=REF] [--format=FORMAT]
    ```

    ## shards compliance-report

    Generate unified compliance report.

    ```
    shards compliance-report [--format=FORMAT] [--sections=LIST] [--reviewer=EMAIL]
    ```

    ## shards sbom

    Generate Software Bill of Materials.

    ```
    shards sbom [--format=spdx|cyclonedx] [--output=FILE] [--include-dev]
    ```

    ## shards mcp-server

    Start MCP compliance server for AI agent integration.

    ```
    shards mcp-server              # Start stdio server
    shards mcp-server --interactive # Interactive testing mode
    shards mcp-server init          # Configure .mcp.json and .claude/
    shards mcp-server --help        # Show help
    ```
    CONTENT

    REF_SHARD_YML = <<-'CONTENT'
    # shard.yml Format Reference

    ## Required Fields

    ```yaml
    name: my_shard          # Shard name
    version: 1.0.0          # Semantic version
    ```

    ## Optional Fields

    ```yaml
    description: My shard description
    authors:
      - Author Name <email@example.com>
    crystal: ">= 1.0.0, < 2.0.0"
    license: MIT
    repository: https://github.com/user/repo
    ```

    ## Dependencies

    ```yaml
    dependencies:
      kemal:
        github: kemalcr/kemal
        version: ~> 1.0

      my_lib:
        git: https://example.com/repo.git
        branch: main

      local_dep:
        path: ../local_dep

    development_dependencies:
      ameba:
        github: crystal-ameba/ameba
    ```

    ### Dependency Sources

    | Key | Description |
    |-----|-------------|
    | `github: user/repo` | GitHub repository |
    | `gitlab: user/repo` | GitLab repository |
    | `bitbucket: user/repo` | Bitbucket repository |
    | `git: <url>` | Any git repository URL |
    | `path: <path>` | Local path dependency |

    ### Version Constraints

    | Pattern | Meaning |
    |---------|---------|
    | `~> 1.0` | >= 1.0.0, < 2.0.0 |
    | `~> 1.0.3` | >= 1.0.3, < 1.1.0 |
    | `>= 1.0, < 2.0` | Range |
    | `1.0.0` | Exact version |

    ## Build Targets

    ```yaml
    targets:
      my_app:
        main: src/my_app.cr
    ```

    ## Scripts

    ```yaml
    scripts:
      postinstall: make ext
    ```
    CONTENT

    REF_AI_DOCS = <<-'CONTENT'
    # AI Documentation Distribution Guide

    ## Overview

    Shards can distribute AI coding agent documentation alongside library code. When you run `shards install`, AI docs from dependencies are automatically installed into your project's `.claude/` directory.

    ## How It Works

    Shards automatically detects these locations in dependencies:

    | Source in shard | What it is |
    |-----------------|------------|
    | `.claude/skills/<name>/` | Claude Code skills |
    | `.claude/agents/<name>.md` | Agent definitions |
    | `CLAUDE.md` | General AI context |
    | `.mcp.json` | MCP server configs |

    Files are namespaced by shard name to avoid conflicts:

    | Source | Destination |
    |--------|-------------|
    | `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
    | `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
    | `CLAUDE.md` | `.claude/skills/<shard>--docs/SKILL.md` |
    | `.mcp.json` | Merged into `.mcp-shards.json` |

    ## Publishing AI Docs

    Create `.claude/skills/` in your shard with `SKILL.md` files containing YAML frontmatter:

    ```markdown
    ---
    name: getting-started
    description: How to get started with your_shard
    user-invocable: false
    ---
    # Getting Started
    ...
    ```

    Or simply add a `CLAUDE.md` at your shard root for basic documentation.

    ## User Customization

    - **Unmodified files**: Auto-updated on `shards update`
    - **Modified files**: Preserved on update
    - **View changes**: `shards ai-docs diff <shard>`
    - **Reset to upstream**: `shards ai-docs reset <shard>`
    CONTENT

    AGENT_COMPLIANCE_CHECKER = <<-'CONTENT'
    ---
    name: compliance-checker
    description: Specialized agent for running comprehensive compliance analysis on Crystal projects. Delegates to this agent when the user asks for a full compliance audit, security review, or pre-release check.
    tools: Bash, Read, Grep, Write
    model: sonnet
    maxTurns: 15
    ---

    # Compliance Checker Agent

    You are a supply-chain compliance specialist for Crystal projects using shards-alpha. Your job is to run a comprehensive compliance analysis and produce a clear, actionable report.

    ## Procedure

    ### Step 1: Verify Project Setup

    Check that `shard.yml` and `shard.lock` exist. If `shard.lock` is missing, run `shards-alpha install`.

    ### Step 2: Run Vulnerability Audit

    ```sh
    shards-alpha audit --format=json
    ```

    Record total vulnerabilities and breakdown by severity.

    ### Step 3: Run License Scan

    ```sh
    shards-alpha licenses --format=json --detect
    ```

    Record dependencies with valid SPDX licenses, missing licenses, and copyleft concerns.

    ### Step 4: Run Policy Check

    If `.shards-policy.yml` exists:

    ```sh
    shards-alpha policy check --format=json
    ```

    Record errors and warnings. If no policy file exists, note the gap.

    ### Step 5: Generate Compliance Report

    Compile findings into:

    **Executive Summary**
    - Overall status: PASS, ACTION_REQUIRED, or FAIL
    - Total dependency count

    **Vulnerability Findings**
    - List each vulnerability grouped by severity (critical first)

    **License Compliance**
    - List all dependencies with their licenses
    - Flag missing or problematic licenses

    **Policy Compliance**
    - List violations with remediation steps

    **Remediation Steps**
    - Specific version bumps for vulnerable dependencies
    - License additions for unlicensed dependencies
    - Policy file changes for violations

    ### Step 6: Offer Additional Actions

    - Generate formal report: `shards-alpha compliance-report --format=html`
    - Generate SBOM: `shards-alpha sbom`
    - Create policy: `shards-alpha policy init`
    - View changes: `shards-alpha diff`

    ## Important Notes

    - Run all commands from the project root.
    - Present findings in order of severity (most critical first).
    - Be specific in remediation advice.
    CONTENT

    AGENT_SECURITY_REVIEWER = <<-'CONTENT'
    ---
    name: security-reviewer
    description: Security-focused agent that analyzes dependencies for vulnerabilities and recommends patches. Delegates to this when the user asks about security posture or vulnerability remediation.
    tools: Bash, Read, Grep
    model: sonnet
    maxTurns: 10
    ---

    # Security Reviewer Agent

    You are a dependency security analyst for Crystal projects using shards-alpha. Your focus is identifying vulnerabilities, prioritizing them by risk, and recommending specific remediation actions.

    ## Procedure

    ### Step 1: Run Vulnerability Audit

    ```sh
    shards-alpha audit --format=json
    ```

    If exit code 0, report clean. If exit code 1, continue analysis.

    ### Step 2: Categorize Results

    For each vulnerability, extract: advisory ID, affected dependency, severity, summary, affected version range, fixed version. Group by severity (critical first).

    ### Step 3: Prioritize by Risk

    1. **Critical** — Remote code execution, data exfiltration. Immediate action.
    2. **High** — Privilege escalation, auth bypass. Fix within days.
    3. **Medium** — Limited impact. Fix within a sprint.
    4. **Low** — Informational. Track and fix at convenience.

    ### Step 4: Research Remediation

    Check `shard.yml` for current version constraints. For each vulnerability determine the minimum fixing version.

    ### Step 5: Recommend Fixes

    **Version Bump**: State the exact version constraint change needed.

    **Ignore with Justification**: If not applicable, recommend adding to `.shards-audit-ignore` with reason and 90-day expiry.

    **Dependency Replacement**: If unmaintained, recommend alternatives.

    ### Step 6: Security Summary

    **Security Posture: [CLEAN | AT RISK | CRITICAL]**

    Present: findings table, recommended shard.yml changes, ignore recommendations.

    ## Important Notes

    - Never recommend ignoring critical/high vulnerabilities without strong justification.
    - Check if fixes introduce breaking changes before recommending major version bumps.
    - Present findings factually. Do not downplay security risks.
    CONTENT
  end
end
