#!/usr/bin/env sh
# End-to-end smoke test: health, create a link, follow it, check the hit count.
set -eu
BASE="${1:-http://localhost:8080}"

echo "1. health:  $(curl -fsS "$BASE/healthz")"
echo "2. ready:   $(curl -fsS "$BASE/readyz")"

CODE=$(curl -fsS -X POST "$BASE/links" -H 'content-type: application/json' \
  -d '{"url":"https://kubernetes.io/docs/home/"}' | sed -E 's/.*"code":"([^"]+)".*/\1/')
echo "3. created: $BASE/$CODE"

STATUS=$(curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}' "$BASE/$CODE")
echo "4. follow:  $STATUS"
case "$STATUS" in 307*kubernetes.io*) ;; *) echo "FAIL: expected a 307 redirect"; exit 1 ;; esac

HITS=$(curl -fsS "$BASE/links/$CODE/stats" | sed -E 's/.*"hits":([0-9]+).*/\1/')
echo "5. hits:    $HITS"
[ "$HITS" = "1" ] || { echo "FAIL: expected 1 hit"; exit 1; }

echo "smoke test passed"
