#!/usr/bin/env bash
# scripts/TestStack.sh
# Full stack integration test. Run after 'make up'.
# Exit 0 = all tests passed.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="${REPO_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then set -a; source "$ENV_FILE"; set +a; fi

SERVER_PORT="${OPENRPORT_SERVER_API_PORT:-8080}"
PAIRING_PORT="${OPENRPORT_PAIRING_PORT:-9978}"
UI_PORT="${OPENRPORT_UI_PORT:-3000}"
PAIRING_BASE="${OPENRPORT_PAIRING_BASE_PATH:-/pairing}"

PASS=0; FAIL=0

pass() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*" >&2; FAIL=$((FAIL+1)); }

http_ok() {
  local label="$1" url="$2"
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  if [[ "$code" == "200" || "$code" == "401" ]]; then
    pass "$label ($url) → HTTP $code"
  else
    fail "$label ($url) → HTTP $code (expected 200 or 401)"
  fi
}

echo "==> TestStack.sh"
echo ""

# ── 1. Container health ───────────────────────────────────────────────────────
echo "--- Container Status ---"
for cname in openrport-server openrport-pairing openrport-ui; do
  if docker ps --filter "name=${cname}" --filter "status=running" | grep -q "${cname}"; then
    pass "$cname is running"
  else
    fail "$cname is NOT running"
  fi
done

# ── 2. Endpoint reachability ─────────────────────────────────────────────────
echo ""
echo "--- Endpoint Reachability ---"
http_ok "Server API"     "http://localhost:${SERVER_PORT}/api/v1/status"
http_ok "Pairing root"   "http://localhost:${PAIRING_PORT}/"
http_ok "UI"             "http://localhost:${UI_PORT}/"

# ── 3. Pairing script generation ─────────────────────────────────────────────
echo ""
echo "--- Pairing Script Generation ---"
PAIR_RESP=$(curl -s -X POST "http://localhost:${PAIRING_PORT}/" \
  -H "Content-Type: application/json" \
  --data-raw '{"connect_url":"http://test-server:8080","client_id":"testclient","password":"testpass","fingerprint":"aa:bb:cc"}' \
  2>/dev/null || echo "FAIL")

if echo "$PAIR_RESP" | grep -q "pairing_code"; then
  pass "Pairing deposit returned pairing_code"
  CODE=$(echo "$PAIR_RESP" | grep -o '"pairing_code":"[^"]*"' | cut -d'"' -f4)
  if [[ -n "$CODE" ]]; then
    SCRIPT=$(curl -s "http://localhost:${PAIRING_PORT}/${CODE}" \
      -H "User-Agent: curl/linux" 2>/dev/null || echo "")
    if echo "$SCRIPT" | grep -q "test-server"; then
      pass "Install script contains correct server URL"
    else
      fail "Install script missing server URL. Script: ${SCRIPT:0:200}"
    fi
    if echo "$SCRIPT" | grep -q "http"; then
      pass "Install script contains valid URL"
    else
      fail "Install script appears malformed"
    fi
  fi
else
  fail "Pairing deposit failed. Response: ${PAIR_RESP:0:200}"
fi

# ── 4. Header discovery simulation ───────────────────────────────────────────
echo ""
echo "--- Header Discovery Simulation ---"
HEADER_RESP=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Forwarded-Proto: https" \
  -H "X-Forwarded-Host: rport.example.com" \
  -H "X-Forwarded-Port: 443" \
  "http://localhost:${PAIRING_PORT}/" 2>/dev/null || echo "000")
if [[ "$HEADER_RESP" == "200" || "$HEADER_RESP" == "404" ]]; then
  pass "Pairing service accepts proxy header requests (HTTP $HEADER_RESP)"
else
  fail "Pairing service rejected proxy header request (HTTP $HEADER_RESP)"
fi

# ── 5. Subpath check (if in subpath mode) ────────────────────────────────────
if [[ "${OPENRPORT_DEPLOYMENT_MODE:-subpath}" == "subpath" ]]; then
  echo ""
  echo "--- Subpath Mode Check ---"
  # Pairing should be accessible at its configured base path via the server port if proxied
  # We test that the pairing URL in the generated config is correct
  RPORTD_CONF="${REPO_ROOT}/Config/Server/rportd.conf"
  if [ -f "$RPORTD_CONF" ]; then
    if grep -q "pairing_url" "$RPORTD_CONF"; then
      PAIRING_IN_CONF=$(grep "pairing_url" "$RPORTD_CONF" | cut -d'"' -f2)
      if [[ "$PAIRING_IN_CONF" == *"$PAIRING_BASE"* || "$PAIRING_IN_CONF" == *"pairing"* ]]; then
        pass "rportd.conf pairing_url contains base path: $PAIRING_IN_CONF"
      else
        fail "rportd.conf pairing_url does not respect base path: $PAIRING_IN_CONF"
      fi
    else
      fail "rportd.conf missing pairing_url"
    fi
  else
    fail "Config/Server/rportd.conf not found – run make generate-config first"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  PASSED: $PASS"
echo "  FAILED: $FAIL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$FAIL" -gt 0 ]]; then
  echo "Stack test FAILED" >&2
  exit 1
fi
echo "Stack test PASSED"
