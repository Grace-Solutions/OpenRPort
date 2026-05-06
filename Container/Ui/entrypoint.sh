#!/usr/bin/env sh
# Container/Ui/entrypoint.sh
# Resolves NUXT_API_URL at runtime (so the image is deployment-mode agnostic)
# and launches the Nuxt server.
set -eu

# ── Resolve API URL ────────────────────────────────────────────────────────────
# Priority: explicit NUXT_API_URL > header-derived > internal service name
resolve_api_url() {
  if [ -n "${NUXT_API_URL:-}" ]; then
    echo "${NUXT_API_URL}"
    return
  fi
  if [ "${OPENRPORT_AUTO_DISCOVER_PUBLIC_URL:-true}" = "true" ]; then
    PROTO="${HTTP_X_FORWARDED_PROTO:-http}"
    HOST="${HTTP_X_FORWARDED_HOST:-${HOSTNAME:-localhost}}"
    PORT_PART="${HTTP_X_FORWARDED_PORT:-}"
    SERVER_BASE="${OPENRPORT_SERVER_BASE_PATH:-/}"
    if [ -n "$PORT_PART" ] && [ "$PORT_PART" != "80" ] && [ "$PORT_PART" != "443" ]; then
      echo "${PROTO}://${HOST}:${PORT_PART}${SERVER_BASE%/}"
    else
      echo "${PROTO}://${HOST}${SERVER_BASE%/}"
    fi
    return
  fi
  # Internal fallback
  echo "http://openrport-server:${OPENRPORT_SERVER_API_PORT:-8080}"
}

export NUXT_API_URL="$(resolve_api_url)"
export NUXT_APP_BASE_URL="${NUXT_APP_BASE_URL:-/ui}"

echo "[entrypoint] NUXT_API_URL      = ${NUXT_API_URL}"
echo "[entrypoint] NUXT_APP_BASE_URL = ${NUXT_APP_BASE_URL}"

exec node /app/.output/server/index.mjs "$@"
