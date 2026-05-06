#!/bin/sh
# Container/Binaries/entrypoint.sh
# Renders nginx.conf.template with current env vars and starts nginx.
# The template uses ${VAR} placeholders that envsubst replaces.
set -eu

BINARIES_BASE="${OPENRPORT_BINARIES_BASE_PATH:-/binaries}"
BINARIES_INTERNAL_PORT="${BINARIES_INTERNAL_PORT:-8080}"

export BINARIES_BASE BINARIES_INTERNAL_PORT

mkdir -p /etc/nginx/conf.d
envsubst '${BINARIES_BASE} ${BINARIES_INTERNAL_PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

echo "[entrypoint] BINARIES_BASE          = ${BINARIES_BASE}"
echo "[entrypoint] BINARIES_INTERNAL_PORT = ${BINARIES_INTERNAL_PORT}"

exec "$@"
