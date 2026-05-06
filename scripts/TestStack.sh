#!/usr/bin/env bash
# scripts/TestStack.sh
# Full stack integration test. Run after 'make up'. Exit 0 = all tests passed.
#
# Each service runs with network_mode: host and listens directly on its
# *_INTERNAL_PORT on the host. The operator's external nginx is the single
# proxy layer and is documented in docs/nginx.sample.conf.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="${REPO_ROOT}/.env"
if [ -f "$ENV_FILE" ]; then set -a; source "$ENV_FILE"; set +a; fi

STACK_BINDMOUNTROOT="${STACK_BINDMOUNTROOT:-/mnt/data/docker/stacks}"
HOST="${TESTSTACK_HOST:-127.0.0.1}"

SERVER_API_PORT="${SERVER_API_INTERNAL_PORT:-${SERVER_API_PUBLISH_PORT:-8080}}"
SERVER_CLIENT_PORT="${SERVER_CLIENT_INTERNAL_PORT:-${SERVER_CLIENT_PUBLISH_PORT:-8081}}"
PAIRING_PORT="${PAIRING_INTERNAL_PORT:-${PAIRING_PUBLISH_PORT:-38102}}"
UI_PORT="${UI_INTERNAL_PORT:-${UI_PUBLISH_PORT:-38103}}"
BINARIES_BASE="${OPENRPORT_BINARIES_BASE_PATH:-/binaries}"
UI_BASE="${OPENRPORT_UI_BASE_PATH:-/ui}"

SERVER_API="http://${HOST}:${SERVER_API_PORT}"
PAIRING="http://${HOST}:${PAIRING_PORT}"
UI="http://${HOST}:${UI_PORT}"

API_USER="${RPORTD_API_USER:-admin}"
API_PASS="${RPORTD_API_PASSWORD:-}"

PASS=0; FAIL=0
pass() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*" >&2; FAIL=$((FAIL+1)); }

http_status() {
  curl -s -o /dev/null -w "%{http_code}" --max-time 8 "$@" 2>/dev/null || echo "000"
}

http_ok() {
  local label="$1" url="$2" expected="${3:-200,401}"
  local code; code=$(http_status "$url")
  if [[ ",${expected}," == *",${code},"* ]]; then
    pass "$label ($url) -> HTTP $code"
  else
    fail "$label ($url) -> HTTP $code (expected one of $expected)"
  fi
}

echo "==> TestStack.sh (host: ${HOST})"
echo ""

# 1. Container health
echo "--- Container Status ---"
for c in OPENRPORT-SERVER-00001 OPENRPORT-PAIRING-00001 OPENRPORT-UI-00001; do
  if docker ps --filter "name=^${c}$" --filter "status=running" --format '{{.Names}}' | grep -qx "${c}"; then
    pass "$c is running"
  else
    fail "$c is NOT running"
  fi
done

# 2. Per-service endpoint reachability (each on its own published port)
echo ""
echo "--- Endpoint Reachability (per service) ---"
http_ok "Server API"        "${SERVER_API}/api/v1/status"           "200,401"
http_ok "Pairing /update"   "${PAIRING}/update"                     "200"
http_ok "UI root"           "${UI}/"                                "200,301,302"
http_ok "UI base path"      "${UI}${UI_BASE}/"                      "200"
http_ok "Binaries manifest" "${PAIRING}${BINARIES_BASE}/manifest.json" "200"

# 3. API authenticated status
echo ""
echo "--- API Authenticated Probe ---"
if [[ -n "$API_PASS" ]]; then
  STATUS=$(curl -s -u "${API_USER}:${API_PASS}" --max-time 8 "${SERVER_API}/api/v1/status" || echo "")
  if echo "$STATUS" | grep -q '"connect_url"'; then
    pass "API /status returns connect_url"
  else
    fail "API /status missing connect_url. Body head: ${STATUS:0:200}"
  fi
  if echo "$STATUS" | grep -q '"pairing_url"'; then
    pass "API /status returns pairing_url"
  else
    fail "API /status missing pairing_url"
  fi
else
  fail "RPORTD_API_PASSWORD unset; cannot run authenticated probe"
fi

# 4. Pairing deposit + install-script generation
echo ""
echo "--- Pairing Deposit + Install Script ---"
PAIR_RESP=$(curl -s --max-time 8 -X POST "${PAIRING}/" \
  -H "Content-Type: application/json" \
  --data-raw '{"connect_url":"http://test-server:8080","client_id":"testclient","password":"testpass","fingerprint":"aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"}' \
  2>/dev/null || echo "")
if echo "$PAIR_RESP" | grep -q "pairing_code"; then
  pass "Pairing deposit returned pairing_code"
  CODE=$(echo "$PAIR_RESP" | grep -o '"pairing_code":"[^"]*"' | cut -d'"' -f4)
  if [[ -n "$CODE" ]]; then
    SCRIPT_TMP=$(mktemp)
    curl -s --max-time 8 "${PAIRING}/${CODE}" -H "User-Agent: curl/linux" > "$SCRIPT_TMP"
    SCRIPT_BYTES=$(wc -c < "$SCRIPT_TMP")
    if [ "$SCRIPT_BYTES" -lt 1000 ]; then
      fail "Install script too small (${SCRIPT_BYTES}B) - render likely failed"
    else
      pass "Install script rendered (${SCRIPT_BYTES}B)"
    fi
    grep -q "test-server" "$SCRIPT_TMP"      && pass "Install script contains pairing connect_url" \
      || fail "Install script missing pairing connect_url (test-server)"
    rm -f "$SCRIPT_TMP"
  fi
else
  fail "Pairing deposit failed. Response head: ${PAIR_RESP:0:200}"
fi

# 5. Generated config sanity
echo ""
echo "--- Generated Config Sanity ---"
RPORTD_CONF="${STACK_BINDMOUNTROOT}/OpenRPort/Server/Config/rportd.conf"
if [ -f "$RPORTD_CONF" ]; then
  grep -q '^url *=' "$RPORTD_CONF"        && pass "rportd.conf has [server] url"        || fail "rportd.conf missing [server] url"
  grep -q '^key_seed *=' "$RPORTD_CONF"   && pass "rportd.conf has key_seed"            || fail "rportd.conf missing key_seed"
  grep -q '^jwt_secret *=' "$RPORTD_CONF" && pass "rportd.conf has [api] jwt_secret"    || fail "rportd.conf missing jwt_secret"
  grep -q '^pairing_url *=' "$RPORTD_CONF" && pass "rportd.conf has pairing_url"        || fail "rportd.conf missing pairing_url"
else
  fail "$RPORTD_CONF not found - run 'make prepare' first"
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
