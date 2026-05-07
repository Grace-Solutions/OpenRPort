#!/usr/bin/env sh
# Container/Server/entrypoint.sh
# Renders rportd.conf at startup and launches rportd. A bind-mounted
# /etc/rport/rportd.conf wins; otherwise the full config (including the
# optional [plus-plugin]/[plus-oauth] OIDC blocks) is rendered from
# environment variables so the image is self-contained and deployable
# without the OpenRPort repo.
set -eu

CONFIG_SRC="/etc/rport/rportd.conf"
CONFIG_LIVE="/tmp/rportd.runtime.conf"

PAIRING_URL_OVERRIDE="${OPENRPORT_PAIRING_PUBLIC_URL:-}"
SERVER_URL_OVERRIDE="${OPENRPORT_SERVER_PUBLIC_URL:-}"

# Convert comma-separated lists into TOML array body: 'a', 'b', 'c'
toml_array() {
  _input="$1"
  _out=""
  _IFS_OLD="$IFS"
  IFS=,
  for _item in $_input; do
    _item="${_item# }"; _item="${_item% }"
    [ -z "$_item" ] && continue
    if [ -n "$_out" ]; then _out="$_out, "; fi
    _out="$_out'$_item'"
  done
  IFS="$_IFS_OLD"
  printf '%s' "$_out"
}

if [ -f "$CONFIG_SRC" ]; then
  cp "$CONFIG_SRC" "$CONFIG_LIVE"
  if [ -n "$PAIRING_URL_OVERRIDE" ]; then
    sed -i "s|pairing_url = \".*\"|pairing_url = \"${PAIRING_URL_OVERRIDE}\"|g" "$CONFIG_LIVE"
  fi
  if [ -n "$SERVER_URL_OVERRIDE" ]; then
    sed -i "s|^url *=.*|url         = \"${SERVER_URL_OVERRIDE}\"|g" "$CONFIG_LIVE"
  fi
  echo "[entrypoint] using ${CONFIG_SRC} (overrides: pairing=${PAIRING_URL_OVERRIDE:-none}, server=${SERVER_URL_OVERRIDE:-none})"
else
  # ── Render full rportd.conf from environment ────────────────────────────
  API_PORT="${SERVER_API_INTERNAL_PORT:-8080}"
  CLIENT_PORT="${SERVER_CLIENT_INTERNAL_PORT:-8081}"

  BIND_DEFAULT="${OPENRPORT_BIND_ADDRESS:-0.0.0.0}"
  API_BIND="${OPENRPORT_SERVER_API_BIND_ADDRESS:-$BIND_DEFAULT}"
  CLIENT_BIND="${OPENRPORT_SERVER_CLIENT_BIND_ADDRESS:-$BIND_DEFAULT}"

  FALLBACK_PAIRING_URL="${PAIRING_URL_OVERRIDE:-http://Pairing:${PAIRING_INTERNAL_PORT:-38102}/pairing}"
  FALLBACK_SERVER_URL="${SERVER_URL_OVERRIDE:-http://localhost:${CLIENT_PORT}}"

  TUNNEL_USED_PORTS="${OPENRPORT_TUNNEL_USED_PORTS:-38200-38400}"
  TUNNEL_EXCLUDED_PORTS="${OPENRPORT_TUNNEL_EXCLUDED_PORTS:-1-1024}"
  TUNNEL_USED_PORTS_TOML=$(toml_array "$TUNNEL_USED_PORTS")
  TUNNEL_EXCLUDED_PORTS_TOML=$(toml_array "$TUNNEL_EXCLUDED_PORTS")
  TUNNEL_HOST="${OPENRPORT_TUNNEL_HOST:-}"

  cat > "$CONFIG_LIVE" <<CONF
# Rendered by Container/Server/entrypoint.sh from environment variables.

[server]
address             = "${CLIENT_BIND}:${CLIENT_PORT}"
url                 = "${FALLBACK_SERVER_URL}"
data_dir            = "/var/lib/rport"
key_seed            = "${RPORTD_KEY_SEED:?RPORTD_KEY_SEED required}"
auth                = "${RPORTD_CLIENT_AUTH:?RPORTD_CLIENT_AUTH required}"
pairing_url         = "${FALLBACK_PAIRING_URL}"
used_ports          = [${TUNNEL_USED_PORTS_TOML}]
excluded_ports      = [${TUNNEL_EXCLUDED_PORTS_TOML}]
auth_multiuse_creds = true
CONF
  if [ -n "$TUNNEL_HOST" ]; then
    echo "tunnel_host         = \"${TUNNEL_HOST}\"" >> "$CONFIG_LIVE"
  fi
  cat >> "$CONFIG_LIVE" <<CONF

[api]
address    = "${API_BIND}:${API_PORT}"
auth       = "${RPORTD_API_USER:-admin}:${RPORTD_API_PASSWORD:?RPORTD_API_PASSWORD required}"
jwt_secret = "${RPORTD_JWT_SECRET:?RPORTD_JWT_SECRET required}"
cors       = ["${RPORTD_CORS_ORIGINS:-*}"]

