# Tutorial — Ghidra MCP from zero to your first LLM-driven reverse-engineering session

This walkthrough takes about 10 minutes if you already have Ghidra installed,
20 if you don't. We'll get one of {Claude Desktop, Claude Code, gemini-cli,
Ollama} talking to Ghidra via MCP.

```
┌──────────────────┐    HTTP    ┌──────────────────────┐    stdio/SSE    ┌────────────┐
│  Ghidra +        │ ◀────────▶ │  bridge_mcp_ghidra   │ ◀────────────▶ │ MCP client │
│  GhidraMCPPlugin │  :8080     │  (Python, in venv)   │                 │ (LLM)      │
└──────────────────┘            └──────────────────────┘                 └────────────┘
```

The Ghidra plugin runs an HTTP server inside Ghidra. The Python bridge translates
between that HTTP server and the Model Context Protocol your LLM client speaks.
`./run-bridge.sh` launches the bridge using the venv's Python interpreter.

---

## Step 0 — Install prerequisites

```bash
# Debian / Ubuntu / Kali
sudo apt install git python3 python3-venv curl openjdk-21-jdk

# Arch / CachyOS
sudo pacman -S git python curl jdk21-openjdk

# Fedora
sudo dnf install git python3 curl java-21-openjdk-devel
```

Then grab Ghidra if you don't have it:

```bash
mkdir -p ~/tools && cd ~/tools
curl -LO https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.3.2_build/ghidra_11.3.2_PUBLIC_20250415.zip
unzip ghidra_11.3.2_PUBLIC_20250415.zip
# Run it:
./ghidra_11.3.2_PUBLIC/ghidraRun
```

