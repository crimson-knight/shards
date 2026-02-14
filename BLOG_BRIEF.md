# Blog Post Brief: AI-Augmented Package Manager Development

## What This Is For

This document is a brief for another agent to write a blog post about the experiment of using AI coding agents to evolve Crystal's Shards package manager with features that benefit both human developers and AI agents.

## The Experiment

A human developer is collaborating with Claude (an AI coding agent) to add features to Crystal's Shards package manager -- the official dependency manager for the Crystal programming language. What makes this interesting is the *kinds* of features being built: they're tools that make the package manager better for both human and AI workflows.

## What's Been Built So Far

### 1. AI Documentation Distribution (already shipped)

Shards can now distribute AI coding agent documentation alongside library code. When you run `shards install`, AI docs from dependencies are automatically installed into your project's `.claude/` directory. This means library authors can ship skills, agent definitions, slash commands, and context files that get automatically distributed to consumers.

Key design decisions:
- Files are namespaced by shard name to prevent conflicts
- Conflict detection via dual checksums (upstream vs installed)
- User modifications are preserved during updates
- Security: settings files are never distributed

### 2. MCP Server Distribution (already shipped)

Dependencies can ship `.mcp.json` files that get merged into a project-level `.mcp-shards.json`. Server names are namespaced, relative paths are rewritten. Users can merge shard MCP configs into their own `.mcp.json` with `shards ai-docs merge-mcp`.

### 3. Postinstall Script Version Tracking (already shipped)

Scripts only auto-run on first install. Changed scripts emit a warning instead of silently re-executing. Users must explicitly run changed scripts with `shards run-script`.

### 4. Documentation Generation with AI Integration (already shipped)

`shards docs` wraps `crystal docs` to add CSS theming, AI assistant buttons (Claude, ChatGPT, Gemini), and parallel Markdown file generation for AI consumption.

### 5. SBOM Generation (just built in this session)

`shards sbom` generates Software Bill of Materials in SPDX 2.3 or CycloneDX 1.6 JSON format. No new dependencies needed -- uses Crystal stdlib's `JSON::Builder`. Supports GitHub/GitLab/Bitbucket/Codeberg purl generation, transitive dependency graph tracking, and path dependency handling. Test coverage: 7 unit tests + 16 integration tests.

## The Bigger Picture / Themes for the Blog

### Tools That Serve Both Worlds

Every feature built here benefits human developers *and* AI agents. SBOM generation is a compliance requirement for humans but also gives AI agents a machine-readable dependency inventory. AI docs distribution helps human developers by surfacing library documentation in their IDE, but it also gives AI coding agents the context they need to use libraries correctly.

### Package Managers as Knowledge Distribution Systems

The thesis emerging from this work is that package managers aren't just code distribution systems -- they're *knowledge* distribution systems. When a library author can ship not just code but also AI skills, MCP server configurations, and documentation tailored for agents, the entire ecosystem levels up.

### The Upward Spiral

Each feature makes the next one easier to build. AI docs make libraries more usable by agents. MCP distribution gives agents access to specialized tools. Better tools mean agents can contribute more effectively. This is a deliberate growth loop.

### Practical Compliance

The SBOM feature demonstrates how AI agents can rapidly implement compliance requirements (SOC 2, ISO 27001) that would otherwise be tedious. The entire SPDX + CycloneDX implementation, with tests, was built in a single session.

## What's Being Explored Next

### MCP Server Lifecycle Management

The next frontier: `shards mcp start` / `shards mcp stop` to actually run MCP servers distributed by dependencies. This would let library authors distribute pre-compiled MCP servers that spin up local HTTP services for coding agents to connect to. The package manager becomes an orchestrator, not just an installer.

## Technical Details for the Blog Author

- **Language**: Crystal (compiled, Ruby-like syntax, type-safe)
- **Package Manager**: Shards (official Crystal package manager)
- **AI Agent**: Claude (Anthropic), used via Claude Code CLI
- **Repository**: The shards package manager itself
- **Key architectural pattern**: Everything uses Crystal stdlib only -- no external dependencies for any of the new features
- **Test infrastructure**: Crystal's built-in spec framework, integration tests that create real git repositories and run the CLI
