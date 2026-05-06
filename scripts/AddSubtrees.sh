#!/usr/bin/env bash
# scripts/AddSubtrees.sh
# Initial one-time import of all three upstream repos as git subtrees.
# Run this once after cloning this repo.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "==> Adding git subtrees (this may take a moment)..."

echo ""
echo "--- src/Server (openrport) ---"
if [ -d "src/Server/.git" ] || git log --oneline -- src/Server 2>/dev/null | grep -q .; then
  echo "src/Server already has history – skipping. Run UpdateSubtrees.sh to pull latest."
else
  git subtree add \
    --prefix src/Server \
    https://github.com/openrport/openrport master \
    --squash
fi

echo ""
echo "--- src/Pairing (rport-pairing) ---"
if git log --oneline -- src/Pairing 2>/dev/null | grep -q .; then
  echo "src/Pairing already has history – skipping."
else
  git subtree add \
    --prefix src/Pairing \
    https://github.com/openrport/rport-pairing main \
    --squash
fi

echo ""
echo "--- src/Ui (openrport-ui) ---"
if git log --oneline -- src/Ui 2>/dev/null | grep -q .; then
  echo "src/Ui already has history – skipping."
else
  git subtree add \
    --prefix src/Ui \
    https://github.com/openrport/openrport-ui main \
    --squash
fi

echo ""
echo "==> All subtrees added successfully."
echo "    Verify with: git log --oneline"
