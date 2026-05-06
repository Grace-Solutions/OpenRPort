#!/usr/bin/env sh
# Container/Ui/entrypoint.sh
# Resolves NUXT_API_URL at runtime (so the image is deployment-mode agnostic)
# and launches the Nuxt server.
set -eu

# Priority: explicit NUXT_API_URL > internal service-name fallback.
# HOSTNAME-based auto-discovery is not used: HOSTNAME inside Docker is the
# random container ID, and X-Forwarded-* are HTTP request headers, not
# startup environment variables. Set NUXT_API_URL explicitly when running
# behind a reverse proxy.
if [ -n "${NUXT_API_URL:-}" ]; then
  RESOLVED_API_URL="${NUXT_API_URL}"
else
  RESOLVED_API_URL="http://openrport-server:${OPENRPORT_SERVER_API_PORT:-8080}"
fi

export NUXT_API_URL="${RESOLVED_API_URL}"
# NUXT_PUBLIC_API_URL overrides runtimeConfig.public.apiUrl in the Nitro server
# so the SPA receives the correct URL across deployment modes.
export NUXT_PUBLIC_API_URL="${NUXT_PUBLIC_API_URL:-${RESOLVED_API_URL}}"
export NUXT_APP_BASE_URL="${NUXT_APP_BASE_URL:-/ui}"

echo "[entrypoint] NUXT_API_URL        = ${NUXT_API_URL}"
echo "[entrypoint] NUXT_PUBLIC_API_URL = ${NUXT_PUBLIC_API_URL}"
echo "[entrypoint] NUXT_APP_BASE_URL   = ${NUXT_APP_BASE_URL}"

exec node /app/.output/server/index.mjs "$@"
