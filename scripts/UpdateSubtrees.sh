#!/usr/bin/env bash
# scripts/UpdateSubtrees.sh
# Pull latest upstream changes into all subtrees.
# Safe to run repeatedly; use --squash to keep history clean.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "==> Pulling latest upstream changes into subtrees..."

echo ""
echo "--- src/Server (openrport master) ---"
git subtree pull \
  --prefix src/Server \
  https://github.com/openrport/openrport master \
  --squash

echo ""
echo "--- src/Pairing (rport-pairing main) ---"
git subtree pull \
  --prefix src/Pairing \
  https://github.com/openrport/rport-pairing main \
  --squash

echo ""
echo "--- src/Ui (openrport-ui main) ---"
git subtree pull \
  --prefix src/Ui \
  https://github.com/openrport/openrport-ui main \
  --squash

echo ""
echo "==> All subtrees updated."
