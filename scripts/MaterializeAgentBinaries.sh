#!/usr/bin/env bash
# scripts/MaterializeAgentBinaries.sh
# Dispatches to BuildAgentBinaries.sh or FetchAgentBinaries.sh based on
# RPORT_AGENT_SOURCE (default: build). Sourcing .env first means the choice
# is settable both via shell env and via the .env file, with shell env
# taking precedence (export RPORT_AGENT_SOURCE=fetch make prepare).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))"
ENV_FILE="${REPO_ROOT}/.env"

# Capture any pre-set value before sourcing .env so command-line/env wins.
PRESET_SOURCE="${RPORT_AGENT_SOURCE:-}"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
[ -n "$PRESET_SOURCE" ] && RPORT_AGENT_SOURCE="$PRESET_SOURCE"
RPORT_AGENT_SOURCE="${RPORT_AGENT_SOURCE:-build}"

case "${RPORT_AGENT_SOURCE}" in
  build)
    exec bash "${REPO_ROOT}/scripts/BuildAgentBinaries.sh" "$@"
    ;;
  fetch)
    exec bash "${REPO_ROOT}/scripts/FetchAgentBinaries.sh" "$@"
    ;;
  *)
    echo "[ERROR] RPORT_AGENT_SOURCE must be 'build' or 'fetch' (got '${RPORT_AGENT_SOURCE}')" >&2
    exit 2
    ;;
esac
