# Ghidra MCP — Getting Started Guide
### AI-Assisted Reverse Engineering on Kali Linux

---

## What Is Ghidra MCP?

Ghidra MCP bridges Ghidra's static analysis engine with LLMs via the **Model Context Protocol (MCP)** — the same standard that lets Claude talk to external tools. The result: an AI that can autonomously read disassembly, rename functions, add comments, query cross-references, and reason about binary behaviour in real time, without you copy-pasting anything.

Two architectures exist:

| Mode | How it works | Best for |
|---|---|---|
| **GUI Plugin** | Plugin runs inside Ghidra; exposes an HTTP/SSE server | Interactive analysis sessions |
| **Headless (pyghidra-mcp)** | CLI server; no GUI needed; entire project exposed | Automation, multi-binary, CI pipelines |

---

## Choosing a Plugin

Three main implementations, each with a different scope:

### 1. LaurieWired/GhidraMCP ⭐ (recommended starting point)
- Original and most widely documented
- Clean two-part architecture: **Ghidra plugin** (Java) + **Python MCP bridge**
- Works with Claude Desktop, Cline, 5ire, any MCP client
- `github.com/LaurieWired/GhidraMCP`

### 2. bethington/ghidra-mcp (most feature-rich)
- 243 MCP tools — full read/write: rename, retype, comment, structure creation, P-code emulation, live debugger integration
- Production-hardened; localhost-only by default with optional bearer token auth
- `github.com/bethington/ghidra-mcp`

### 3. clearbluejar/pyghidra-mcp (headless / multi-binary)
- Exposes an **entire Ghidra project** through one MCP interface
- Traces function calls across multiple interdependent binaries in a single session
- Powered by `pyghidra` + `jpype`; no GUI required
- `github.com/clearbluejar/pyghidra-mcp`

> **Recommendation:** Start with **LaurieWired** to get the mental model, then move to **bethington** for real work. Use **pyghidra-mcp** once you're doing multi-binary or automated analysis.

---

## Prerequisites

```bash
# Kali already has Java but verify version (Ghidra requires JDK 21+)
java -version

# Install JDK 21 if needed
sudo apt install openjdk-21-jdk

# Python 3.9+ (should already be present)
python3 --version

# Install uv (fast package manager, preferred over pip for MCP tools)
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Download Ghidra from the NSA releases page if not already installed:
```bash
# https://github.com/NationalSecurityAgency/ghidra/releases
# Use version 11.3.x or later
wget https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.3.2_build/ghidra_11.3.2_PUBLIC_20250415.zip
unzip ghidra_11.3.2_PUBLIC_20250415.zip -d ~/tools/
```

---

## Setup: LaurieWired/GhidraMCP

### Step 1 — Install the Ghidra Plugin

1. Download the latest release ZIP from `github.com/LaurieWired/GhidraMCP/releases`
2. Launch Ghidra: `~/tools/ghidra_11.3.2_PUBLIC/ghidraRun`
3. **File → Install Extensions → (+)**
4. Select the plugin ZIP (the inner `.zip` inside the release archive)
5. Restart Ghidra when prompted

### Step 2 — Enable the Plugin in Code Browser

1. Open a project → launch **Code Browser**
2. **File → Configure → "Developer" section → tick `GhidraMCPPlugin`**
3. The Ghidra HTTP server starts on `127.0.0.1:8080` automatically

Verify it's running:
```bash
curl http://127.0.0.1:8080/functions | python3 -m json.tool | head -30
```

### Step 3 — Install the Python MCP Bridge

```bash
cd ~/tools/
git clone https://github.com/LaurieWired/GhidraMCP
cd GhidraMCP

# Install dependencies
pip3 install mcp httpx --break-system-packages
# or with uv:
uv pip install mcp httpx
```

### Step 4 — Connect an MCP Client

#### Option A: Claude Desktop (cloud)
Edit `~/.config/Claude/claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "ghidra": {
      "command": "python3",
      "args": [
        "/home/YOUR_USER/tools/GhidraMCP/bridge_mcp_ghidra.py",
        "--ghidra-server",
        "http://127.0.0.1:8080/"
      ]
    }
  }
}
```
Restart Claude Desktop. You should see **Ghidra** listed under MCP servers.

#### Option B: Ollama (local LLM — recommended for sensitive binaries)
Since you're running Ollama on the 3090, pair it with **Open WebUI** which has MCP support:

```bash
# Start the bridge as an SSE server
python3 bridge_mcp_ghidra.py \
  --transport sse \
  --mcp-host 127.0.0.1 \
  --mcp-port 8081 \
  --ghidra-server http://127.0.0.1:8080/
```

In Open WebUI: **Settings → Tools → Add MCP Server** → `http://127.0.0.1:8081/sse`

Best local models for RE tasks (tool-calling ability matters most):
- `qwen2.5-coder:32b` — excellent for code reasoning
- `llama3.1:70b` — strong general reasoning
- `deepseek-coder-v2` — good at decompiled C patterns

