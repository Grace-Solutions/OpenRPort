#!/usr/bin/env bash
# scripts/BuildAgentBinaries.sh
# Builds the rport agent from src/Server/cmd/rport for all supported targets
# and emits the same on-disk layout as scripts/FetchAgentBinaries.sh so the
# Pairing service can serve them under /binaries/ without depending on
# github.com or download.openrport.io at runtime.
#
# Layout produced (under ${STACK_BINDMOUNTROOT}/OpenRPort/Binaries/Data):
#   rport/stable/Linux_x86_64.tar.gz
#   rport/stable/Linux_arm64.tar.gz
#   rport/stable/Linux_armv7.tar.gz
#   rport/stable/Windows_x86_64.zip
#   by-version/<version>/rport_<version>_Linux_x86_64.tar.gz
#   manifest.json
#
# Version selection:
#   RPORT_VERSION=<x.y.z>  -> use it verbatim, stamped via -ldflags
#   RPORT_VERSION=latest   -> derive from `git rev-parse --short HEAD` of the
#                             src/Server subtree as 0.0.0-build-<sha>
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))"
ENV_FILE="${REPO_ROOT}/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

STACK_BINDMOUNTROOT="${STACK_BINDMOUNTROOT:-/mnt/data/docker/stacks}"
RPORT_VERSION="${RPORT_VERSION:-latest}"
SERVER_SRC="${REPO_ROOT}/src/Server"

OUT_ROOT="${STACK_BINDMOUNTROOT}/OpenRPort/Binaries/Data"
mkdir -p "${OUT_ROOT}/rport/stable" "${OUT_ROOT}/by-version"

if ! command -v go >/dev/null 2>&1; then
  echo "[ERROR] go toolchain not found on PATH; install Go 1.21+ to build the agent" >&2
  exit 1
fi

if [ ! -d "${SERVER_SRC}/cmd/rport" ]; then
  echo "[ERROR] ${SERVER_SRC}/cmd/rport not found; ensure subtree is in place" >&2
  exit 1
fi

if [ "${RPORT_VERSION}" = "latest" ]; then
  SHA="$(git -C "${SERVER_SRC}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  VERSION_TAG="0.0.0-build-${SHA}"
else
  VERSION_TAG="${RPORT_VERSION#v}"
fi

echo "==> BuildAgentBinaries"
echo "    OUT_ROOT      = ${OUT_ROOT}"
echo "    SERVER_SRC    = ${SERVER_SRC}"
echo "    VERSION_TAG   = ${VERSION_TAG}"
echo "    Go            = $(go version)"

LDFLAGS="-s -w -X github.com/openrport/openrport/share.BuildVersion=${VERSION_TAG}"

# Each entry: GOOS|GOARCH|GOARM|label|upstream-filename|archiver
TARGETS=(
  "linux|amd64||Linux_x86_64.tar.gz|rport_${VERSION_TAG}_Linux_x86_64.tar.gz|tar"
  "linux|arm64||Linux_arm64.tar.gz|rport_${VERSION_TAG}_Linux_arm64.tar.gz|tar"
  "linux|arm|7|Linux_armv7.tar.gz|rport_${VERSION_TAG}_Linux_armv7.tar.gz|tar"
  "windows|amd64||Windows_x86_64.zip|rport_${VERSION_TAG}_Windows_x86_64.zip|zip"
)

WORKDIR="$(mktemp -d -t rport-build-XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

CONF_SRC="${SERVER_SRC}/rport.example.conf"
[ -f "${CONF_SRC}" ] || { echo "[ERROR] ${CONF_SRC} missing" >&2; exit 1; }

MANIFEST_TMP="$(mktemp)"
{
  echo "{"
  echo "  \"version\": \"${VERSION_TAG}\","
  echo "  \"built_at\": \"$(date -u +%FT%TZ)\","
  echo "  \"source\": \"build\","
  echo "  \"files\": ["
} > "$MANIFEST_TMP"

FIRST=1
for entry in "${TARGETS[@]}"; do
  IFS='|' read -r goos goarch goarm label upstream archiver <<<"${entry}"
  echo "--> ${goos}/${goarch}${goarm:+v$goarm} -> ${upstream}"

  STAGE="${WORKDIR}/${goos}-${goarch}${goarm:+v$goarm}"
  mkdir -p "${STAGE}"
  cp "${CONF_SRC}" "${STAGE}/rport.example.conf"

  if [ "${goos}" = "windows" ]; then
    BINARY_NAME="rport.exe"
  else
    BINARY_NAME="rport"
  fi

  build_env=( "CGO_ENABLED=0" "GOOS=${goos}" "GOARCH=${goarch}" )
  [ -n "${goarm}" ] && build_env+=( "GOARM=${goarm}" )
  ( cd "${SERVER_SRC}" && \
    env "${build_env[@]}" go build -ldflags "${LDFLAGS}" -o "${STAGE}/${BINARY_NAME}" ./cmd/rport )

  versioned_dir="${OUT_ROOT}/by-version/${VERSION_TAG}"
  mkdir -p "${versioned_dir}"
  versioned_path="${versioned_dir}/${upstream}"
  stable_path="${OUT_ROOT}/rport/stable/${label}"

  if [ "${archiver}" = "tar" ]; then
    ( cd "${STAGE}" && tar czf "${versioned_path}" "${BINARY_NAME}" rport.example.conf )
  else
    ( cd "${STAGE}" && zip -q "${versioned_path}" "${BINARY_NAME}" rport.example.conf )
  fi
  cp -f "${versioned_path}" "${stable_path}"

  sha=$(sha256sum "${versioned_path}" | awk '{print $1}')
  size=$(stat -c %s "${versioned_path}")
  [ ${FIRST} -eq 0 ] && echo "    ," >> "$MANIFEST_TMP"
  FIRST=0
  {
    echo "    {"
    echo "      \"label\": \"${label}\","
    echo "      \"upstream\": \"${upstream}\","
    echo "      \"sha256\": \"${sha}\","
    echo "      \"size\": ${size}"
    echo "    }"
  } >> "$MANIFEST_TMP"
done

{ echo "  ]"; echo "}"; } >> "$MANIFEST_TMP"
mv "$MANIFEST_TMP" "${OUT_ROOT}/manifest.json"
chmod 644 "${OUT_ROOT}/manifest.json"
find "${OUT_ROOT}" -type f -exec chmod 644 {} +
find "${OUT_ROOT}" -type d -exec chmod 755 {} +
echo "    wrote ${OUT_ROOT}/manifest.json"
echo "==> done."
