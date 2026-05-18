# Security notes

This project is a thin installer + tutorial around third-party software. Most
of the security-relevant code is upstream of us. This document records what
the installer does to defend its small attack surface, and what's explicitly
out of scope.

## What `install.sh` does

1. Clones `LaurieWired/GhidraMCP` over HTTPS (TLS-verified by git).
2. Creates a Python venv with `python3 -m venv`.
3. `pip install`s from the upstream `GhidraMCP/requirements.txt` (over HTTPS,
   from default PyPI).
4. Fetches the latest plugin release ZIP from
   `https://github.com/LaurieWired/GhidraMCP/releases` (over HTTPS).
5. Writes config snippets under `configs/generated/`.

That's it. No `sudo`, no system-wide writes, no `eval`, no `curl | bash`.

## Hardening in the installer

- `set -euo pipefail` and quoted variable expansions throughout.
- The release URL parsed from the GitHub API is **validated** before download:
  it must start with `https://github.com/LaurieWired/GhidraMCP/releases/download/`
  and its filename must match `GhidraMCP-*.zip`. Anything else is refused.
- `curl --proto '=https' --tlsv1.2` for the release download.
- The plugin ZIP is downloaded to a `mktemp` file under `extensions/` and only
  `mv`d into place on success — no partial files left behind.
- After download, the installer prints the SHA256 of the ZIP and points you
  at the releases page so you can verify out-of-band.
- The upstream clone is **not** auto-updated on re-run. Pass `--update` to
  refresh; pin to a specific tag/sha via `GHIDRAMCP_REF=...`.
- Java version detection guards against non-numeric output before the numeric
  comparison.

## What's out of scope

These are real risks, but defending against them from a 200-line shell script
buys little.

- **Upstream compromise of `LaurieWired/GhidraMCP`.** If their `main` ships
  malicious code, we ship it too. Pin with `GHIDRAMCP_REF=<tag-or-sha>` and
  review the diff if you care.
- **Compromise of a PyPI package** (`mcp`, `requests`). We install whatever
  the upstream `requirements.txt` pins, over HTTPS, from default PyPI.
  Hash-pinning would defeat the "track upstream" property.
- **Compromise of GitHub's release infrastructure.** We verify the URL host
  and filename pattern, but the ZIP itself is trusted as served. If you need
  stronger guarantees, build the plugin from source — see `GhidraMCP/`.
- **A local attacker who can write to `./extensions/` before you run the
  installer.** The installer skips download if a `GhidraMCP-*.zip` is
  already present. If your filesystem is hostile, you have bigger problems.
- **The MCP bridge itself.** The bridge speaks to a Ghidra HTTP server on
  `127.0.0.1:8080`. Don't bind it to a public interface, and don't expose
  the SSE port (`8081`) beyond localhost unless you put auth in front of it.
  The `bethington/ghidra-mcp` variant adds bearer-token auth — use that if
  you need remote access.
- **What the LLM does with the tools.** Treat the model as a fast first-pass
  analyst, not ground truth. Renames and comments it makes are real edits to
  your Ghidra project.

## Reporting

Found a bug in this installer or tutorial? Open an issue or PR. For issues in
the upstream bridge or Ghidra plugin, report to those projects directly.