[logging]
log_file  = "/var/log/rport/rportd.log"
log_level = "info"
CONF

  # ── Optional [plus-plugin]/[plus-oauth] (OIDC) ────────────────────────
  # Activated only when RPORT_OIDC_ISSUER_URL is set. Endpoint resolution:
  #   1. Explicit RPORT_OIDC_AUTHORIZE_URL/_TOKEN_URL/_JWKS_URL win.
  #   2. Otherwise OIDC discovery via curl+jq against the issuer's
  #      /.well-known/openid-configuration. Failure aborts startup.
  if [ -n "${RPORT_OIDC_ISSUER_URL:-}" ]; then
    PLUGIN_PATH="${RPORT_PLUS_PLUGIN_PATH:-/usr/local/lib/rport/rport-plus.so}"
    UI_URL_DEFAULT="${OPENRPORT_UI_PUBLIC_URL:-http://localhost:${UI_INTERNAL_PORT:-38103}}"
    OIDC_REDIRECT="${RPORT_OIDC_REDIRECT_URI:-${UI_URL_DEFAULT}/auth/callback}"
    case "${RPORT_OIDC_ALLOW_LOCAL_LOGIN:-false}" in
      1|true|TRUE|True|yes|YES) OIDC_ALLOW_LOCAL="true" ;;
      *) OIDC_ALLOW_LOCAL="false" ;;
    esac

    _ISSUER_RAW="${RPORT_OIDC_ISSUER_URL%/}"
    case "$_ISSUER_RAW" in
      */.well-known/openid-configuration)
        _DISCOVERY_URL="$_ISSUER_RAW"
        ;;
      *)
        _DISCOVERY_URL="${_ISSUER_RAW}/.well-known/openid-configuration"
        ;;
    esac

    OIDC_AUTHZ="${RPORT_OIDC_AUTHORIZE_URL:-}"
    OIDC_TOKEN="${RPORT_OIDC_TOKEN_URL:-}"
    OIDC_JWKS="${RPORT_OIDC_JWKS_URL:-}"

    if [ -z "$OIDC_AUTHZ" ] || [ -z "$OIDC_TOKEN" ] || [ -z "$OIDC_JWKS" ]; then
      if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        echo "[entrypoint] ERROR: curl+jq required for OIDC discovery" >&2; exit 1
      fi
      echo "[entrypoint] discovering OIDC endpoints from ${_DISCOVERY_URL}"
      _DISCO_DOC=$(curl -fsS --max-time 10 "$_DISCOVERY_URL" 2>/dev/null) || {
        echo "[entrypoint] ERROR: OIDC discovery failed (curl ${_DISCOVERY_URL})" >&2; exit 1; }
      OIDC_AUTHZ="${OIDC_AUTHZ:-$(printf '%s' "$_DISCO_DOC" | jq -er '.authorization_endpoint')}" || {
        echo "[entrypoint] ERROR: discovery doc missing authorization_endpoint" >&2; exit 1; }
      OIDC_TOKEN="${OIDC_TOKEN:-$(printf '%s' "$_DISCO_DOC" | jq -er '.token_endpoint')}" || {
        echo "[entrypoint] ERROR: discovery doc missing token_endpoint" >&2; exit 1; }
      OIDC_JWKS="${OIDC_JWKS:-$(printf '%s' "$_DISCO_DOC" | jq -er '.jwks_uri')}" || {
        echo "[entrypoint] ERROR: discovery doc missing jwks_uri" >&2; exit 1; }
    fi

    cat >> "$CONFIG_LIVE" <<CONF

[plus-plugin]
plugin_path = "${PLUGIN_PATH}"

[plus-oauth]
provider             = "${RPORT_OIDC_PROVIDER:-oidc}"
authorize_url        = "${OIDC_AUTHZ}"
token_url            = "${OIDC_TOKEN}"
redirect_uri         = "${OIDC_REDIRECT}"
client_id            = "${RPORT_OIDC_CLIENT_ID:?RPORT_OIDC_CLIENT_ID required when RPORT_OIDC_ISSUER_URL is set}"
client_secret        = "${RPORT_OIDC_CLIENT_SECRET:?RPORT_OIDC_CLIENT_SECRET required when RPORT_OIDC_ISSUER_URL is set}"
jwks_url             = "${OIDC_JWKS}"
username_claim       = "${RPORT_OIDC_USERNAME_CLAIM:-preferred_username}"
permitted_user_match = "${RPORT_OIDC_PERMITTED_USER_MATCH:-.*}"
allow_local_login    = ${OIDC_ALLOW_LOCAL}
CONF
    echo "[entrypoint] OIDC enabled (authorize=${OIDC_AUTHZ})"
  fi

  echo "[entrypoint] rendered ${CONFIG_LIVE} from environment"
fi

exec rportd -c "$CONFIG_LIVE" "$@"
