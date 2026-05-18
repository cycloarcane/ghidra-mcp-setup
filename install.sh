#!/usr/bin/env bash
# ghidra-mcp-setup installer
# Clones the LaurieWired/GhidraMCP bridge, builds a Python venv,
# fetches the latest Ghidra plugin ZIP, and generates ready-to-paste
# MCP client configs.
#
# Env overrides:
#   GHIDRAMCP_REPO   upstream git URL    (default: https://github.com/LaurieWired/GhidraMCP.git)
#   GHIDRAMCP_REF    pin to tag/branch/sha (default: empty = upstream default branch)
#   GHIDRAMCP_OWNER  GitHub owner/repo for release fetch (default: LaurieWired/GhidraMCP)
#   GHIDRA_PORT      Ghidra plugin HTTP port    (default: 8080)
#                    Set to e.g. 9090 if 8080 is taken (Open WebUI, etc.).
#                    Must match the port configured in Ghidra's plugin options.
#   MCP_SSE_PORT     bridge SSE listen port for Open WebUI path (default: 8081)
#
# Flags:
#   --update    pull latest upstream into existing GhidraMCP checkout
#               (default: leave existing checkout alone — reproducibility over freshness)
#
# Security posture: see SECURITY.md.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

GHIDRAMCP_REPO="${GHIDRAMCP_REPO:-https://github.com/LaurieWired/GhidraMCP.git}"
GHIDRAMCP_REF="${GHIDRAMCP_REF:-}"
GHIDRAMCP_OWNER="${GHIDRAMCP_OWNER:-LaurieWired/GhidraMCP}"
GHIDRA_PORT="${GHIDRA_PORT:-8080}"
MCP_SSE_PORT="${MCP_SSE_PORT:-8081}"
MCPO_PORT="${MCPO_PORT:-8000}"

# Validate ports look like sensible integers (not user-attacker-controlled here,
# but we splice these into generated configs so a non-numeric value would write
# broken JSON. Fail loud instead of silently producing garbage.)
for portname in GHIDRA_PORT MCP_SSE_PORT MCPO_PORT; do
  portval="${!portname}"
  if ! [[ "$portval" =~ ^[0-9]+$ ]] || [ "$portval" -lt 1 ] || [ "$portval" -gt 65535 ]; then
    echo "[-] $portname='$portval' is not a valid TCP port" >&2
    exit 2
  fi
done

GHIDRA_SERVER_URL="http://127.0.0.1:${GHIDRA_PORT}/"
UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --update) UPDATE=1 ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ─── pretty output ─────────────────────────────────────────────────────────
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; NC=""
fi
info() { printf "%s[*]%s %s\n" "$BLUE" "$NC" "$1"; }
ok()   { printf "%s[+]%s %s\n" "$GREEN" "$NC" "$1"; }
warn() { printf "%s[!]%s %s\n" "$YELLOW" "$NC" "$1"; }
err()  { printf "%s[-]%s %s\n" "$RED" "$NC" "$1" >&2; }

# ─── prerequisite checks ───────────────────────────────────────────────────
need() {
  command -v "$1" >/dev/null 2>&1 || { err "$1 not found in PATH"; return 1; }
}

info "Checking prerequisites..."

MISSING=0
need git     || MISSING=1
need python3 || MISSING=1
need curl    || MISSING=1
[ "$MISSING" -eq 1 ] && { err "Install missing prerequisites and re-run."; exit 1; }

