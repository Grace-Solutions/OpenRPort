#!/usr/bin/env sh
# Container/Pairing/entrypoint.sh
# Resolves the public pairing URL, writes config, launches rport-pairing.
set -eu

CONFIG_SRC="/etc/rport-pairing/config.toml"
CONFIG_LIVE="/tmp/rport-pairing.runtime.toml"

# ── Resolve public URL ─────────────────────────────────────────────────────────
# Priority: explicit OPENRPORT_PAIRING_PUBLIC_URL > header-derived > fallback
resolve_pairing_url() {
  if [ -n "${OPENRPORT_PAIRING_PUBLIC_URL:-}" ]; then
    echo "${OPENRPORT_PAIRING_PUBLIC_URL}"
    return
  fi
  if [ "${OPENRPORT_AUTO_DISCOVER_PUBLIC_URL:-true}" = "true" ]; then
    PROTO="${HTTP_X_FORWARDED_PROTO:-http}"
    HOST="${HTTP_X_FORWARDED_HOST:-${HOSTNAME:-localhost}}"
    PORT_PART="${HTTP_X_FORWARDED_PORT:-}"
    PREFIX="${HTTP_X_FORWARDED_PREFIX:-${OPENRPORT_PAIRING_BASE_PATH:-/pairing}}"
    if [ -n "$PORT_PART" ] && [ "$PORT_PART" != "80" ] && [ "$PORT_PART" != "443" ]; then
      echo "${PROTO}://${HOST}:${PORT_PART}${PREFIX%/}"
    else
      echo "${PROTO}://${HOST}${PREFIX%/}"
    fi
    return
  fi
  echo "http://localhost:${OPENRPORT_PAIRING_PORT:-9978}"
}

PAIRING_URL="$(resolve_pairing_url)"
PAIRING_BASE="${OPENRPORT_PAIRING_BASE_PATH:-/pairing}"
echo "[entrypoint] pairing base_url = ${PAIRING_URL}"
echo "[entrypoint] pairing base_path = ${PAIRING_BASE}"

# ── Config preparation ─────────────────────────────────────────────────────────
if [ -f "$CONFIG_SRC" ]; then
  cp "$CONFIG_SRC" "$CONFIG_LIVE"
  # Patch the url in the live config (TOML: url = "...")
  sed -i "s|url = \".*\"|url = \"${PAIRING_URL}\"|g" "$CONFIG_LIVE"
else
  cat > "$CONFIG_LIVE" <<CONF
[server]
  address = "0.0.0.0:9978"
  url = "${PAIRING_URL}"
CONF
fi

# rport-pairing uses -c flag (not --config)
exec rport-pairing -c "$CONFIG_LIVE" "$@"
