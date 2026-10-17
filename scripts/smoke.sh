#!/usr/bin/env bash
# The three facts most "it doesn't work" reports come down to: is the key
# valid, what permission does it have, and which site ids exist.
set -euo pipefail

: "${RANKRAFT_API_KEY:?set RANKRAFT_API_KEY (an rr_api_… key from Settings → API)}"
BASE="${RANKRAFT_BASE_URL:-https://api.rankraft.ai/v1}"

case "$RANKRAFT_API_KEY" in
  rr_api_*) ;;
  rr_live_*) echo "that is a SITE key (rr_live_…), for sending traffic. The API wants an rr_api_… key." >&2; exit 2 ;;
  *) echo "API keys start with rr_api_" >&2; exit 2 ;;
esac

req() { curl -sS -w '\n%{http_code}' -H "X-API-Key: $RANKRAFT_API_KEY" -H 'Accept: application/json' "$BASE$1"; }

out=$(req /me); code=${out##*$'\n'}; body=${out%$'\n'*}
if [ "$code" != "200" ]; then
  echo "GET /me → $code"; echo "$body"; exit 1
fi
echo "$body" | python3 -c '
import json,sys; d=json.load(sys.stdin)["data"]
print(f"key        {d[\"key\"][\"name\"]}  permission={d[\"key\"][\"permission\"]}  expires={d[\"key\"][\"expires_at\"][:10]}")
print(f"org        {d[\"organization\"][\"name\"]}  plan={d[\"organization\"][\"plan\"]}")
print(f"limits     {d[\"rate_limits\"][\"requests_per_minute\"]}/min, {d[\"rate_limits\"][\"writes_per_minute\"]} writes/min")'

out=$(req /sites); code=${out##*$'\n'}; body=${out%$'\n'*}
if [ "$code" != "200" ]; then echo "GET /sites → $code"; echo "$body"; exit 1; fi
echo "$body" | python3 -c '
import json,sys
for s in json.load(sys.stdin)["data"]:
    scan = s["last_answer_scan"]
    print(f"site       {s[\"id\"]}  {s[\"domain\"]}  last scan: {scan[\"date\"] + \" \" + scan[\"status\"] if scan else \"none yet\"}")'
