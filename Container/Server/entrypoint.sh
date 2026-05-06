#!/usr/bin/env sh
# Container/Server/entrypoint.sh
# Resolves public URL from env or proxy headers, patches config, launches rportd.
set -eu

CONFIG_SRC="/etc/rport/rportd.conf"
CONFIG_LIVE="/tmp/rportd.runtime.conf"

# ── URL resolution helper ──────────────────────────────────────────────────────
# Priority: explicit env > header-derived > internal default
resolve_server_url() {
  if [ -n "${OPENRPORT_SERVER_PUBLIC_URL:-}" ]; then
    echo "${OPENRPORT_SERVER_PUBLIC_URL}"
    return
  fi
  # Headers are injected by the proxy at request time; for startup we use what's
  # baked into the environment by the proxy or operator.
  if [ "${OPENRPORT_AUTO_DISCOVER_PUBLIC_URL:-true}" = "true" ]; then
    PROTO="${HTTP_X_FORWARDED_PROTO:-${HTTP_FORWARDED_PROTO:-http}}"
    HOST="${HTTP_X_FORWARDED_HOST:-${HOSTNAME:-localhost}}"
    PORT_PART="${HTTP_X_FORWARDED_PORT:-}"
    PREFIX="${HTTP_X_FORWARDED_PREFIX:-${OPENRPORT_SERVER_BASE_PATH:-/}}"
    if [ -n "$PORT_PART" ] && [ "$PORT_PART" != "80" ] && [ "$PORT_PART" != "443" ]; then
      echo "${PROTO}://${HOST}:${PORT_PART}${PREFIX%/}"
    else
      echo "${PROTO}://${HOST}${PREFIX%/}"
    fi
    return
  fi
  echo "http://localhost:${OPENRPORT_SERVER_API_PORT:-8080}"
}

resolve_pairing_url() {
  if [ -n "${OPENRPORT_PAIRING_PUBLIC_URL:-}" ]; then
    echo "${OPENRPORT_PAIRING_PUBLIC_URL}"
    return
  fi
  SERVER_URL="$(resolve_server_url)"
  MODE="${OPENRPORT_DEPLOYMENT_MODE:-subpath}"
  if [ "$MODE" = "subpath" ]; then
    PAIRING_BASE="${OPENRPORT_PAIRING_BASE_PATH:-/pairing}"
    echo "${SERVER_URL%/}${PAIRING_BASE}"
  else
    echo "http://openrport-pairing:${OPENRPORT_PAIRING_PORT:-9978}"
  fi
}

PAIRING_URL="$(resolve_pairing_url)"
echo "[entrypoint] pairing_url = ${PAIRING_URL}"

# ── Config preparation ─────────────────────────────────────────────────────────
if [ -f "$CONFIG_SRC" ]; then
  cp "$CONFIG_SRC" "$CONFIG_LIVE"
  # Patch pairing_url in the live config (sed in-place)
  sed -i "s|pairing_url = \".*\"|pairing_url = \"${PAIRING_URL}\"|g" "$CONFIG_LIVE"
else
  # Minimal fallback config when no mount is provided
  cat > "$CONFIG_LIVE" <<CONF
[server]
address = "0.0.0.0:8081"
data_dir = "/var/lib/rport"
pairing_url = "${PAIRING_URL}"

[api]
address = "0.0.0.0:8080"
auth = "${RPORTD_API_USER:-admin}:${RPORTD_API_PASSWORD:-changeme}"
cors = ["${RPORTD_CORS_ORIGINS:-*}"]
CONF
fi

exec rportd --config "$CONFIG_LIVE" "$@"