# Java check (warn-only; only needed when actually running Ghidra)
if command -v java >/dev/null 2>&1; then
  JAVA_VER=$(java -version 2>&1 | awk -F\" '/version/ {print $2}' | cut -d. -f1 || echo "?")
  # Guard against non-numeric (e.g. "?" or "1") before numeric compare
  if ! [[ "$JAVA_VER" =~ ^[0-9]+$ ]] || [ "$JAVA_VER" -lt 21 ]; then
    warn "Java '$JAVA_VER' detected; Ghidra 11.3+ requires JDK 21+. Install with your package manager when ready to run Ghidra."
  else
    ok "Java $JAVA_VER"
  fi
else
  warn "Java not installed. Install JDK 21+ before running Ghidra (e.g. 'sudo apt install openjdk-21-jdk' or 'sudo pacman -S jdk21-openjdk')."
fi

PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
ok "Python $PY_VER"

# Detect user shell for the final hint
USER_SHELL=$(basename "${SHELL:-/bin/bash}")
ok "Detected shell: $USER_SHELL"

# ─── clone the bridge ──────────────────────────────────────────────────────
if [ ! -d "GhidraMCP/.git" ]; then
  info "Cloning $GHIDRAMCP_REPO ..."
  git clone --depth 1 ${GHIDRAMCP_REF:+--branch "$GHIDRAMCP_REF"} "$GHIDRAMCP_REPO" GhidraMCP
elif [ "$UPDATE" -eq 1 ]; then
  info "Updating existing GhidraMCP checkout (--update)..."
  git -C GhidraMCP fetch --depth 1 origin "${GHIDRAMCP_REF:-HEAD}"
  git -C GhidraMCP reset --hard FETCH_HEAD
else
  info "GhidraMCP already cloned — leaving as-is (pass --update to refresh)"
fi
GHIDRA_COMMIT=$(git -C GhidraMCP rev-parse --short HEAD 2>/dev/null || echo "unknown")
ok "Bridge source ready (commit $GHIDRA_COMMIT)"

# ─── python venv ───────────────────────────────────────────────────────────
if [ ! -d "venv" ]; then
  info "Creating Python venv at ./venv ..."
  python3 -m venv venv
fi
ok "venv ready"

info "Installing bridge dependencies into venv..."
./venv/bin/pip install --quiet --upgrade pip
if [ -f "GhidraMCP/requirements.txt" ]; then
  ./venv/bin/pip install --quiet -r GhidraMCP/requirements.txt
  ok "Dependencies installed (from GhidraMCP/requirements.txt)"
else
  # Fallback if upstream layout changes
  ./venv/bin/pip install --quiet mcp requests
  warn "No requirements.txt in GhidraMCP — installed mcp + requests as fallback"
fi

# mcpo: MCP-to-OpenAPI proxy by the Open WebUI team. Only the Open WebUI path
# needs this — Open WebUI's "Tools" feature consumes OpenAPI, not raw MCP/SSE.
# Cheap to install for everyone; users on Claude/gemini-cli paths just ignore it.
./venv/bin/pip install --quiet mcpo
ok "mcpo installed (for the Open WebUI / Ollama path)"

# ─── fetch + unwrap the Ghidra plugin release ──────────────────────────────
#
# Upstream ships a wrapper: GhidraMCP-release-N-N.zip contains an inner
# GhidraMCP-N-N.zip which is the file Ghidra's "Install Extensions" UI
# actually wants. We download the outer, then extract the inner. Both steps
# are independent and idempotent: re-runs heal partial state.
mkdir -p extensions

# Step A: ensure the outer release ZIP is on disk.
OUTER=$(ls extensions/GhidraMCP-release-*.zip 2>/dev/null | head -1 || true)
# Also count a non-release-prefixed ZIP as "already have it" — covers cases
# where upstream stops using the wrapper in a future release.
ANY_INNER=$(ls extensions/GhidraMCP-[0-9]*.zip 2>/dev/null | head -1 || true)

if [ -z "$OUTER" ] && [ -z "$ANY_INNER" ]; then
  info "Fetching latest GhidraMCP release ZIP from GitHub..."
  RELEASE_API="https://api.github.com/repos/${GHIDRAMCP_OWNER}/releases/latest"
  RELEASE_JSON=$(curl -fsSL "$RELEASE_API" || true)

  RELEASE_URL=""
  if command -v jq >/dev/null 2>&1; then
    RELEASE_URL=$(printf "%s" "$RELEASE_JSON" | jq -r '.assets[]?.browser_download_url | select(test("GhidraMCP-.*\\.zip$"))' | head -1 || true)
  else
    RELEASE_URL=$(printf "%s" "$RELEASE_JSON" \
      | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+GhidraMCP-[^"]+\.zip"' \
      | head -1 | cut -d'"' -f4 || true)
  fi

  # Validate URL: must be HTTPS, on github.com, in the expected repo's release path,
  # and the filename must match GhidraMCP-*.zip. Refuse anything else.
  EXPECTED_PREFIX="https://github.com/${GHIDRAMCP_OWNER}/releases/download/"
  FNAME=""
  if [ -n "${RELEASE_URL:-}" ]; then
    case "$RELEASE_URL" in
      "${EXPECTED_PREFIX}"*)
        FNAME=$(basename "$RELEASE_URL")
        if ! [[ "$FNAME" =~ ^GhidraMCP-[A-Za-z0-9._-]+\.zip$ ]]; then
          warn "Release filename '$FNAME' didn't match expected pattern — refusing to download."
          RELEASE_URL=""
        fi
        ;;
      *)
        warn "Release URL '$RELEASE_URL' didn't start with $EXPECTED_PREFIX — refusing to download."
        RELEASE_URL=""
        ;;
    esac
  fi

  if [ -n "${RELEASE_URL:-}" ] && [ -n "$FNAME" ]; then
    TMP=$(mktemp -p extensions ".dl-XXXXXX.zip")
    if curl -fsSL --proto '=https' --tlsv1.2 -o "$TMP" "$RELEASE_URL"; then
      mv "$TMP" "extensions/$FNAME"
      ok "Downloaded extensions/$FNAME"
      if command -v sha256sum >/dev/null 2>&1; then
        HASH=$(sha256sum "extensions/$FNAME" | awk '{print $1}')
        info "SHA256: $HASH"
        info "Verify out-of-band against https://github.com/${GHIDRAMCP_OWNER}/releases"
      fi
      OUTER="extensions/$FNAME"
    else
      rm -f "$TMP"
      warn "Download failed. Fetch the ZIP manually from"
      warn "  https://github.com/${GHIDRAMCP_OWNER}/releases"
      warn "and drop it into ./extensions/"
    fi
  else
    warn "Could not resolve a trusted release URL. Fetch manually from"
    warn "  https://github.com/${GHIDRAMCP_OWNER}/releases"
    warn "and drop the ZIP into ./extensions/"
  fi
else
  [ -n "$OUTER" ] && info "Outer release ZIP already present: $OUTER"
fi

# Step B: extract the inner extension ZIP from the outer wrapper, if needed.
# Idempotent — skip if a non-wrapper GhidraMCP-*.zip is already in extensions/.
INNER_ZIP=$(ls extensions/GhidraMCP-[0-9]*.zip 2>/dev/null | head -1 || true)
if [ -z "$INNER_ZIP" ] && [ -n "$OUTER" ]; then
  info "Extracting inner extension ZIP from $OUTER ..."
  INNER=$(python3 - "$OUTER" extensions <<'PY'
import sys, os, zipfile
src, outdir = sys.argv[1], sys.argv[2]
try:
    with zipfile.ZipFile(src) as z:
        for info in z.infolist():
            bn = os.path.basename(info.filename)
            # Want an inner extension ZIP: starts GhidraMCP-, ends .zip,
            # and isn't the outer wrapper itself.
            if (bn.lower().startswith("ghidramcp-")
                    and bn.lower().endswith(".zip")
                    and "release" not in bn.lower()
                    and bn != os.path.basename(src)):
                dst = os.path.join(outdir, bn)
                with z.open(info) as f, open(dst, "wb") as out:
                    out.write(f.read())
                with zipfile.ZipFile(dst):  # sanity-check it's a valid zip
                    pass
                print(bn)
                break
except Exception as e:
    print(f"ERR:{e}", file=sys.stderr)
PY
)
  if [ -n "$INNER" ]; then
    INNER_ZIP="extensions/$INNER"
    ok "Extracted $INNER_ZIP"
  else
    warn "No inner extension ZIP found inside $OUTER — point Ghidra at $OUTER directly and see if it accepts it."
  fi
fi

# Step C: pick the plugin ZIP path to advertise in the final summary.
# Prefer the inner extension; fall back to the outer wrapper if extraction failed.
PLUGIN_ZIP="${INNER_ZIP:-$OUTER}"

# ─── generate client configs with absolute paths ───────────────────────────
mkdir -p configs/generated
BRIDGE="$SCRIPT_DIR/run-bridge.sh"
PY="$SCRIPT_DIR/venv/bin/python"
SCRIPT="$SCRIPT_DIR/GhidraMCP/bridge_mcp_ghidra.py"

# Claude Desktop / Claude Code / gemini-cli all use the same mcpServers shape.
cat > configs/generated/claude-desktop.json <<EOF
{
  "mcpServers": {
    "ghidra": {
      "command": "$PY",
      "args": [
        "$SCRIPT",
        "--ghidra-server",
        "$GHIDRA_SERVER_URL"
      ]
    }
  }
}
EOF

cat > configs/generated/gemini-cli.json <<EOF
{
  "mcpServers": {
    "ghidra": {
      "command": "$PY",
      "args": [
        "$SCRIPT",
        "--ghidra-server",
        "$GHIDRA_SERVER_URL"
      ]
    }
  }
}
EOF

cat > configs/generated/claude-code.mcp.json <<EOF
{
  "mcpServers": {
    "ghidra": {
      "type": "stdio",
      "command": "$PY",
      "args": [
        "$SCRIPT",
        "--ghidra-server",
        "$GHIDRA_SERVER_URL"
      ]
    }
  }
}
EOF

cat > configs/generated/ollama-openwebui.txt <<EOF
# Ollama via Open WebUI
# =====================
# Open WebUI's "Tools" feature consumes OpenAPI, not raw MCP/SSE. The bridge
# alone won't work — pointing OWUI at /sse returns 404 on /sse/openapi.json.
# Use mcpo (MCP-to-OpenAPI proxy by the Open WebUI team) in front of it.
#
# Ports (override with MCPO_PORT=... GHIDRA_PORT=... ./install.sh):
#   GHIDRA_PORT = $GHIDRA_PORT   (Ghidra plugin HTTP — must match Ghidra options)
#   MCPO_PORT   = $MCPO_PORT     (OpenAPI proxy Open WebUI talks to)
#
# Note: Open WebUI itself binds 8080 by default — keep GHIDRA_PORT off 8080.
#
# Start the proxy + bridge as one process:
$SCRIPT_DIR/venv/bin/mcpo --port $MCPO_PORT -- \\
    $SCRIPT_DIR/venv/bin/python \\
    $SCRIPT_DIR/GhidraMCP/bridge_mcp_ghidra.py \\
    --ghidra-server $GHIDRA_SERVER_URL
#
# Then in Open WebUI: Settings → Tools → "+"
#   URL:  http://127.0.0.1:$MCPO_PORT
#   (OWUI auto-discovers the schema at /openapi.json)
EOF
# Drop a stale SSE-mode hint from earlier installs so users don't follow it
rm -f configs/generated/ollama-openwebui.sse.txt

ok "Generated client configs in configs/generated/ (Ghidra port: $GHIDRA_PORT)"

# ─── done ──────────────────────────────────────────────────────────────────
echo
printf "%s%sInstallation complete.%s\n" "$BOLD" "$GREEN" "$NC"
echo
echo "Next steps:"
echo "  1. Install the Ghidra plugin:"
if [ -n "${PLUGIN_ZIP:-}" ]; then
  echo "       Ghidra → File → Install Extensions → (+)"
  echo "       Select: $SCRIPT_DIR/$PLUGIN_ZIP"
  echo "       Restart Ghidra, then: Code Browser → File → Configure → Developer → tick GhidraMCPPlugin"
  echo
  echo "     If Ghidra shows 'Extension Version Mismatch' (e.g. plugin built for 11.3.2"
  echo "     vs your Ghidra 12.x), click 'Install Anyway'. The bridge uses stable APIs"
  echo "     and usually works across minor versions. If the plugin fails to load after"
  echo "     restart, see the Version mismatch section in TUTORIAL.md."
else
  echo "       (No plugin ZIP detected in ./extensions/ — download it manually first.)"
fi
echo
echo "  2. Wire up your MCP client (pick one):"
echo "       Claude Desktop  →  configs/generated/claude-desktop.json"
echo "       Claude Code     →  configs/generated/claude-code.mcp.json"
echo "       gemini-cli      →  configs/generated/gemini-cli.json"
echo "       Ollama (WebUI)  →  configs/generated/ollama-openwebui.txt"
echo
echo "     See TUTORIAL.md for exactly where to drop each one."
echo
echo "  3. If you need to enter the venv manually:"
case "$USER_SHELL" in
  fish) printf "       %ssource %s/venv/bin/activate.fish%s\n" "$BOLD" "$SCRIPT_DIR" "$NC" ;;
  *)    printf "       %ssource %s/venv/bin/activate%s\n"      "$BOLD" "$SCRIPT_DIR" "$NC" ;;
esac
echo "     (or just use ./run-bridge.sh, which calls the venv's python directly)"
echo
