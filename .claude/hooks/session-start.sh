#!/bin/bash
set -euo pipefail

# Only run in Claude Code remote (web) sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Run async so the session starts without waiting for the full install
echo '{"async": true, "asyncTimeout": 300000}'

cd "$CLAUDE_PROJECT_DIR"

# Install all dependencies including browser and dev extras
uv sync --frozen --extra browser --extra dev --extra markdown

# Install Playwright Chromium browser (~170 MB; no progress bar — be patient)
uv run playwright install chromium

# Expose the venv to the session so `python`, `pytest`, `ruff`, etc. resolve correctly
echo "export VIRTUAL_ENV=\"$CLAUDE_PROJECT_DIR/.venv\"" >> "$CLAUDE_ENV_FILE"
echo "export PATH=\"$CLAUDE_PROJECT_DIR/.venv/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
