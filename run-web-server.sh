#!/usr/bin/env bash
set -euo pipefail

PORT=8080
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "[1/4] Closing any process that is listening on port ${PORT}..."
if command -v lsof >/dev/null 2>&1; then
  EXISTING_PIDS="$(lsof -tiTCP:${PORT} -sTCP:LISTEN || true)"
  if [ -n "${EXISTING_PIDS}" ]; then
    kill ${EXISTING_PIDS}
  fi
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js was not found. UI image path check cannot run."
  exit 1
fi

echo "[2/4] Checking UI image paths..."
node "${PROJECT_ROOT}/tests/ui_bare_asset_paths_check.mjs"

if command -v python3 >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
else
  echo "Python was not found. Install Python or add it to PATH."
  exit 1
fi

echo "[3/4] Starting the server from:"
echo "${PROJECT_ROOT}"
echo "[4/4] Opening http://localhost:${PORT}/web/"

if command -v open >/dev/null 2>&1; then
  open "http://localhost:${PORT}/web/" >/dev/null 2>&1 || true
fi

cd "${PROJECT_ROOT}"
exec "${PYTHON}" -m http.server "${PORT}"
