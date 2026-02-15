# MCP Compliance Server

## Overview

The shards-alpha MCP compliance server exposes Crystal project supply-chain compliance tooling to AI agents through the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). It implements the JSON-RPC 2.0 over stdio transport, allowing MCP clients such as Claude Code, Cursor, and other LLM-powered development environments to invoke vulnerability audits, license checks, policy enforcement, dependency diffs, compliance reports, and SBOM generation directly from natural language conversations.

The server is implemented in `src/mcp/compliance_server.cr` as the `Shards::ComplianceMCPServer` class. It uses the [mcprotocol](https://github.com/nobodywasishere/mcprotocol) Crystal shard for MCP type definitions and advertises itself with the server name `shards-compliance`.

When a tool is called, the server delegates to the shards-alpha CLI by spawning a subprocess with the appropriate command and flags, capturing its stdout/stderr, and returning the result as structured JSON-RPC content. This architecture means the MCP server always produces the same output as the CLI commands it wraps.

---

## Quick Start

### 1. Initialize the MCP configuration

From your Crystal project root:

```bash
shards-alpha mcp-server init
```

This creates or updates `.mcp.json` in the current directory with the `shards-compliance` server entry.

For Claude Code skills, agents, and settings, also run:

```bash
shards-alpha assistant init
```

See `shards-alpha assistant --help` for component selection and update options.

### 2. Restart your MCP client

Restart Claude Code (or your MCP-compatible editor) so it discovers the new server in `.mcp.json`.

### 3. Use the tools

Ask your AI agent to use the compliance tools. For example:

- "Audit my dependencies for vulnerabilities"
- "Show me all dependency licenses"
- "Run a compliance report"
- "Generate an SBOM in CycloneDX format"
- "Diff the lockfile against the last commit"
- "Check dependencies against my policy"

The agent will automatically invoke the appropriate MCP tool and return structured results.

---

## Protocol Version Support

The server supports four MCP protocol versions, listed newest to oldest:

| Version | Notes |
|---|---|
| `2025-11-25` | Latest supported version (default) |
| `2025-06-18` | |
| `2025-03-26` | |
| `2024-11-05` | Initial MCP protocol version |

### Version negotiation

During the `initialize` handshake, the client sends a `protocolVersion` field indicating the version it wants to use. The server negotiates as follows:

1. **Exact match** -- If the client requests a version the server supports, that version is used.
2. **Client is newer** -- If the client requests a version newer than `2025-11-25`, the server responds with `2025-11-25` (its latest).
3. **Client is between versions** -- If the client requests a version that falls between two supported versions, the server selects the closest older supported version.
4. **Client is older than all** -- If the client requests a version older than all supported versions, the server falls back to `2024-11-05` (its oldest).
5. **No version provided** -- The server defaults to `2025-11-25`.

The negotiated version is returned in the `initialize` response's `protocolVersion` field.

---

## Tools Reference

The server exposes six tools. All tools produce JSON output (the server passes `--format=json` to the underlying CLI commands).

### audit

Scan dependencies for known vulnerabilities using the OSV database.

**Input schema:**

| Parameter | Type | Enum Values | Description |
|---|---|---|---|
| `severity` | `string` | `low`, `medium`, `high`, `critical` | Minimum severity filter |
| `fail_above` | `string` | `low`, `medium`, `high`, `critical` | Exit non-zero if vulnerabilities at or above this severity are found |
| `ignore` | `string` | -- | Comma-separated advisory IDs to suppress |
| `offline` | `boolean` | -- | Use cached vulnerability data only |

All parameters are optional.

**Example JSON-RPC request:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "audit",
    "arguments": {
      "severity": "high",
      "fail_above": "critical"
    }
  }
}
```

**Example JSON-RPC response:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"vulnerabilities\": [], \"summary\": {\"total\": 0}}"
      }
    ],
    "isError": false,
    "_meta": {
      "exit_code": 0
    }
  }
}
```

**CLI equivalent:**

```bash
shards-alpha audit --format=json --severity=high --fail-above=critical
```

**Note:** `audit` uses exit code 1 to signal "vulnerabilities found." The server treats this as a successful result (not an error) and includes the exit code in `_meta`.

---

### licenses

List all dependency licenses with SPDX identifier validation.

**Input schema:**

| Parameter | Type | Description |
|---|---|---|
| `check` | `boolean` | Exit non-zero if policy violations found |
| `detect` | `boolean` | Use heuristic detection from LICENSE files |
| `include_dev` | `boolean` | Include development dependencies |

All parameters are optional.

