#!/usr/bin/env sh
# Container/Server/entrypoint.sh
# Patches the runtime rportd config and launches rportd.
set -eu

CONFIG_SRC="/etc/rport/rportd.conf"
CONFIG_LIVE="/tmp/rportd.runtime.conf"

# pairing_url override is only applied when an explicit env value is given.
# X-Forwarded-* values are HTTP request headers, not startup environment
# variables, and HOSTNAME inside Docker is the random container ID – not a
# useful default. For everything else, keep the value baked into the mounted
# config (rportd applies trust_proxy at request time for header discovery).
PAIRING_URL_OVERRIDE="${OPENRPORT_PAIRING_PUBLIC_URL:-}"
if [ -n "$PAIRING_URL_OVERRIDE" ]; then
  echo "[entrypoint] pairing_url override = ${PAIRING_URL_OVERRIDE}"
else
  echo "[entrypoint] using pairing_url from config (no OPENRPORT_PAIRING_PUBLIC_URL set)"
fi

# ── Config preparation ─────────────────────────────────────────────────────────
if [ -f "$CONFIG_SRC" ]; then
  cp "$CONFIG_SRC" "$CONFIG_LIVE"
  if [ -n "$PAIRING_URL_OVERRIDE" ]; then
    sed -i "s|pairing_url = \".*\"|pairing_url = \"${PAIRING_URL_OVERRIDE}\"|g" "$CONFIG_LIVE"
  fi
else
  # Minimal fallback config when no mount is provided.
  FALLBACK_PAIRING_URL="${PAIRING_URL_OVERRIDE:-http://openrport-pairing:${OPENRPORT_PAIRING_PORT:-9978}}"
  cat > "$CONFIG_LIVE" <<CONF
[server]
address = "0.0.0.0:8081"
data_dir = "/var/lib/rport"
pairing_url = "${FALLBACK_PAIRING_URL}"
auth = "${RPORTD_CLIENT_AUTH:-clientauth1:1234}"

[api]
address = "0.0.0.0:8080"
auth = "${RPORTD_API_USER:-admin}:${RPORTD_API_PASSWORD:-changeme}"
cors = ["${RPORTD_CORS_ORIGINS:-*}"]
CONF
fi

exec rportd -c "$CONFIG_LIVE" "$@"
