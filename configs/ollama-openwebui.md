# Ollama via Open WebUI

Open WebUI's "Tools" feature speaks **OpenAPI**, not raw MCP/SSE. The bridge
alone won't work — Open WebUI hits `/sse/openapi.json` and gets a 404. Use
`mcpo` (MCP-to-OpenAPI proxy, by the Open WebUI team) in front of the bridge.

```
Ghidra :9090  ←  bridge (stdio)  ←  mcpo :8000 (OpenAPI)  ←  Open WebUI
```

`mcpo` is pip-installed into the venv by `install.sh`.

## 1. Run mcpo + the bridge

From the repo root:

```bash
./venv/bin/mcpo --port 8000 -- \
    ./venv/bin/python ./GhidraMCP/bridge_mcp_ghidra.py \
    --ghidra-server http://127.0.0.1:9090/
```

Sanity check:

```bash
curl -s http://127.0.0.1:8000/openapi.json | head -20
# Should return JSON listing the tools
```

## 2. Register it in Open WebUI

**Settings → Tools → "+"**

| Field | Value                       |
| ----- | --------------------------- |
| Name  | `ghidra`                    |
| URL   | `http://127.0.0.1:8000`     |

Open WebUI auto-discovers the schema at `/openapi.json`.

## 3. The two settings that decide whether tool calling actually works

This trips everyone up the first time.

### a) Function Calling: set to `Native`

**Settings → Models → \<your-model\> → Advanced Params → Function Calling**

Change from `Default` to **`Native`**. Without this, Open WebUI injects the
tool descriptions into the system prompt as plain text. The model "responds"
by writing ```bash` code blocks containing tool names — it never actually
calls anything. `Native` mode uses Ollama's structured function-calling API
and the tools become real callable functions. **Apply this to every model
you'll use with Ghidra-MCP.**

### b) Enable the tool per-chat

In the chat input area there's a tool icon (a "+" or wrench depending on
your OWUI version). Click it and **toggle `ghidra` ON for the chat**.
Tools registered in Settings are *available*; they're off by default in
each new conversation.

When both are correct, you'll see a "Using tools" indicator above each
response and tool-call cards stream in (e.g.
"🔧 ghidra.list_functions → 142 results").

## 4. Context size — bump it

Default `num_ctx` on Ollama is often 2048–4096 tokens. A single
`decompile_function` response can be 200–1000 tokens. You'll hit context
limits after 4-5 tool calls. In **Settings → Models → \<model\> → Advanced
Params → num_ctx**, set to at least `16384`. `32768` if you have the VRAM.

## 3. Pick a model with strong tool-calling

For 24 GB VRAM (single RTX 3090/4090):

- `qwen2.5-coder:32b` — best all-rounder for RE tasks
- `deepseek-coder-v2` — strong on decompiled C
- `llama3.1:70b` (heavily quantized) — broader reasoning, slower

For smaller cards, `qwen2.5-coder:14b` or `llama3.1:8b` work but tool-call
reliability drops — expect to re-prompt more often.

## Persisting across reboots

If you want mcpo + the bridge to come up automatically, drop a user-scoped
systemd unit at `~/.config/systemd/user/ghidra-mcp.service`:

```ini
[Unit]
Description=mcpo OpenAPI proxy fronting GhidraMCP bridge
After=network.target

[Service]
Type=simple
ExecStart=%h/Documents/ghidra-mcp-setup/venv/bin/mcpo --port 8000 -- \
    %h/Documents/ghidra-mcp-setup/venv/bin/python \
    %h/Documents/ghidra-mcp-setup/GhidraMCP/bridge_mcp_ghidra.py \
    --ghidra-server http://127.0.0.1:9090/
Restart=on-failure

[Install]
WantedBy=default.target
```

Then:

```bash
systemctl --user daemon-reload
systemctl --user enable --now ghidra-mcp.service
```

Note: this only serves the bridge — Ghidra itself still needs to be running
with the plugin enabled before the bridge has anything to talk to.
