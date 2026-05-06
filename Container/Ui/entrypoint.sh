#!/usr/bin/env sh
# Container/Ui/entrypoint.sh
# Resolves NUXT_API_URL at runtime (so the image is deployment-mode agnostic)
# and launches the Nuxt server. When NUXT_PUBLIC_API_URL is empty (typical
# for subpath deployments) we fall back to a relative URL so the browser
# uses the same origin as the page.
set -eu

if [ -n "${NUXT_PUBLIC_API_URL:-}" ]; then
  RESOLVED_API_URL="${NUXT_PUBLIC_API_URL}"
elif [ -n "${NUXT_API_URL:-}" ]; then
  RESOLVED_API_URL="${NUXT_API_URL}"
else
  # Subpath default - the browser hits the same edge, /api/v1 is routed
  # to the Server by the Binaries proxy.
  RESOLVED_API_URL=""
fi

export NUXT_API_URL="${RESOLVED_API_URL}"
export NUXT_PUBLIC_API_URL="${RESOLVED_API_URL}"
export NUXT_APP_BASE_URL="${NUXT_APP_BASE_URL:-/ui}"
export NUXT_PUBLIC_AUTH_MODE="${NUXT_PUBLIC_AUTH_MODE:-both}"
export HOST="${HOST:-${OPENRPORT_UI_BIND_ADDRESS:-${OPENRPORT_BIND_ADDRESS:-0.0.0.0}}}"
export PORT="${UI_INTERNAL_PORT:-${PORT:-8083}}"

echo "[entrypoint] NUXT_API_URL          = ${NUXT_API_URL}"
echo "[entrypoint] NUXT_PUBLIC_API_URL   = ${NUXT_PUBLIC_API_URL}"
echo "[entrypoint] NUXT_APP_BASE_URL     = ${NUXT_APP_BASE_URL}"
echo "[entrypoint] NUXT_PUBLIC_AUTH_MODE = ${NUXT_PUBLIC_AUTH_MODE}"
echo "[entrypoint] HOST:PORT             = ${HOST}:${PORT}"

exec node /app/.output/server/index.mjs "$@"