**Example JSON-RPC request:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "licenses",
    "arguments": {
      "check": true,
      "include_dev": true
    }
  }
}
```

**Example JSON-RPC response:**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"dependencies\": [{\"name\": \"molinillo\", \"license\": \"MIT\", \"spdx_valid\": true}]}"
      }
    ],
    "isError": false,
    "_meta": {
      "exit_code": 0
    }
  }
}
```

**CLI equivalent:**

```bash
shards-alpha licenses --format=json --check --include-dev
```

**Note:** Like `audit`, `licenses --check` uses exit code 1 to signal violations without being treated as a server error.

---

### policy_check

Check dependencies against policy rules defined in `.shards-policy.yml`.

**Input schema:**

| Parameter | Type | Description |
|---|---|---|
| `strict` | `boolean` | Treat warnings as errors |

All parameters are optional.

**Example JSON-RPC request:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "policy_check",
    "arguments": {
      "strict": true
    }
  }
}
```

**Example JSON-RPC response:**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"violations\": [], \"warnings\": [], \"passed\": true}"
      }
    ],
    "isError": false,
    "_meta": {
      "exit_code": 0
    }
  }
}
```

**CLI equivalent:**

```bash
shards-alpha policy check --format=json --strict
```

**Note:** `policy_check` uses exit code 1 to signal policy violations without being treated as a server error.

---

### diff

Show dependency changes between lockfile states.

**Input schema:**

| Parameter | Type | Description |
|---|---|---|
| `from` | `string` | Starting ref (git ref, file path, or `current`). Default: `HEAD` |
| `to` | `string` | Ending ref. Default: current working tree |

All parameters are optional.

**Example JSON-RPC request:**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "diff",
    "arguments": {
      "from": "v1.0.0",
      "to": "HEAD"
    }
  }
}
```

**Example JSON-RPC response:**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"added\": [], \"removed\": [], \"changed\": []}"
      }
    ],
    "isError": false,
    "_meta": {
      "exit_code": 0
    }
  }
}
```

**CLI equivalent:**

```bash
shards-alpha diff --format=json --from=v1.0.0 --to=HEAD
```

---

### compliance_report

Generate a unified supply chain compliance report combining multiple sections.

**Input schema:**

| Parameter | Type | Description |
|---|---|---|
| `sections` | `string` | Comma-separated sections to include: `sbom`, `audit`, `licenses`, `policy`, `integrity`, `changelog`. Default: all |
| `reviewer` | `string` | Reviewer email for attestation |

All parameters are optional.

**Example JSON-RPC request:**

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "tools/call",
  "params": {
    "name": "compliance_report",
    "arguments": {
      "sections": "audit,licenses,policy",
      "reviewer": "security@example.com"
    }
  }
}
```

**Example JSON-RPC response:**

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"report\": {\"sections\": [\"audit\", \"licenses\", \"policy\"], \"reviewer\": \"security@example.com\", ...}}"
      }
    ],
    "isError": false,
    "_meta": {
      "exit_code": 0
    }
  }
}
```

**CLI equivalent:**

```bash
shards-alpha compliance-report --format=json --sections=audit,licenses,policy --reviewer=security@example.com
```

---

### sbom

Generate a Software Bill of Materials (SBOM) listing all dependencies with versions, licenses, and relationships.

**Input schema:**

| Parameter | Type | Enum Values | Description |
|---|---|---|---|
| `format` | `string` | `spdx`, `cyclonedx` | SBOM format. Default: `spdx` |
| `include_dev` | `boolean` | -- | Include development dependencies |

All parameters are optional.

**Example JSON-RPC request:**

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "tools/call",
  "params": {
    "name": "sbom",
    "arguments": {
      "format": "cyclonedx",
      "include_dev": true
    }
  }
}
```

**Example JSON-RPC response:**

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "{\"bomFormat\": \"CycloneDX\", \"specVersion\": \"1.5\", \"components\": [...]}"
      }
    ],
    "isError": false,
    "structuredContent": {
      "bomFormat": "CycloneDX",
      "specVersion": "1.5",
      "components": []
    },
    "_meta": {
      "exit_code": 0
    }
  }
}
```

**CLI equivalent:**

```bash
shards-alpha sbom --format=cyclonedx --output=/dev/stdout --include-dev
```

**Note:** The SBOM tool always writes to `/dev/stdout` so the server can capture the output. When the CLI output is valid JSON, the response includes a `structuredContent` field with the parsed JSON in addition to the `content` text field.

---

## Setup and Configuration

### Automatic setup with `init`

The simplest way to configure the server:

```bash
shards-alpha mcp-server init
```

This command:

1. Looks for `shards-alpha` on `PATH`. If not found, falls back to the absolute path of the current binary.
2. Creates `.mcp.json` in the current directory (or merges into an existing one).
3. Adds the `shards-compliance` server entry.

