#!/usr/bin/env bash
# scripts/FetchAgentBinaries.sh
# Pre-fetches the rport agent binaries into the Binaries bind-mount so the
# stack can hand them to agents without depending on github.com /
# download.openrport.io at runtime.
#
# Layout produced (under ${STACK_BINDMOUNTROOT}/OpenRPort/Binaries/Data):
#   rport/stable/Linux_x86_64.tar.gz
#   rport/stable/Linux_arm64.tar.gz
#   rport/stable/Linux_armv7.tar.gz
#   rport/stable/Windows_x86_64.zip
#   rport/stable/Windows_x86_64.msi          (when published)
#   by-version/<version>/Linux_x86_64.tar.gz (mirror of the GitHub URL)
#   manifest.json                            (version, sha256, size, mtime)
#
# Optional S3 offload: if RPORT_S3_BUCKET is set the artefacts are also
# uploaded under the same key prefix. Presigned-URL serving is a follow-up
# integration in the Pairing service and is not yet wired up here.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "$0")/.." && pwd))"
ENV_FILE="${REPO_ROOT}/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

STACK_BINDMOUNTROOT="${STACK_BINDMOUNTROOT:-/mnt/data/docker/stacks}"
RPORT_VERSION="${RPORT_VERSION:-latest}"
GH_REPO="${RPORT_GH_REPO:-openrport/openrport}"

OUT_ROOT="${STACK_BINDMOUNTROOT}/OpenRPort/Binaries/Data"
mkdir -p "${OUT_ROOT}/rport/stable" "${OUT_ROOT}/by-version"

echo "==> FetchAgentBinaries"
echo "    OUT_ROOT         = ${OUT_ROOT}"
echo "    RPORT_VERSION    = ${RPORT_VERSION}"
echo "    GH_REPO          = ${GH_REPO}"

# ── Resolve version ─────────────────────────────────────────────────────────
if [ "${RPORT_VERSION}" = "latest" ]; then
  echo "--> resolving latest stable from GitHub releases ..."
  if ! VERSION_TAG=$(curl -fsSL "https://api.github.com/repos/${GH_REPO}/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1); then
    echo "    [WARN] failed to query GitHub API – falling back to 'stable'" >&2
    VERSION_TAG=""
  fi
else
  VERSION_TAG="${RPORT_VERSION}"
fi
VERSION_TAG="${VERSION_TAG#v}"
echo "    resolved version = ${VERSION_TAG:-<unknown>}"

# ── Asset list (filename → arch label used by templates) ───────────────────
ASSETS=(
  "rport_${VERSION_TAG}_Linux_x86_64.tar.gz|Linux_x86_64.tar.gz"
  "rport_${VERSION_TAG}_Linux_arm64.tar.gz|Linux_arm64.tar.gz"
  "rport_${VERSION_TAG}_Linux_armv7.tar.gz|Linux_armv7.tar.gz"
  "rport_${VERSION_TAG}_Windows_x86_64.zip|Windows_x86_64.zip"
)

fetch() {
  local src="$1" dst="$2"
  if [ -f "$dst" ]; then
    echo "    [skip]  $(basename "$dst") already present"
    return 0
  fi
  echo "    [fetch] $src"
  if ! curl -fsSL --retry 3 --retry-delay 2 -o "${dst}.part" "$src"; then
    echo "    [WARN]  could not download $src" >&2
    rm -f "${dst}.part"
    return 1
  fi
  mv "${dst}.part" "$dst"
}

if [ -z "${VERSION_TAG}" ]; then
  echo "[WARN] no version resolved; skipping downloads. Stack will work but"
  echo "       agents downloading via /binaries will get 404 until you re-run"
  echo "       this script with a reachable GitHub or RPORT_VERSION set."
  exit 0
fi

MANIFEST_TMP="$(mktemp)"
{ echo "{"; echo "  \"version\": \"${VERSION_TAG}\","; echo "  \"fetched_at\": \"$(date -u +%FT%TZ)\","; echo "  \"source\": \"fetch\","; echo "  \"files\": ["; } > "$MANIFEST_TMP"

FIRST=1
for entry in "${ASSETS[@]}"; do
  upstream="${entry%%|*}"
  label="${entry##*|}"
  url="https://github.com/${GH_REPO}/releases/download/${VERSION_TAG}/${upstream}"
  versioned_dir="${OUT_ROOT}/by-version/${VERSION_TAG}"
  mkdir -p "$versioned_dir"
  versioned_path="${versioned_dir}/${upstream}"
  stable_path="${OUT_ROOT}/rport/stable/${label}"

  if fetch "$url" "$versioned_path"; then
    cp -f "$versioned_path" "$stable_path"
    sha=$(sha256sum "$versioned_path" | awk '{print $1}')
    size=$(stat -c %s "$versioned_path")
    [ $FIRST -eq 0 ] && echo "    ," >> "$MANIFEST_TMP"
    FIRST=0
    {
      echo "    {"
      echo "      \"label\": \"${label}\","
      echo "      \"upstream\": \"${upstream}\","
      echo "      \"sha256\": \"${sha}\","
      echo "      \"size\": ${size}"
      echo "    }"
    } >> "$MANIFEST_TMP"
  fi
done

{ echo "  ]"; echo "}"; } >> "$MANIFEST_TMP"
mv "$MANIFEST_TMP" "${OUT_ROOT}/manifest.json"
chmod 644 "${OUT_ROOT}/manifest.json"
find "${OUT_ROOT}" -type f -exec chmod 644 {} +
find "${OUT_ROOT}" -type d -exec chmod 755 {} +
echo "    wrote ${OUT_ROOT}/manifest.json"

# ── Optional S3 offload ────────────────────────────────────────────────────
if [ -n "${RPORT_S3_BUCKET:-}" ] && [ -n "${RPORT_S3_ACCESS_KEY:-}" ]; then
  if command -v aws >/dev/null 2>&1; then
    S3_PREFIX="${RPORT_S3_PREFIX:-OpenRPort/Binaries}"
    echo "--> uploading to s3://${RPORT_S3_BUCKET}/${S3_PREFIX}/ ..."
    AWS_ACCESS_KEY_ID="${RPORT_S3_ACCESS_KEY}" \
    AWS_SECRET_ACCESS_KEY="${RPORT_S3_SECRET_KEY}" \
    aws s3 sync "${OUT_ROOT}" "s3://${RPORT_S3_BUCKET}/${S3_PREFIX}/" \
      ${RPORT_S3_REGION:+--region "${RPORT_S3_REGION}"} \
      ${RPORT_S3_ENDPOINT:+--endpoint-url "${RPORT_S3_ENDPOINT}"} \
      --no-progress
  else
    echo "[WARN] aws CLI not installed; skipping S3 upload" >&2
  fi
fi

echo "==> done."
