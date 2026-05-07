#!/usr/bin/env sh
# Container/Pairing/entrypoint.sh
# Renders config.toml at startup and launches rport-pairing. A bind-mounted
# /etc/rport-pairing/config.toml wins; otherwise the full config (including
# the [downloads] block) is rendered from environment variables so the image
# is self-contained and deployable without the OpenRPort repo.
set -eu

CONFIG_SRC="/etc/rport-pairing/config.toml"
CONFIG_LIVE="/tmp/rport-pairing.runtime.toml"

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
  echo "[entrypoint] using ${CONFIG_SRC}"
else
  PORT="${PAIRING_INTERNAL_PORT:-38102}"
  BIND_DEFAULT="${OPENRPORT_BIND_ADDRESS:-0.0.0.0}"
  BIND="${OPENRPORT_PAIRING_BIND_ADDRESS:-$BIND_DEFAULT}"
  FALLBACK_URL="${PAIRING_URL_OVERRIDE:-http://localhost:${PORT}}"

  # Download endpoints baked into rendered installer scripts. Empty values
  # fall back to upstream openrport.io defaults inside rport-pairing.
  DL_BINARIES="${OPENRPORT_PAIRING_DOWNLOADS_BINARIES_BASE_URL:-}"
  DL_TACO="${OPENRPORT_PAIRING_DOWNLOADS_TACO_BASE_URL:-}"
  DL_REPO="${OPENRPORT_PAIRING_DOWNLOADS_REPO_BASE_URL:-}"
  DL_RELEASE="${OPENRPORT_PAIRING_DOWNLOADS_RELEASE:-stable}"

  cat > "$CONFIG_LIVE" <<CONF
# Rendered by Container/Pairing/entrypoint.sh from environment variables.
[server]
  address = "${BIND}:${PORT}"
  url     = "${FALLBACK_URL}"

[downloads]
  binaries_base_url = "${DL_BINARIES}"
  taco_base_url     = "${DL_TACO}"
  repo_base_url     = "${DL_REPO}"
  release           = "${DL_RELEASE}"
CONF
  echo "[entrypoint] rendered ${CONFIG_LIVE} from environment"
fi

# rport-pairing uses -c flag (not --config)
exec rport-pairing -c "$CONFIG_LIVE" "$@"