The resulting `.mcp.json` looks like:

```json
{
  "mcpServers": {
    "shards-compliance": {
      "command": "shards-alpha",
      "args": [
        "mcp-server"
      ]
    }
  }
}
```

If `.mcp.json` already exists and contains a `shards-compliance` entry, the command prints a message and does nothing.

If `.mcp.json` already exists with other servers, `init` merges the new entry into the existing `mcpServers` object without disturbing other entries.

### Manual setup

You can create or edit `.mcp.json` by hand. The minimum required structure is shown above. The `command` value should be the path to or name of the `shards-alpha` binary, and `args` must include `mcp-server`.

### After setup

After creating or modifying `.mcp.json`, restart your MCP client (e.g., Claude Code) for it to discover the new server.

---

## Interactive Mode

For manual testing and debugging, run the server in interactive mode:

```bash
shards-alpha mcp-server --interactive
```

Interactive mode:

- Prints a `>` prompt to stderr and waits for JSON-RPC input on stdin.
- Pretty-prints JSON responses to stdout (indented, human-readable).
- Supports the `help` command to show example JSON-RPC messages.
- Supports `quit` or `exit` to terminate.

### Interactive help

Typing `help` at the prompt displays example messages for `initialize`, `tools/list`, and `tools/call`:

```
> help

Example messages:

  Initialize:
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}

  List tools:
    {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}

  Call audit:
    {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"audit","arguments":{}}}

  Call licenses:
    {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"licenses","arguments":{}}}
```

### Example interactive session

```
$ shards-alpha mcp-server --interactive
shards-compliance MCP server v2.0.0 (interactive)
Supported MCP versions: 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05
Type JSON-RPC messages, 'help' for examples, or 'quit' to exit.

> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-11-25",
    "capabilities": {
      "tools": {}
    },
    "serverInfo": {
      "name": "shards-compliance",
      "version": "2.0.0"
    }
  }
}

> {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [ ... ]
  }
}

> quit
Goodbye!
```

---

## Help

Display the built-in help text:

```bash
shards-alpha mcp-server --help
```

or:

```bash
shards-alpha mcp-server -h
```

Output:

```
shards-alpha mcp-server — MCP compliance server (JSON-RPC 2.0 over stdio)

Usage:
    shards-alpha mcp-server [command] [options]

Commands:
    init               Configure .mcp.json for MCP server
    (default)          Start the MCP server (stdio transport)

Options:
    --interactive    Run in interactive mode for manual testing
    --help, -h       Show this help message

Tools provided:
    audit              Scan dependencies for known vulnerabilities (OSV)
    licenses           List dependency licenses with SPDX validation
    policy_check       Check dependencies against policy rules
    diff               Show dependency changes between lockfile states
    compliance_report  Generate unified compliance report
    sbom               Generate Software Bill of Materials (SPDX/CycloneDX)

Examples:
    shards-alpha mcp-server init          # Configure .mcp.json
    shards-alpha mcp-server               # Start server (for MCP clients)
    shards-alpha mcp-server --interactive  # Manual testing mode

For Claude Code skills, agents, and settings, use:
    shards-alpha assistant init
```

---

## Architecture

### Subprocess execution model

The MCP server does not implement audit, license scanning, or SBOM generation directly. Instead, it acts as a thin JSON-RPC adapter in front of the shards-alpha CLI:

```
MCP Client  <--stdio-->  ComplianceMCPServer  <--subprocess-->  shards-alpha <command>
```

When a `tools/call` request arrives:

1. The server maps the tool name and arguments to a CLI command with appropriate flags (via `build_cli_args`).
2. It spawns a subprocess using `Process.run`, passing the assembled arguments.
3. Stdout and stderr from the subprocess are captured into `IO::Memory` buffers.
4. The exit code is captured.
5. If the output is valid JSON, it is included as `structuredContent` in the response alongside the text content.
6. The response is sent back over stdio.

### Executable discovery

The server resolves the shards-alpha executable in the following order:

1. `Process.executable_path` -- the running binary itself.
2. `Process.find_executable("shards-alpha")` -- look up on PATH.
3. `Process.find_executable("shards")` -- fall back to upstream shards.

If none of these succeed, the server raises an error.

### Stdio transport

The server uses synchronous line-delimited JSON-RPC over stdin/stdout:

- **stdin**: One JSON-RPC message per line.
- **stdout**: One JSON-RPC response per line (compact JSON in stdio mode, pretty-printed in interactive mode).
- **stderr**: Diagnostic messages (server version, startup info, errors). Stderr is used for logging because MCP clients read only stdout for protocol messages.

