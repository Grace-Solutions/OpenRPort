#!/usr/bin/env sh
# Container/Pairing/entrypoint.sh
# Patches the runtime pairing config and launches rport-pairing.
set -eu

CONFIG_SRC="/etc/rport-pairing/config.toml"
CONFIG_LIVE="/tmp/rport-pairing.runtime.toml"

# Only override the URL when an explicit env value is given. X-Forwarded-* are
# request-time HTTP headers, not startup environment variables, and HOSTNAME
# inside Docker is the random container ID.
PAIRING_URL_OVERRIDE="${OPENRPORT_PAIRING_PUBLIC_URL:-}"
PAIRING_BASE="${OPENRPORT_PAIRING_BASE_PATH:-/pairing}"
if [ -n "$PAIRING_URL_OVERRIDE" ]; then
  echo "[entrypoint] pairing url override = ${PAIRING_URL_OVERRIDE}"
else
  echo "[entrypoint] using pairing url from config (no OPENRPORT_PAIRING_PUBLIC_URL set)"
fi
echo "[entrypoint] pairing base_path = ${PAIRING_BASE}"

# ── Config preparation ─────────────────────────────────────────────────────────
if [ -f "$CONFIG_SRC" ]; then
  cp "$CONFIG_SRC" "$CONFIG_LIVE"
  if [ -n "$PAIRING_URL_OVERRIDE" ]; then
    sed -i "s|url = \".*\"|url = \"${PAIRING_URL_OVERRIDE}\"|g" "$CONFIG_LIVE"
  fi
else
  PORT="${PAIRING_INTERNAL_PORT:-9978}"
  FALLBACK_URL="${PAIRING_URL_OVERRIDE:-http://localhost:${PORT}}"
  cat > "$CONFIG_LIVE" <<CONF
[server]
  address = "0.0.0.0:${PORT}"
  url = "${FALLBACK_URL}"
CONF
fi

# rport-pairing uses -c flag (not --config)
exec rport-pairing -c "$CONFIG_LIVE" "$@"
