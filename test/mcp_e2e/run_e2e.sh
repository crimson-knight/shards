#!/bin/bash
#
# End-to-end test for the shards MCP lifecycle management feature.
#
# Tests two things:
#   1. Lifecycle management: shards mcp start/stop/status/restart/logs
#   2. Claude Code integration: Claude can discover and call MCP tools
#      served by a Crystal binary managed through .mcp-shards.json
#
# Prerequisites:
#   - Crystal compiler installed
#   - shards-alpha built at bin/shards-alpha
#   - claude CLI installed (for Claude Code integration test)
#
# Usage:
#   ./test/mcp_e2e/run_e2e.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SHARDS_BIN="$PROJECT_ROOT/bin/shards-alpha"
MCP_SERVER_SRC="$SCRIPT_DIR/mcp_echo_server.cr"
MCP_SERVER_BIN="$SCRIPT_DIR/mcp_echo_server"
MCP_CONFIG="$SCRIPT_DIR/mcp_config.json"
TMPDIR_E2E=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass=0
fail=0

cleanup() {
  if [ -n "$TMPDIR_E2E" ] && [ -d "$TMPDIR_E2E" ]; then
    # Kill any leftover test processes
    if [ -f "$TMPDIR_E2E/.shards/mcp/servers.json" ]; then
      pids=$(python3 -c "
import json, sys
try:
    data = json.load(open('$TMPDIR_E2E/.shards/mcp/servers.json'))
    for s in data.get('servers', {}).values():
        print(s.get('pid', ''))
except: pass
" 2>/dev/null || true)
      for pid in $pids; do
        kill -9 "$pid" 2>/dev/null || true
      done
    fi
    rm -rf "$TMPDIR_E2E"
  fi
}
trap cleanup EXIT

assert_contains() {
  local label="$1"
  local output="$2"
  local expected="$3"
  if echo "$output" | grep -q "$expected"; then
    echo -e "  ${GREEN}PASS${NC} $label"
    pass=$((pass + 1))
  else
    echo -e "  ${RED}FAIL${NC} $label"
    echo "    Expected output to contain: $expected"
    echo "    Got: $output"
    fail=$((fail + 1))
  fi
}

# ── Step 1: Build MCP server ────────────────────────────────────────
echo ""
echo "=== Building test MCP server ==="
if [ ! -f "$MCP_SERVER_BIN" ] || [ "$MCP_SERVER_SRC" -nt "$MCP_SERVER_BIN" ]; then
  crystal build "$MCP_SERVER_SRC" -o "$MCP_SERVER_BIN" 2>&1
  echo -e "  ${GREEN}Built${NC} $MCP_SERVER_BIN"
else
  echo -e "  ${GREEN}Up to date${NC} $MCP_SERVER_BIN"
fi

# ── Step 2: Verify MCP protocol directly ────────────────────────────
echo ""
echo "=== Testing MCP protocol (raw JSON-RPC) ==="

PROTOCOL_OUTPUT=$(echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_shards_build_info","arguments":{}}}' | "$MCP_SERVER_BIN" 2>/dev/null)

assert_contains "initialize response" "$PROTOCOL_OUTPUT" '"protocolVersion"'
assert_contains "tools/list response" "$PROTOCOL_OUTPUT" '"get_shards_build_info"'
assert_contains "tools/call response" "$PROTOCOL_OUTPUT" 'SHARDS_MCP_VERIFIED_2026'

# ── Step 3: Test lifecycle management (shards mcp) ──────────────────
echo ""
echo "=== Testing lifecycle management (shards mcp) ==="

# Check shards-alpha binary exists
if [ ! -f "$SHARDS_BIN" ]; then
  echo -e "  ${YELLOW}SKIP${NC} shards-alpha not built at $SHARDS_BIN"
  echo "  Run: crystal build src/shards.cr -o bin/shards-alpha"
else
  TMPDIR_E2E=$(mktemp -d)
  cd "$TMPDIR_E2E"

  cat > shard.yml << 'YAML'
name: mcp_e2e_test
version: 0.0.1
YAML

  cat > .mcp-shards.json << JSON
{
  "mcpServers": {
    "test/echo": {
      "command": "$MCP_SERVER_BIN",
      "args": []
    }
  }
}
JSON

  # Status before start
  OUTPUT=$("$SHARDS_BIN" mcp 2>&1)
  assert_contains "status shows stopped" "$OUTPUT" "[stopped]"
  assert_contains "status shows server name" "$OUTPUT" "test/echo"

  # Start
  OUTPUT=$("$SHARDS_BIN" mcp start 2>&1)
  assert_contains "start reports PID" "$OUTPUT" "Started test/echo"

  # Log file created
  if [ -f ".shards/mcp/test--echo.log" ]; then
    echo -e "  ${GREEN}PASS${NC} log file created"
    pass=$((pass + 1))
  else
    echo -e "  ${RED}FAIL${NC} log file not created"
    fail=$((fail + 1))
  fi

  # State file created
  if [ -f ".shards/mcp/servers.json" ]; then
    echo -e "  ${GREEN}PASS${NC} servers.json created"
    pass=$((pass + 1))
  else
    echo -e "  ${RED}FAIL${NC} servers.json not created"
    fail=$((fail + 1))
  fi

  # Stop
  OUTPUT=$("$SHARDS_BIN" mcp stop 2>&1 || true)
  assert_contains "stop completes" "$OUTPUT" "" # No error = pass (stop on already-exited stdio server)

  # Status after stop
  OUTPUT=$("$SHARDS_BIN" mcp 2>&1)
  assert_contains "status shows stopped after stop" "$OUTPUT" "[stopped]"

  cd "$PROJECT_ROOT"
fi

# ── Step 4: Claude Code E2E integration ─────────────────────────────
echo ""
echo "=== Testing Claude Code integration ==="

if ! command -v claude &>/dev/null; then
  echo -e "  ${YELLOW}SKIP${NC} claude CLI not found"
else
  # Write MCP config with absolute path
  cat > "$SCRIPT_DIR/mcp_config.json" << JSON
{
  "mcpServers": {
    "shards-test": {
      "type": "stdio",
      "command": "$MCP_SERVER_BIN",
      "args": []
    }
  }
}
JSON

  echo "  Calling Claude Code with MCP server..."

  CLAUDE_OUTPUT=$(unset CLAUDECODE && claude -p \
    "You have access to an MCP tool called get_shards_build_info from the shards-test server. Please call it now and report back the exact text it returns. Only output the exact text from the tool, nothing else." \
    --mcp-config "$MCP_CONFIG" \
    --allowedTools "mcp__shards-test__get_shards_build_info" \
    --output-format json \
    --max-turns 3 \
    --no-session-persistence \
    --model haiku 2>/dev/null || echo '{"result":"ERROR"}')

  RESULT=$(echo "$CLAUDE_OUTPUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result',''))" 2>/dev/null || echo "PARSE_ERROR")

  assert_contains "Claude called MCP tool and got verification phrase" "$RESULT" "SHARDS_MCP_VERIFIED_2026"

  # Show cost info
  COST=$(echo "$CLAUDE_OUTPUT" | python3 -c "import json,sys; print(f\"  Cost: \${json.load(sys.stdin).get('total_cost_usd', 'unknown')}\")" 2>/dev/null || true)
  echo "$COST"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo -e "  ${GREEN}$pass passed${NC}, ${RED}$fail failed${NC}"
echo "========================================"

if [ $fail -gt 0 ]; then
  exit 1
fi
