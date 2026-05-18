#!/usr/bin/env bash
# Wrapper that runs the GhidraMCP Python bridge using the venv's interpreter.
# Forwards all CLI args to bridge_mcp_ghidra.py.
#
# Default mode is stdio (for Claude Desktop / Claude Code / gemini-cli).
# For Ollama (Open WebUI), pass SSE flags, e.g.:
#   ./run-bridge.sh --transport sse --mcp-host 127.0.0.1 --mcp-port 8081 \
#       --ghidra-server http://127.0.0.1:8080/
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PY="$SCRIPT_DIR/venv/bin/python"
BRIDGE="$SCRIPT_DIR/GhidraMCP/bridge_mcp_ghidra.py"

if [ ! -x "$PY" ]; then
  echo "venv not found at $PY — run ./install.sh first" >&2
  exit 1
fi
if [ ! -f "$BRIDGE" ]; then
  echo "bridge not found at $BRIDGE — run ./install.sh first" >&2
  exit 1
fi

# Default: connect to a Ghidra plugin running on localhost:8080.
# Users can override by passing their own --ghidra-server flag.
if ! printf '%s\0' "$@" | grep -qz -- '--ghidra-server'; then
  set -- "$@" --ghidra-server "http://127.0.0.1:8080/"
fi

exec "$PY" "$BRIDGE" "$@"