All three streams are set to `sync = true` to disable buffering.

### Supported JSON-RPC methods

| Method | Description |
|---|---|
| `initialize` | Protocol handshake with version negotiation |
| `notifications/initialized` | Post-handshake notification (no response) |
| `ping` | Health check, returns empty result |
| `tools/list` | Return the list of available tools with schemas |
| `tools/call` | Invoke a tool with arguments |

### Tool-to-CLI mapping

| MCP Tool | CLI Command | Implicit Flags |
|---|---|---|
| `audit` | `shards-alpha audit` | `--format=json` |
| `licenses` | `shards-alpha licenses` | `--format=json` |
| `policy_check` | `shards-alpha policy check` | `--format=json` |
| `diff` | `shards-alpha diff` | `--format=json` |
| `compliance_report` | `shards-alpha compliance-report` | `--format=json` |
| `sbom` | `shards-alpha sbom` | `--output=/dev/stdout` |

### Expected non-zero exit codes

Some tools use exit code 1 to communicate a meaningful result rather than an error:

- **audit**: exit 1 means vulnerabilities were found.
- **licenses** (with `--check`): exit 1 means license policy violations were found.
- **policy_check**: exit 1 means policy violations were found.

The server recognizes these cases and sets `isError: false` in the response, including the actual exit code in the `_meta` object.

---

## Error Handling

The server uses standard JSON-RPC 2.0 error codes:

### -32700: Parse Error

Returned when the incoming message is not valid JSON.

```json
{
  "jsonrpc": "2.0",
  "id": null,
  "error": {
    "code": -32700,
    "message": "Parse error: Unexpected char 'x' at line 1, column 1"
  }
}
```

### -32601: Method Not Found

Returned when the `method` field does not match any supported method.

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "error": {
    "code": -32601,
    "message": "Method not found: resources/list"
  }
}
```

### -32602: Invalid Params

Returned when required parameters are missing or a tool name is unrecognized.

Missing tool name:

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "error": {
    "code": -32602,
    "message": "Missing tool name"
  }
}
```

Unknown tool:

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "error": {
    "code": -32602,
    "message": "Unknown tool: nonexistent"
  }
}
```

### -32603: Internal Error

Returned when an unexpected exception occurs during message handling.

```json
{
  "jsonrpc": "2.0",
  "id": 8,
  "error": {
    "code": -32603,
    "message": "Internal error: Could not find shards-alpha executable"
  }
}
```

### Error handling flow

1. The outer `handle_message` method wraps all processing in a rescue block.
2. `JSON::ParseException` is caught and mapped to `-32700`.
3. All other exceptions are caught and mapped to `-32603`, with the server attempting to extract the request `id` for correlation.
4. Notifications (methods without an `id`) that fail silently -- no error response is sent for unknown notifications.

---

## Integration with MCP Lifecycle

The `shards-alpha mcp-server` command and the `shards-alpha mcp` lifecycle commands serve complementary roles:

### `shards-alpha mcp-server` (this server)

- The **built-in** MCP compliance server bundled with shards-alpha.
- Provides supply-chain compliance tools (audit, licenses, policy, etc.).
- Configured via `shards-alpha mcp-server init` which writes to `.mcp.json`.
- Run directly by MCP clients as a subprocess (stdio transport).

### `shards-alpha mcp` (lifecycle manager)

- Manages **third-party** MCP servers distributed through shard dependencies.
- Handles starting, stopping, restarting, and log tailing for servers defined in `.mcp-shards.json`.
- Operates as a background process manager (PID tracking, health checks, graceful shutdown).

### How they relate

The lifecycle manager (`shards mcp start/stop/logs`) is designed for MCP servers that come from **dependencies** -- when a shard ships an `.mcp.json` with its own tools, `shards install` merges them into `.mcp-shards.json`, and `shards mcp start` launches them as managed background processes.

The compliance server (`shards mcp-server`) is the **first-party** server built directly into shards-alpha. It does not need the lifecycle manager because MCP clients launch it directly as a subprocess via the `.mcp.json` configuration.

Both write to `.mcp.json` but with different server names: the compliance server registers as `shards-compliance`, while dependency servers are namespaced by their shard name (e.g., `my_shard/explorer`).

### Typical project setup

A project might use both:

```json
{
  "mcpServers": {
    "shards-compliance": {
      "command": "shards-alpha",
      "args": ["mcp-server"]
    },
    "analytics_shard/query-tool": {
      "command": "lib/analytics_shard/bin/mcp-server",
      "args": ["--stdio"]
    }
  }
}
```

Here, `shards-compliance` is managed by the MCP client directly, while `analytics_shard/query-tool` can be managed through `shards mcp start/stop/logs`.
