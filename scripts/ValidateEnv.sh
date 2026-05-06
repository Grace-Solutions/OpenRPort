#!/usr/bin/env bash
# scripts/ValidateEnv.sh
# Validate required environment variables and formatting rules.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))"
ENV_FILE="${REPO_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

ERRORS=0
err()  { echo "  [ERROR] $*" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "  [WARN]  $*"; }
ok()   { echo "  [ OK ]  $*"; }

echo "==> Validating environment..."

# ── Stack identity ──────────────────────────────────────────────────────────
[ -n "${STACK_NAME:-}" ]         && ok "STACK_NAME=$STACK_NAME"               || err "STACK_NAME is required"
[ -n "${STACK_BINDMOUNTROOT:-}" ] && ok "STACK_BINDMOUNTROOT=$STACK_BINDMOUNTROOT" || err "STACK_BINDMOUNTROOT is required"

# ── Mode ────────────────────────────────────────────────────────────────────
MODE="${OPENRPORT_DEPLOYMENT_MODE:-subpath}"
case "$MODE" in
  dns|subpath|internal|local) ok "OPENRPORT_DEPLOYMENT_MODE=$MODE" ;;
  *) err "OPENRPORT_DEPLOYMENT_MODE must be one of: dns, subpath, internal, local. Got: $MODE" ;;
esac

# ── Base path format ────────────────────────────────────────────────────────
check_base_path() {
  local name="$1" val="$2"
  if [[ -z "$val" ]]; then err "$name is empty"; return; fi
  if [[ "${val:0:1}" != "/" ]]; then
    err "$name must start with /. Got: $val"
  elif [[ "$val" != "/" && "${val: -1}" == "/" ]]; then
    err "$name must not have a trailing slash. Got: $val"
  else
    ok "$name=$val"
  fi
}
check_base_path "OPENRPORT_SERVER_BASE_PATH"   "${OPENRPORT_SERVER_BASE_PATH:-/}"
check_base_path "OPENRPORT_PAIRING_BASE_PATH"  "${OPENRPORT_PAIRING_BASE_PATH:-/pairing}"
check_base_path "OPENRPORT_UI_BASE_PATH"       "${OPENRPORT_UI_BASE_PATH:-/ui}"
check_base_path "OPENRPORT_BINARIES_BASE_PATH" "${OPENRPORT_BINARIES_BASE_PATH:-/binaries}"

