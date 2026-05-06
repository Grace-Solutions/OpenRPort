#!/usr/bin/env bash
# scripts/ValidateEnv.sh
# Validate required environment variables and formatting rules.
# Sourced by GenerateConfig.sh and also callable standalone.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="${REPO_ROOT}/.env"

# Load .env if present and not already exported
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

ERRORS=0

err() { echo "  [ERROR] $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "  [WARN]  $*"; }
ok()  { echo "  [ OK ]  $*"; }

echo "==> Validating environment..."

# ── Mode ────────────────────────────────────────────────────────────────────
MODE="${OPENRPORT_DEPLOYMENT_MODE:-subpath}"
case "$MODE" in
  dns|subpath|internal|local) ok "OPENRPORT_DEPLOYMENT_MODE=$MODE" ;;
  *) err "OPENRPORT_DEPLOYMENT_MODE must be one of: dns, subpath, internal, local. Got: $MODE" ;;
esac

# ── Base path format ─────────────────────────────────────────────────────────
check_base_path() {
  local name="$1" val="$2"
  if [[ -z "$val" ]]; then
    err "$name is empty – must start with /"
    return
  fi
  if [[ "${val:0:1}" != "/" ]]; then
    err "$name must start with /. Got: $val"
  elif [[ "$val" != "/" && "${val: -1}" == "/" ]]; then
    err "$name must not have a trailing slash (unless root /). Got: $val"
  else
    ok "$name=$val"
  fi
}

check_base_path "OPENRPORT_SERVER_BASE_PATH"  "${OPENRPORT_SERVER_BASE_PATH:-/}"
check_base_path "OPENRPORT_PAIRING_BASE_PATH" "${OPENRPORT_PAIRING_BASE_PATH:-/pairing}"
check_base_path "OPENRPORT_UI_BASE_PATH"      "${OPENRPORT_UI_BASE_PATH:-/ui}"

# ── Public URL format ────────────────────────────────────────────────────────
check_public_url() {
  local name="$1" val="$2"
  if [[ -z "$val" ]]; then
    warn "$name is empty – will be auto-discovered from headers or defaults"
    return
  fi
  if [[ "${val: -1}" == "/" ]]; then
    err "$name must not have a trailing slash. Got: $val"
  elif [[ "$val" != http://* && "$val" != https://* ]]; then
    err "$name must start with http:// or https://. Got: $val"
  else
    ok "$name=$val"
  fi
}

check_public_url "OPENRPORT_SERVER_PUBLIC_URL"  "${OPENRPORT_SERVER_PUBLIC_URL:-}"
check_public_url "OPENRPORT_PAIRING_PUBLIC_URL" "${OPENRPORT_PAIRING_PUBLIC_URL:-}"
check_public_url "OPENRPORT_UI_PUBLIC_URL"      "${OPENRPORT_UI_PUBLIC_URL:-}"

# ── Subpath mode requires matching hosts ────────────────────────────────────
if [[ "$MODE" == "subpath" ]]; then
  SERVER_URL="${OPENRPORT_SERVER_PUBLIC_URL:-}"
  PAIRING_URL="${OPENRPORT_PAIRING_PUBLIC_URL:-}"
  UI_URL="${OPENRPORT_UI_PUBLIC_URL:-}"
  if [[ -n "$SERVER_URL" && -n "$PAIRING_URL" ]]; then
    S_HOST=$(echo "$SERVER_URL"  | awk -F/ '{print $3}')
    P_HOST=$(echo "$PAIRING_URL" | awk -F/ '{print $3}')
    if [[ "$S_HOST" != "$P_HOST" ]]; then
      err "Subpath mode: SERVER and PAIRING must share the same host ($S_HOST vs $P_HOST)"
    fi
  fi
fi

# ── DNS mode requires all public URLs ───────────────────────────────────────
if [[ "$MODE" == "dns" ]]; then
  [[ -z "${OPENRPORT_SERVER_PUBLIC_URL:-}"  ]] && err "DNS mode requires OPENRPORT_SERVER_PUBLIC_URL"
  [[ -z "${OPENRPORT_PAIRING_PUBLIC_URL:-}" ]] && err "DNS mode requires OPENRPORT_PAIRING_PUBLIC_URL"
  [[ -z "${OPENRPORT_UI_PUBLIC_URL:-}"      ]] && err "DNS mode requires OPENRPORT_UI_PUBLIC_URL"
fi

# ── Result ───────────────────────────────────────────────────────────────────
echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "==> Validation FAILED with $ERRORS error(s). Fix .env and retry." >&2
  exit 1
fi
echo "==> Validation passed."