#### Option C: Cline (VS Code extension)
In Cline settings → MCP Servers → Remote → add `http://127.0.0.1:8081` (with SSE bridge running).

---

## First Analysis Walkthrough

### Import a Binary

1. **File → New Project** in Ghidra
2. **File → Import File** → select your target (ELF, PE, Mach-O, shellcode — all supported)
3. When prompted to analyse, click **Yes** and accept defaults (or tune: enable aggressive instruction finder, decompiler parameter ID)

### Prompt Patterns That Work Well

Once connected, use these patterns with your LLM:

```
"List all functions in the binary and identify any that look like 
network or socket operations."

"Rename all functions that appear to be crypto-related based on 
their constants and operations."

"Find the main entry point and walk me through what it does at 
a high level."

"Look at function at address 0x00401234 — what is it doing 
and what should I name it?"

"Identify any functions that call strcmp or memcmp and explain 
what they're comparing."

"Find all string references containing 'password', 'key', or 'token'."

"Add inline comments to FUN_00401234 explaining each block."
```

### What the LLM Can Do (LaurieWired plugin)

| Operation | Available |
|---|---|
| List/get functions | ✅ |
| Get decompiled pseudocode | ✅ |
| Rename functions & variables | ✅ |
| Add comments | ✅ |
| List imports/exports | ✅ |
| Get strings | ✅ |
| Cross-reference queries | ✅ |
| Create data structures | ✅ (bethington version) |
| P-code / emulation | ✅ (bethington version) |

---

## Upgrading: bethington/ghidra-mcp

Once comfortable, switch to the 243-tool version for real engagements:

```bash
git clone https://github.com/bethington/ghidra-mcp
cd ghidra-mcp
# Follow its README — plugin install is the same process
# Adds: structure creation, full write access, live debugger bridge,
#        P-code emulation, batch operations
```

Security note — the server is localhost-only by default. If you ever need remote access:
```bash
export GHIDRA_MCP_BIND_HOST=0.0.0.0
export GHIDRA_MCP_TOKEN=your_secret_token_here
# Every request must then carry: Authorization: Bearer <token>
```

---

## Multi-Binary Analysis: pyghidra-mcp

For tracing execution across shared libraries:

```bash
pip3 install pyghidra jpype1 --break-system-packages
git clone https://github.com/clearbluejar/pyghidra-mcp
cd pyghidra-mcp

# Point at a Ghidra project directory containing multiple binaries
python3 server.py --project /path/to/ghidra/project.gpr
```

Your LLM can now trace function calls from `main` → `libfoo.so` → `libbar.so` in a single conversation without context switching.

---

## Practical RE Workflow

```
1. STATIC TRIAGE
   └─ strings, file, checksec, readelf/objdump
   └─ Import into Ghidra, run auto-analysis

2. LLM INITIAL PASS (via MCP)
   └─ "What does this binary do at a high level?"
   └─ "Identify and rename crypto, network, and persistence functions"
   └─ "Find all functions with no callers (potential entry points)"

3. TARGETED DEEP DIVE
   └─ Focus on interesting functions the LLM flagged
   └─ "Explain FUN_xxx in detail — what are the arguments doing?"
   └─ "Add comments to this function"

4. DYNAMIC VALIDATION
   └─ Confirm LLM's theory with GDB/pwndbg or Frida
   └─ Check if runtime behaviour matches static analysis

5. DOCUMENT
   └─ LLM can generate a full analysis report from its session context
```

---

## Tips & Gotchas

- **Analysis quality gates everything.** Run Ghidra's full auto-analysis before querying the LLM — it does much better with decompiled pseudocode than raw bytes.
- **Stripped binaries** are harder. Ask the LLM to infer names from behaviour patterns and calling conventions, not symbols.
- **Sensitive samples** (malware, client binaries) → use Ollama locally. Don't send proprietary code to cloud APIs.
- **Context window limits** apply — for large binaries, query function by function rather than "explain everything."
- **The LLM hallucinates** on RE tasks. Always verify renamed functions and structural claims against the disassembly. Treat it as a very fast first-pass analyst, not ground truth.
- On Kali, Ghidra may need `_JAVA_OPTIONS="-Dawt.useSystemAAFontSettings=on"` if font rendering is broken.

---

## Resources

| Resource | URL |
|---|---|
| LaurieWired GhidraMCP | `github.com/LaurieWired/GhidraMCP` |
| bethington ghidra-mcp | `github.com/bethington/ghidra-mcp` |
| pyghidra-mcp | `github.com/clearbluejar/pyghidra-mcp` |
| Ghidra releases | `github.com/NationalSecurityAgency/ghidra/releases` |
| MCP spec | `modelcontextprotocol.io` |
| Clearbluejar RE blog | `clearbluejar.github.io` |

---

*Generated May 2026 — verify plugin version compatibility against your Ghidra version before installing.*
