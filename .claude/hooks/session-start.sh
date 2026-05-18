#!/bin/bash
set -euo pipefail

# Only run in remote Claude Code on the web sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install all dev dependencies using the locked uv.lock for reproducibility.
# Equivalent to: pip install notebooklm-py and pip install "notebooklm-py[browser]"
# plus dev + markdown extras needed for linting and testing.
uv sync --frozen --extra browser --extra dev --extra markdown
