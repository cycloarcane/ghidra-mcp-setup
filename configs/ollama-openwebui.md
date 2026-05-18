# Ollama via Open WebUI

Ollama doesn't speak MCP directly — Open WebUI is the bridge.

## 1. Run the GhidraMCP bridge in SSE mode

From the repo root:

```bash
./run-bridge.sh \
    --transport sse \
    --mcp-host 127.0.0.1 \
    --mcp-port 8081 \
    --ghidra-server http://127.0.0.1:8080/
```

Leave it running in a separate terminal, tmux pane, or `--user` systemd unit.

Sanity check:

```bash
curl -s -N http://127.0.0.1:8081/sse | head -5
# Should print SSE event headers like 'event: endpoint'
```

## 2. Register it in Open WebUI

**Settings → Tools → "+" → Add MCP Server**

| Field | Value                       |
| ----- | --------------------------- |
| Name  | `ghidra`                    |
| URL   | `http://127.0.0.1:8081/sse` |

## 3. Pick a model with strong tool-calling

For 24 GB VRAM (single RTX 3090/4090):

- `qwen2.5-coder:32b` — best all-rounder for RE tasks
- `deepseek-coder-v2` — strong on decompiled C
- `llama3.1:70b` (heavily quantized) — broader reasoning, slower

For smaller cards, `qwen2.5-coder:14b` or `llama3.1:8b` work but tool-call
reliability drops — expect to re-prompt more often.

## Persisting across reboots

If you want the SSE bridge to come up automatically, drop a user-scoped systemd
unit at `~/.config/systemd/user/ghidra-mcp.service`:

```ini
[Unit]
Description=GhidraMCP SSE bridge
After=network.target

[Service]
Type=simple
ExecStart=%h/Documents/ghidra-mcp-setup/run-bridge.sh \
    --transport sse \
    --mcp-host 127.0.0.1 \
    --mcp-port 8081 \
    --ghidra-server http://127.0.0.1:8080/
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
