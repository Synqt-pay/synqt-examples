#!/bin/sh
# Mints a SYNQT PAYIN_CREATE token on this Mac and copies it, with the payin details, for the demo page's
# "Paste from script" box. The private key never goes into the browser.
# Usage: SYNQT_MERCHANT=<Merchant ID> SYNQT_KEY=path/to/synqt-private.pem scripts/sandbox-token.sh 100 ZAR
# SYNQT_ENV picks the platform: sandbox (default), stable or live.
set -eu
amount=${1:?amount}
currency=${2:?currency code}
: "${SYNQT_MERCHANT:?set SYNQT_MERCHANT}" "${SYNQT_KEY:?set SYNQT_KEY}"
env=${SYNQT_ENV:-sandbox}
case "$env" in
  sandbox) api=https://api.sandbox.synqt.io ;;
  stable) api=https://api.stable.aopay.io ;;
  live) api=https://api.synqt.io ;;
  *) echo "SYNQT_ENV must be sandbox, stable or live" >&2; exit 1 ;;
esac

id="test-$(date +%s)"
body=$(printf '{"merchantCode":"%s","validitySecs":1800,"action":"PAYIN_CREATE","idPayment":"%s","money":{"amount":%s,"currencyCode":"%s"},"timestamp":%s}' \
  "$SYNQT_MERCHANT" "$id" "$amount" "$currency" "$(date +%s)")
sig=$(printf %s "$body" | openssl dgst -sha256 -sign "$SYNQT_KEY" | base64 | tr -d '\n')

response=$(curl -sS "$api/auth-tokens-by-action" \
  -H 'Content-Type: application/json' -H 'X-API-Version: 2' -H "X-SIGNATURE: $sig" -d "$body")
token=$(printf %s "$response" | sed -nE 's/.*"token":"([^"]+)".*/\1/p')
[ -n "$token" ] || { echo "No token from SYNQT: $response" >&2; exit 1; }

printf '{"environment":"%s","merchantCode":"%s","idPayin":"%s","token":"%s","amount":"%s","currencyCode":"%s"}' \
  "$env" "$SYNQT_MERCHANT" "$id" "$token" "$amount" "$currency" | pbcopy
echo "idPayin=$id copied. Paste it into the demo page's \"Paste from script\" box."
