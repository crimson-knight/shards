# class Shards::ComplianceMCPServer

## Constants

- `CAPABILITIES` = `MCProtocol::ServerCapabilities.new(tools: MCProtocol::ServerCapabilitiesTools.new)`
- `HELP_TEXT` = `"shards-alpha mcp-server — MCP compliance server (JSON-RPC 2.0 over stdio)\n\nUsage:\n    shards-alpha mcp-server [command] [options]\n\nCommands:\n    init               Configure .mcp.json for MCP server\n    (default)          Start the MCP server (stdio transport)\n\nOptions:\n    --interactive    Run in interactive mode for manual testing\n    --help, -h       Show this help message\n\nTools provided:\n    audit              Scan dependencies for known vulnerabilities (OSV)\n    licenses           List dependency licenses with SPDX validation\n    policy_check       Check dependencies against policy rules\n    diff               Show dependency changes between lockfile states\n    compliance_report  Generate unified compliance report\n    sbom               Generate Software Bill of Materials (SPDX/CycloneDX)\n\nExamples:\n    shards-alpha mcp-server init          # Configure .mcp.json\n    shards-alpha mcp-server               # Start server (for MCP clients)\n    shards-alpha mcp-server --interactive  # Manual testing mode\n\nFor Claude Code skills, agents, and settings, use:\n    shards-alpha assistant init"`
- `LATEST_VERSION` = `SUPPORTED_VERSIONS.first`
- `MCP_SERVER_NAME` = `"shards-compliance"`
- `SERVER_INFO` = `MCProtocol::Implementation.new(name: "shards-compliance", version: Shards::VERSION)`
- `SUPPORTED_VERSIONS` = `["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]` -- Supported MCP protocol versions, newest first.
- `TOOLS` = `[MCProtocol::Tool.new(name: "audit", description: "Scan dependencies for known vulnerabilities using the OSV database. Returns vulnerability details with severity levels.", inputSchema: MCProtocol::ToolInputSchema.new(properties: JSON::Any.new({"severity" => JSON::Any.new({"type" => JSON::Any.new("string"), "enum" => JSON::Any.new(["low", "medium", "high", "critical"].map do |s| JSON::Any.new(s) end), "description" => JSON::Any.new("Minimum severity filter")}), "fail_above" => JSON::Any.new({"type" => JSON::Any.new("string"), "enum" => JSON::Any.new(["low", "medium", "high", "critical"].map do |s| JSON::Any.new(s) end), "description" => JSON::Any.new("Exit non-zero if vulnerabilities at or above this severity are found")}), "ignore" => JSON::Any.new({"type" => JSON::Any.new("string"), "description" => JSON::Any.new("Comma-separated advisory IDs to suppress")}), "offline" => JSON::Any.new({"type" => JSON::Any.new("boolean"), "description" => JSON::Any.new("Use cached vulnerability data only")})}))), MCProtocol::Tool.new(name: "licenses", description: "List all dependency licenses with SPDX identifier validation. Optionally check compliance against a license policy.", inputSchema: MCProtocol::ToolInputSchema.new(properties: JSON::Any.new({"check" => JSON::Any.new({"type" => JSON::Any.new("boolean"), "description" => JSON::Any.new("Exit non-zero if policy violations found")}), "detect" => JSON::Any.new({"type" => JSON::Any.new("boolean"), "description" => JSON::Any.new("Use heuristic detection from LICENSE files")}), "include_dev" => JSON::Any.new({"type" => JSON::Any.new("boolean"), "description" => JSON::Any.new("Include development dependencies")})}))), MCProtocol::Tool.new(name: "policy_check", description: "Check dependencies against policy rules defined in .shards-policy.yml. Validates allowed licenses, version constraints, and source requirements.", inputSchema: MCProtocol::ToolInputSchema.new(properties: JSON::Any.new({"strict" => JSON::Any.new({"type" => JSON::Any.new("boolean"), "description" => JSON::Any.new("Treat warnings as errors")})}))), MCProtocol::Tool.new(name: "diff", description: "Show dependency changes between lockfile states. Compares added, removed, and upgraded dependencies.", inputSchema: MCProtocol::ToolInputSchema.new(properties: JSON::Any.new({"from" => JSON::Any.new({"type" => JSON::Any.new("string"), "description" => JSON::Any.new("Starting ref (git ref, file path, or 'current'). Default: HEAD")}), "to" => JSON::Any.new({"type" => JSON::Any.new("string"), "description" => JSON::Any.new("Ending ref. Default: current working tree")})}))), MCProtocol::Tool.new(name: "compliance_report", description: "Generate a unified supply chain compliance report combining SBOM, audit, licenses, policy, integrity, and changelog sections.", inputSchema: MCProtocol::ToolInputSchema.new(properties: JSON::Any.new({"sections" => JSON::Any.new({"type" => JSON::Any.new("string"), "description" => JSON::Any.new("Comma-separated sections to include: sbom,audit,licenses,policy,integrity,changelog (default: all)")}), "reviewer" => JSON::Any.new({"type" => JSON::Any.new("string"), "description" => JSON::Any.new("Reviewer email for attestation")})}))), MCProtocol::Tool.new(name: "sbom", description: "Generate a Software Bill of Materials (SBOM) listing all dependencies with versions, licenses, and relationships.", inputSchema: MCProtocol::ToolInputSchema.new(properties: JSON::Any.new({"format" => JSON::Any.new({"type" => JSON::Any.new("string"), "enum" => JSON::Any.new(["spdx", "cyclonedx"].map do |s| JSON::Any.new(s) end), "description" => JSON::Any.new("SBOM format (default: spdx)")}), "include_dev" => JSON::Any.new({"type" => JSON::Any.new("boolean"), "description" => JSON::Any.new("Include development dependencies")})})))]`

## Constructors

### `new(path : String, interactive : Bool = false)`

## Class Methods

### `init_claude_config(path : String)`

### `init_mcp_config(path : String)`

### `run(path : String, args : Array(String) = [] of String)`

## Instance Methods

### `build_cli_args(tool_name : String, arguments : JSON::Any | Nil) : Array(String)`

Build CLI arguments from tool name and parameters

### `negotiate_version(client_version : String | Nil) : String`

Negotiate the best protocol version.
If the client requests a version we support, use it.
If the client requests a version newer than our latest, use our latest.
If the client requests an older version we don't support, use our oldest.
If no version is provided, use the latest.

### `run`

