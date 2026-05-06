#!/usr/bin/env sh
# Container/Server/entrypoint.sh
# Renders the runtime rportd config from the bind-mounted /etc/rport tree
# and launches rportd. The rportd.conf is fully populated by
# scripts/GenerateConfig.sh so we just copy + apply optional env overrides.
set -eu

CONFIG_SRC="/etc/rport/rportd.conf"
CONFIG_LIVE="/tmp/rportd.runtime.conf"

PAIRING_URL_OVERRIDE="${OPENRPORT_PAIRING_PUBLIC_URL:-}"
SERVER_URL_OVERRIDE="${OPENRPORT_SERVER_PUBLIC_URL:-}"

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
  # Minimal fallback when no config is mounted - meant for emergency boot.
  API_PORT="${SERVER_API_INTERNAL_PORT:-8080}"
  CLIENT_PORT="${SERVER_CLIENT_INTERNAL_PORT:-8081}"
  FALLBACK_PAIRING_URL="${PAIRING_URL_OVERRIDE:-http://Pairing:${PAIRING_INTERNAL_PORT:-38102}/pairing}"
  FALLBACK_SERVER_URL="${SERVER_URL_OVERRIDE:-http://localhost:${CLIENT_PORT}}"
  cat > "$CONFIG_LIVE" <<CONF
[server]
address     = "0.0.0.0:${CLIENT_PORT}"
url         = "${FALLBACK_SERVER_URL}"
data_dir    = "/var/lib/rport"
key_seed    = "${RPORTD_KEY_SEED:?RPORTD_KEY_SEED required}"
pairing_url = "${FALLBACK_PAIRING_URL}"
auth        = "${RPORTD_CLIENT_AUTH:?RPORTD_CLIENT_AUTH required}"

[api]
address    = "0.0.0.0:${API_PORT}"
auth       = "${RPORTD_API_USER:-admin}:${RPORTD_API_PASSWORD:?RPORTD_API_PASSWORD required}"
jwt_secret = "${RPORTD_JWT_SECRET:?RPORTD_JWT_SECRET required}"
cors       = ["${RPORTD_CORS_ORIGINS:-*}"]

[logging]
log_file  = "/var/log/rport/rportd.log"
log_level = "info"
CONF
  echo "[entrypoint] no mounted config; using inline fallback"
fi

exec rportd -c "$CONFIG_LIVE" "$@"
