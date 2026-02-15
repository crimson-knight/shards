module Shards
  # # Shards Documentation
  #
  # Shards is the dependency manager for the Crystal programming language.
  # It reads `shard.yml` to resolve, install, and update dependencies from
  # source repositories.
  #
  # ## Features
  #
  # - **Dependency resolution** via `shard.yml` with semantic versioning
  # - **Lock files** (`shard.lock`) for reproducible builds
  # - **Build targets** for compiling Crystal executables
  # - **Postinstall scripts** with version-aware execution tracking
  # - **AI documentation distribution** from shard dependencies
  # - **MCP server distribution** via `.mcp-shards.json`
  #
  # See `Shards::Docs` submodules for detailed guides on each feature area.
  module Docs
    # ## AI Documentation Distribution
    #
    # Shards can distribute AI coding agent documentation alongside library
    # code. When you run `shards install`, AI docs from dependencies are
    # automatically installed into the project's `.claude/` directory.
    #
    # ### How It Works
    #
    # The `AIDocsInstaller` scans each installed dependency for AI-relevant
    # files and copies them into the project with shard-namespaced paths.
    #
    # ### Auto-detected locations
    #
    # These paths are scanned in each dependency:
    #
    # | Source in shard | What it is |
    # |---|---|
    # | `.claude/skills/<name>/` | Claude Code skills |
    # | `.claude/agents/<name>.md` | Agent definitions |
    # | `.claude/commands/<name>.md` | Slash commands |
    # | `CLAUDE.md` | General AI context |
    # | `AGENTS.md` | Agent specifications |
    # | `.mcp.json` | MCP server configs |
    #
    # ### Installation mapping
    #
    # Files are namespaced by shard name to prevent conflicts:
    #
    # | Source | Destination |
    # |---|---|
    # | `.claude/skills/<name>/` | `.claude/skills/<shard>--<name>/` |
    # | `.claude/agents/<name>.md` | `.claude/agents/<shard>--<name>.md` |
    # | `.claude/commands/<name>.md` | `.claude/commands/<shard>:<name>.md` |
    # | `CLAUDE.md` (no skills) | `.claude/skills/<shard>--docs/SKILL.md` |
    # | `CLAUDE.md` (with skills) | `.claude/skills/<shard>--docs/reference/CLAUDE.md` |
    # | `AGENTS.md` | `.claude/skills/<shard>--docs/reference/AGENTS.md` |
    # | `.mcp.json` | merged into `.mcp-shards.json` |
    #
    # When a shard ships `CLAUDE.md` but no explicit skills, the content is
    # wrapped as a passive skill with frontmatter (`user-invocable: false`).
    #
    # ### Conflict detection
    #
    # `AIDocsInfo` tracks two checksums per file (upstream and installed).
    # User-modified files are preserved during updates, with a `.upstream`
    # copy saved for comparison. See `AIDocsInfo::FileEntry#user_modified?`.
    #
    # ### Security
    #
    # `.claude/settings.json` and `.claude/settings.local.json` are never
    # distributed, even if present in a dependency.
    #
    # ### shard.yml configuration
    #
    # The `ai_docs` section is optional. Auto-detection handles standard
    # locations. Use it only for customization:
    #
    # ```yaml
    # ai_docs:
    #   include:
    #     - docs/claude/custom_guide.md
    #   exclude:
    #     - .claude/skills/internal_dev_tool/
    # ```
    #
    # See `Spec::AIDocs`, `AIDocsInstaller`, `AIDocsInfo`.
    module AIDocumentation
    end

    # ## Postinstall Scripts
    #
    # Shards supports postinstall scripts defined in `shard.yml`:
    #
    # ```yaml
    # scripts:
    #   postinstall: make ext
    # ```
    #
    # ### Version-aware execution
    #
    # Postinstall scripts use `PostinstallInfo` for tracking:
    #
    # - **First install**: the script runs automatically, and its hash is recorded
    # - **Subsequent installs** (same script): skipped silently
    # - **Script changed**: a warning is emitted, the user must run
    #   `shards run-script <shard>` explicitly
    #
    # This prevents unexpected re-execution of potentially destructive scripts
    # while still notifying users when scripts change.
    #
    # ### Manual execution
    #
    # ```
    # shards run - script          # run all pending scripts
    # shards run - script my_shard # run for specific shard
    # ```
    #
    # See `PostinstallInfo`, `Commands::RunScript`, `Package#postinstall`.
    module PostinstallScripts
    end

    # ## MCP Server Distribution
    #
    # Shards that ship `.mcp.json` can distribute MCP (Model Context Protocol)
    # server configurations to consuming projects.
    #
    # ### How it works
    #
    # When a dependency contains `.mcp.json`, the `AIDocsInstaller`:
    #
    # 1. Parses the JSON and extracts `mcpServers` entries
    # 2. Namespaces server names as `<shard>/<server_name>`
    # 3. Rewrites relative command/args paths to `lib/<shard>/...`
    # 4. Merges into `.mcp-shards.json` at the project root
    #
    # The user's `.mcp.json` is never modified automatically. To merge
    # shard servers into the user's config:
    #
    # ```
    # shards ai - docs merge - mcp
    # ```
    #
    # ### Example .mcp.json in a shard
    #
    # ```json
    # {
    #   "mcpServers": {
    #     "db-explorer": {
    #       "command": "./bin/mcp-server",
    #       "args": ["--mode", "readonly"]
    #     }
    #   }
    # }
    # ```
    #
    # After installation, this becomes `<shard>/db-explorer` in `.mcp-shards.json`
    # with the command rewritten to `lib/<shard>/bin/mcp-server`.
    #
    # See `AIDocsInstaller#install_mcp_config`, `Commands::AIDocs`.
    module MCPDistribution
    end

    # ## MCP Server Lifecycle Management
    #
    # The `shards mcp` command manages the runtime lifecycle of MCP servers
    # distributed via `.mcp-shards.json`. This completes the pipeline from
    # distribution (handled by `shards install`) to execution.
    #
    # ### Commands
    #
    # ```
    # shards mcp                         # Show server status (default)
    # shards mcp start [server_name]     # Start all or one server
    # shards mcp stop [server_name]      # Stop all or one server
    # shards mcp restart [server_name]   # Restart all or one server
    # shards mcp logs <name> [--no-follow] [--lines=N]
    # ```
    #
    # ### Runtime state
    #
    # All managed state lives in `.shards/mcp/`:
    # - `servers.json`: PID, port, timestamps per server
    # - `<name>.log`: per-server stdout/stderr logs
    # - `bin/`: cached builds for `crystal_main` servers
    #
    # ### Process management
    #
    # Servers are spawned via `Process.new` (non-blocking) with output
    # redirected to log files. PID tracking uses `LibC.kill(pid, 0)`.
    # Shutdown sends SIGTERM, waits 5 seconds, then SIGKILL if needed.
    # Stale PIDs are detected and cleaned on every status check.
    #
    # ### Name resolution
    #
    # Server names use the existing namespacing from `.mcp-shards.json`
    # (e.g., `my_shard/explorer`). Partial name matching is supported:
    # `explorer` finds `my_shard/explorer` if unambiguous.
    #
    # See `MCPManager`, `Commands::MCP`.
    module MCPLifecycle
    end

    # ## CLI Commands Reference
    #
    # ### Core commands
    #
    # | Command | Description |
    # |---|---|
    # | `shards install` | Install dependencies from `shard.yml` |
    # | `shards update [names...]` | Update dependencies to latest compatible |
    # | `shards build [targets...]` | Build targets defined in `shard.yml` |
    # | `shards run [target]` | Build and run a target |
    # | `shards check` | Verify all dependencies are installed |
    # | `shards list [--tree]` | List installed dependencies |
    # | `shards lock [--update]` | Lock dependencies without installing |
    # | `shards outdated [--pre]` | Show outdated dependencies |
    # | `shards prune` | Remove unused dependencies |
    # | `shards version [path]` | Print the shard version |
    # | `shards init` | Generate a new `shard.yml` |
    #
    # ### AI docs commands
    #
    # | Command | Description |
    # |---|---|
    # | `shards ai-docs` | Show installed AI docs status |
    # | `shards ai-docs diff <shard>` | Diff local changes vs upstream |
    # | `shards ai-docs reset <shard> [file]` | Reset to upstream version |
    # | `shards ai-docs update [shard]` | Force re-install AI docs |
    # | `shards ai-docs merge-mcp` | Merge shard MCP configs into `.mcp.json` |
    # | `shards run-script [names...]` | Run pending postinstall scripts |
    # | `shards docs [options]` | Generate themed docs with AI buttons |
    # | `shards sbom [options]` | Generate SBOM (SPDX/CycloneDX) |
    #
    # ### MCP lifecycle commands
    #
    # | Command | Description |
    # |---|---|
    # | `shards mcp` | Show MCP server status (default) |
    # | `shards mcp start [name]` | Start all or one MCP server |
    # | `shards mcp stop [name]` | Stop all or one MCP server |
    # | `shards mcp restart [name]` | Restart all or one MCP server |
    # | `shards mcp logs <name>` | Tail server logs (`--no-follow`, `--lines=N`) |
    #
    # ### Global flags
    #
    # | Flag | Description |
    # |---|---|
    # | `--frozen` | Strictly install locked versions |
    # | `--without-development` | Skip dev dependencies |
    # | `--production` | `--frozen --without-development` |
    # | `--skip-postinstall` | Skip postinstall scripts |
    # | `--skip-executables` | Skip executable installation |
    # | `--skip-ai-docs` | Skip AI documentation installation |
    # | `--local` | Use local cache only |
    # | `--jobs=N` | Parallel downloads (default: 8) |
    #
    # See individual command classes in `Commands`.
    module CLIReference
    end

    # ## shard.yml Format
    #
    # ### Required fields
    #
    # ```yaml
    # name: my_shard
    # version: 1.0.0
    # ```
    #
    # ### Dependencies
    #
    # ```yaml
    # dependencies:
    #   kemal:
    #     github: kemalcr/kemal
    #     version: ~> 1.0
    #   local_dep:
    #     path: ../local_dep
    #
    # development_dependencies:
    #   ameba:
    #     github: crystal-ameba/ameba
    # ```
    #
    # ### Dependency sources
    #
    # | Key | Description |
    # |---|---|
    # | `github: user/repo` | GitHub repository |
    # | `gitlab: user/repo` | GitLab repository |
    # | `bitbucket: user/repo` | Bitbucket repository |
    # | `git: <url>` | Any git URL |
    # | `hg: <url>` | Mercurial |
    # | `fossil: <url>` | Fossil |
    # | `path: <path>` | Local path |
    #
    # ### Version constraints
    #
    # | Pattern | Meaning |
    # |---|---|
    # | `*` | Any version |
    # | `1.0.0` | Exact version |
    # | `>= 1.0.0` | Minimum version |
    # | `~> 1.0` | >= 1.0.0, < 2.0.0 |
    # | `~> 1.0.3` | >= 1.0.3, < 1.1.0 |
    #
    # ### Build targets
    #
    # ```yaml
    # targets:
    #   my_app:
    #     main: src/my_app.cr
    # ```
    #
    # ### Scripts
    #
    # ```yaml
    # scripts:
    #   postinstall: make ext
    # ```
    #
    # ### AI documentation (optional)
    #
    # ```yaml
    # ai_docs:
    #   include:
    #     - docs/claude/custom_guide.md
    #   exclude:
    #     - .claude/skills/internal_dev_tool/
    # ```
    #
    # See `Spec`, `Spec::AIDocs`, `Dependency`.
    module ShardYmlFormat
    end

    # ## Publishing AI Docs for Your Shard
    #
    # ### Recommended: ship skills
    #
    # Create `.claude/skills/` in your shard repository:
    #
    # ```
    # your_shard/
    #   .claude/
    #     skills/
    #       getting-started/
    #         SKILL.md
    #       api-reference/
    #         SKILL.md
    #   src/
    #   shard.yml
    # ```
    #
    # Each `SKILL.md` needs frontmatter:
    #
    # ```markdown
    # ---
    # name: getting-started
    # description: How to get started with your_shard
    # user-invocable: false
    # ---
    # # Getting Started
    # ...
    # ```
    #
    # ### Simple: ship CLAUDE.md
    #
    # For basic documentation, add a `CLAUDE.md` at your shard root.
    # It is auto-converted to a passive skill during installation.
    #
    # ### Optional: customize with shard.yml
    #
    # ```yaml
    # ai_docs:
    #   include:
    #     - docs/claude/advanced_guide.md
    #   exclude:
    #     - .claude/skills/internal_dev_tool/
    # ```
    #
    # ### Ship MCP servers
    #
    # Add `.mcp.json` to your shard root with standard MCP configuration.
    # Relative paths in `command` and `args` are automatically rewritten.
    #
    # See `AIDocsInstaller`, `Docs::AIDocumentation`, `Docs::MCPDistribution`.
    module PublishingGuide
    end

    # ## Documentation Generation and Theming
    #
    # The `shards docs` command wraps `crystal docs` to add theming support
    # and AI assistant integration buttons.
    #
    # ### Usage
    #
    # ```
    # shards docs                      # Generate docs with defaults
    # shards docs --skip-ai-buttons    # No AI buttons
    # shards docs -o my_docs           # Custom output directory
    # ```
    #
    # All standard `crystal docs` options are passed through.
    #
    # ### Theming with CSS Variables
    #
    # `shards docs` injects CSS custom properties into the generated
    # stylesheet. To create a custom theme, create `docs-theme/style.css`
    # in your project root and override the variables:
    #
    # ```css
    # :root {
    #   --sidebar-bg: #1a1a2e;
    #   --sidebar-text: #e0e0e0;
    #   --accent-primary: #e94560;
    #   --type-name-color: #e94560;
    #   --signature-color: #e94560;
    #   --link-color: #0f3460;
    # }
    # ```
    #
    # Available CSS variables cover sidebar colors, main content colors,
    # code/signature styling, syntax highlighting, and more. See
    # `Commands::Docs::CSS_VARIABLES` for the full list.
    #
    # ### AI Assistant Buttons
    #
    # Each generated page includes buttons to discuss the API with:
    # - **Claude** (claude.ai)
    # - **ChatGPT** (chatgpt.com)
    # - **Gemini** (gemini.google.com)
    # - **View as Markdown** (opens the parallel `.md` file)
    #
    # The buttons extract page content and construct a prompt that
    # includes the type name, project name, and documentation.
    #
    # ### Markdown Files
    #
    # Parallel `.md` files are generated for every HTML page, making
    # the documentation easily consumable by AI coding assistants,
    # CLI tools, and any system that prefers plain text.
    #
    # See `Commands::Docs`.
    module DocsGeneration
    end

    # ## Software Bill of Materials (SBOM) Generation
    #
    # The `shards sbom` command generates a machine-readable inventory of all
    # dependencies in SPDX 2.3 or CycloneDX 1.6 JSON format for compliance
    # auditing (SOC 2, ISO 27001).
    #
    # ### Usage
    #
    # ```
    # shards sbom                          # SPDX 2.3 JSON (default)
    # shards sbom --format=cyclonedx       # CycloneDX 1.6 JSON
    # shards sbom --output=custom.json     # Custom output path
    # shards sbom --include-dev            # Include dev dependencies
    # ```
    #
    # ### Data sources
    #
    # The command reads `shard.lock` for locked versions, then loads each
    # dependency's `shard.yml` from `lib/<name>/` for metadata (license,
    # authors, description). Package URLs (purls) are derived from resolver
    # source URLs, with GitHub/GitLab/Bitbucket sources mapped to their
    # respective purl types.
    #
    # See `Commands::SBOM`.
    module SBOMGeneration
    end
  end
end