# ── Public URL format ───────────────────────────────────────────────────────
check_public_url() {
  local name="$1" val="$2"
  if [[ -z "$val" ]]; then warn "$name empty - will fall back to http://localhost:<port>"; return; fi
  if [[ "${val: -1}" == "/" ]]; then
    err "$name must not end with /. Got: $val"
  elif [[ "$val" != http://* && "$val" != https://* ]]; then
    err "$name must start with http:// or https://. Got: $val"
  else
    ok "$name=$val"
  fi
}
check_public_url "OPENRPORT_SERVER_PUBLIC_URL"   "${OPENRPORT_SERVER_PUBLIC_URL:-}"
check_public_url "OPENRPORT_PAIRING_PUBLIC_URL"  "${OPENRPORT_PAIRING_PUBLIC_URL:-}"
check_public_url "OPENRPORT_UI_PUBLIC_URL"       "${OPENRPORT_UI_PUBLIC_URL:-}"
check_public_url "OPENRPORT_BINARIES_PUBLIC_URL" "${OPENRPORT_BINARIES_PUBLIC_URL:-}"

# ── Network bind addresses ──────────────────────────────────────────────────
check_bind_addr() {
  local name="$1" val="$2"
  [ -z "$val" ] && return
  case "$val" in
    0.0.0.0|127.0.0.1|::|::1) ok "$name=$val"; return ;;
  esac
  if [[ "$val" =~ ^[0-9a-fA-F.:]+$ ]]; then ok "$name=$val"
  else err "$name must be a valid IP address. Got: $val"; fi
}
check_bind_addr "OPENRPORT_BIND_ADDRESS"               "${OPENRPORT_BIND_ADDRESS:-0.0.0.0}"
check_bind_addr "OPENRPORT_SERVER_API_BIND_ADDRESS"    "${OPENRPORT_SERVER_API_BIND_ADDRESS:-}"
check_bind_addr "OPENRPORT_SERVER_CLIENT_BIND_ADDRESS" "${OPENRPORT_SERVER_CLIENT_BIND_ADDRESS:-}"
check_bind_addr "OPENRPORT_PAIRING_BIND_ADDRESS"       "${OPENRPORT_PAIRING_BIND_ADDRESS:-}"
check_bind_addr "OPENRPORT_UI_BIND_ADDRESS"            "${OPENRPORT_UI_BIND_ADDRESS:-}"

# ── Tunnel port pool ────────────────────────────────────────────────────────
check_port_list() {
  local name="$1" val="$2"
  [ -z "$val" ] && { warn "$name empty - using rportd default"; return; }
  # accept comma-separated tokens that are either a single port or a range
  local IFS=,
  for tok in $val; do
    tok="${tok#"${tok%%[![:space:]]*}"}"; tok="${tok%"${tok##*[![:space:]]}"}"
    if [[ ! "$tok" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
      err "$name has invalid token '$tok' (expected port or range like 38200-38400)"
      return
    fi
  done
  ok "$name=$val"
}
check_port_list "OPENRPORT_TUNNEL_USED_PORTS"     "${OPENRPORT_TUNNEL_USED_PORTS:-}"
check_port_list "OPENRPORT_TUNNEL_EXCLUDED_PORTS" "${OPENRPORT_TUNNEL_EXCLUDED_PORTS:-}"

# ── Per-service ports ───────────────────────────────────────────────────────
check_port() {
  local name="$1" val="$2"
  if [[ ! "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 1 ] || [ "$val" -gt 65535 ]; then
    err "$name must be an integer 1-65535. Got: $val"
  else
    ok "$name=$val"
  fi
}
check_port "SERVER_API_INTERNAL_PORT"    "${SERVER_API_INTERNAL_PORT:-38100}"
check_port "SERVER_API_PUBLISH_PORT"     "${SERVER_API_PUBLISH_PORT:-38100}"
check_port "SERVER_CLIENT_INTERNAL_PORT" "${SERVER_CLIENT_INTERNAL_PORT:-38101}"
check_port "SERVER_CLIENT_PUBLISH_PORT"  "${SERVER_CLIENT_PUBLISH_PORT:-38101}"
check_port "PAIRING_INTERNAL_PORT"       "${PAIRING_INTERNAL_PORT:-38102}"
check_port "PAIRING_PUBLISH_PORT"        "${PAIRING_PUBLISH_PORT:-38102}"
check_port "UI_INTERNAL_PORT"            "${UI_INTERNAL_PORT:-38103}"
check_port "UI_PUBLISH_PORT"             "${UI_PUBLISH_PORT:-38103}"

# ── Subpath: hosts must match ───────────────────────────────────────────────
if [[ "$MODE" == "subpath" ]]; then
  S="${OPENRPORT_SERVER_PUBLIC_URL:-}"
  P="${OPENRPORT_PAIRING_PUBLIC_URL:-}"
  U="${OPENRPORT_UI_PUBLIC_URL:-}"
  if [[ -n "$S" && -n "$P" ]]; then
    sh=$(echo "$S" | awk -F/ '{print $3}')
    ph=$(echo "$P" | awk -F/ '{print $3}')
    [[ "$sh" == "$ph" ]] || err "Subpath: server/pairing hosts differ ($sh vs $ph)"
  fi
  if [[ -n "$S" && -n "$U" ]]; then
    sh=$(echo "$S" | awk -F/ '{print $3}')
    uh=$(echo "$U" | awk -F/ '{print $3}')
    [[ "$sh" == "$uh" ]] || err "Subpath: server/ui hosts differ ($sh vs $uh)"
  fi
fi

# ── DNS mode requires all public URLs ───────────────────────────────────────
if [[ "$MODE" == "dns" ]]; then
  [[ -z "${OPENRPORT_SERVER_PUBLIC_URL:-}"   ]] && err "DNS mode requires OPENRPORT_SERVER_PUBLIC_URL"
  [[ -z "${OPENRPORT_PAIRING_PUBLIC_URL:-}"  ]] && err "DNS mode requires OPENRPORT_PAIRING_PUBLIC_URL"
  [[ -z "${OPENRPORT_UI_PUBLIC_URL:-}"       ]] && err "DNS mode requires OPENRPORT_UI_PUBLIC_URL"
  [[ -z "${OPENRPORT_BINARIES_PUBLIC_URL:-}" ]] && err "DNS mode requires OPENRPORT_BINARIES_PUBLIC_URL"
fi

# ── Secrets sanity ──────────────────────────────────────────────────────────
[ -n "${RPORTD_API_PASSWORD:-}" ]   || err "RPORTD_API_PASSWORD must be set"
[ -n "${RPORTD_KEY_SEED:-}" ]       || err "RPORTD_KEY_SEED must be set (openssl rand -hex 18)"
[ -n "${RPORTD_JWT_SECRET:-}" ]     || err "RPORTD_JWT_SECRET must be set (openssl rand -base64 50)"
[ -n "${RPORTD_CLIENT_AUTH:-}" ]    || err "RPORTD_CLIENT_AUTH must be set (id:password)"

case "${RPORTD_API_PASSWORD:-}" in
  changeme|password|admin) err "RPORTD_API_PASSWORD looks like a placeholder - regenerate" ;;
esac

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "==> Validation FAILED with $ERRORS error(s). Fix .env and retry." >&2
  exit 1
fi
echo "==> Validation passed."