*(Versions change — check the [releases page](https://github.com/NationalSecurityAgency/ghidra/releases) for the current one.)*

---

## Step 1 — Run the installer

```bash
git clone https://github.com/YOUR_USER/ghidra-mcp-setup.git
cd ghidra-mcp-setup
./install.sh
```

When it finishes you should have:

```
GhidraMCP/                  cloned bridge source
venv/                       Python venv with the bridge's deps (mcp, requests)
extensions/GhidraMCP-*.zip  the Ghidra plugin
configs/generated/*         ready-to-paste client configs
```

> **fish users:** the installer is bash (`#!/usr/bin/env bash`) so it works fine
> regardless of your interactive shell. The final hint it prints will show
> `activate.fish` if your `$SHELL` is fish.

---

## Step 2 — Install the plugin inside Ghidra

1. Launch Ghidra: `~/tools/ghidra_11.3.2_PUBLIC/ghidraRun`
2. **File → Install Extensions → "+"**
3. Browse to `ghidra-mcp-setup/extensions/GhidraMCP-*.zip` and select it
4. Click **OK**, then restart Ghidra when prompted

Open or create a project, then double-click a binary to launch **Code Browser**.
In Code Browser:

5. **File → Configure**
6. Click **"Configure"** under the *Developer* row
7. Tick **`GhidraMCPPlugin`** → **OK**
8. **File → Configure → Save**

The plugin now exposes an HTTP server on `127.0.0.1:8080`. Verify from another terminal:

```bash
curl -s http://127.0.0.1:8080/methods | head -20
# Should list available endpoints; if you get "Connection refused",
# the plugin isn't enabled or Ghidra isn't running.
```

---

## Step 3 — Wire up an MCP client

Pick one of the four paths below. You only need one.

### A) Claude Desktop

Config lives at `~/.config/Claude/claude_desktop_config.json` on Linux
(`~/Library/Application Support/Claude/claude_desktop_config.json` on macOS).

If the file doesn't exist yet, copy ours wholesale:

```bash
mkdir -p ~/.config/Claude
cp configs/generated/claude-desktop.json ~/.config/Claude/claude_desktop_config.json
```

If you already have a config, merge the `"ghidra"` entry from
`configs/generated/claude-desktop.json` into your existing `mcpServers` block.

Restart Claude Desktop. Click the **🔌 / tools** icon — you should see **ghidra**
listed with a green dot.

### B) Claude Code (CLI)

Either drop a project-local `.mcp.json`:

```bash
cp configs/generated/claude-code.mcp.json .mcp.json
```

…or register it globally:

```bash
# Inspect the generated file first, then:
claude mcp add ghidra "$PWD/venv/bin/python" \
  "$PWD/GhidraMCP/bridge_mcp_ghidra.py" \
  --ghidra-server "http://127.0.0.1:8080/"
```

Start a new Claude Code session. Run `/mcp` inside it to confirm the **ghidra**
server is connected.

### C) gemini-cli

gemini-cli reads MCP server definitions from `~/.gemini/settings.json` (verify
against the [current docs](https://github.com/google-gemini/gemini-cli) — the
location has changed across versions).

Copy or merge:

```bash
mkdir -p ~/.gemini
# Fresh install:
cp configs/generated/gemini-cli.json ~/.gemini/settings.json
# Or merge the mcpServers block into your existing settings.json.
```

Run `gemini` and type `/mcp` to list connected servers; **ghidra** should show
up.

### D) Ollama (via Open WebUI)

Ollama itself doesn't speak MCP — Open WebUI is the easiest bridge. Assuming
you already have [Open WebUI](https://github.com/open-webui/open-webui) running
against your local Ollama:

1. Start the GhidraMCP bridge in **SSE** mode:

   ```bash
   ./run-bridge.sh --transport sse \
                   --mcp-host 127.0.0.1 \
                   --mcp-port 8081 \
                   --ghidra-server http://127.0.0.1:8080/
   ```

   Leave it running in a separate terminal (or under tmux / systemd).

2. In Open WebUI: **Settings → Tools → "+" → Add MCP Server**
   - URL: `http://127.0.0.1:8081/sse`
   - Name: `ghidra`

3. Pick a model that's good at tool-calling. For 24 GB VRAM:
   - `qwen2.5-coder:32b` — best all-rounder for RE tasks
   - `deepseek-coder-v2` — strong on decompiled C
   - `llama3.1:70b` (quantized) — broader reasoning

`./run-bridge.sh` runs in your foreground shell — to keep it alive across
reboots, drop it into a systemd `--user` unit or a tmux window.

---

## Step 4 — Try it out

Load any binary into Ghidra (let auto-analysis finish — this matters; the LLM
sees decompiled pseudocode, not raw bytes). Then in your MCP client:

```
List all functions in this binary and flag any that look like crypto,
networking, or process-injection primitives.
```

```
Show me the decompilation of FUN_00401234 and suggest a better name
based on what it actually does.
```

```
Find every function that references the string "password" and tell me
which one looks like the credential check.
```

The LLM will issue MCP tool calls under the hood (`list_functions`,
`get_decompiled_function`, `rename_function`, …) and stream results into the chat.

---

## Troubleshooting

**`Connection refused` from the bridge.**
Ghidra plugin isn't enabled, or Code Browser isn't open. The HTTP server only
runs while a project is loaded in Code Browser. Re-check Step 2.

**Plugin doesn't appear under "Developer" in Configure.**
The plugin ZIP wasn't installed (or the wrong inner ZIP was picked). The
release archive sometimes contains a nested ZIP — install the inner one if
needed. Restart Ghidra after installing.

**Client says `ghidra` failed to start.**
Try running the exact command from the config manually:

```bash
./run-bridge.sh
```

If that prints `ModuleNotFoundError: mcp` or `ModuleNotFoundError: requests`,
the venv didn't get the deps — re-run `./install.sh`. If it prints a Python interpreter error, the venv was
created with a different Python; delete `./venv` and re-run the installer.

**Java version errors when launching Ghidra.**
Run `java -version`. Ghidra 11.3+ needs JDK 21+. If you have multiple JDKs,
set `JAVA_HOME` before launching Ghidra:

```bash
# bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
# fish
set -x JAVA_HOME /usr/lib/jvm/java-21-openjdk
```

**Open WebUI doesn't see the tools.**
Confirm `curl http://127.0.0.1:8081/sse` returns an `event-stream` response.
If not, the bridge isn't running in SSE mode — check the flags in Step 3D.

**Activating the venv manually.**

```bash
# bash / zsh
source venv/bin/activate

# fish
source venv/bin/activate.fish
```

You almost never need to — `./run-bridge.sh` and the generated configs both
call `venv/bin/python` directly.

---

## Going further

When the LaurieWired bridge starts to feel limiting (it focuses on the read +
rename + comment loop), look at:

- **`bethington/ghidra-mcp`** — 240+ tools, including structure creation,
  P-code emulation, and a live debugger bridge. Same plugin install flow;
  the bridge is a drop-in replacement.
- **`clearbluejar/pyghidra-mcp`** — headless, project-wide. Best for tracing
  calls across multiple binaries in a single session (e.g. `main` →
  `libfoo.so` → `libbar.so`).

The background guide at [`ghidra-mcp-guide.md`](./ghidra-mcp-guide.md) covers
the tradeoffs and the broader RE workflow (static triage → LLM first-pass →
dynamic validation → report).

**Operational note:** treat the LLM as a fast first-pass analyst, not a
source of truth. It hallucinates on RE tasks — every claim of "this is the
auth check" or "this is AES" should be verified against the disassembly or a
debugger before you act on it. For sensitive samples (malware, client code
under NDA), use the **Ollama** path so nothing leaves your machine.
