# OpenCode setup (legacy entry point)

**Canonical documentation:** [`docs/opencode-setup.md`](docs/opencode-setup.md)

Quick start:

```bash
npm install -g @opencode/cli
cd runpod-llm-fleet
./scripts/setup-opencode.sh
./scripts/validate-opencode.sh
```

That installs `~/.config/opencode/opencode.jsonc`, syncs `~/.config/envman/RUNPOD.key`,
and validates the RunPod connection.

See [`docs/opencode-setup.md`](docs/opencode-setup.md) for configuration reference,
usage, troubleshooting (including the `401 no token provided` fix), and debugging.
