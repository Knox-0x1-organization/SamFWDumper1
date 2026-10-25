#!/bin/bash
# =============================================================================
# SamFWDumper - Automated Samsung Firmware Extraction
# Copyright (C) 2026 Xiatsuma
# Licensed under PolyForm Noncommercial License 1.0.0
# https://polyformproject.org/licenses/noncommercial/1.0.0
#
# You may NOT use this file except in compliance with the License.
# Commercial use, removal of this header, or distribution without attribution
# is strictly prohibited. For permissions: https://github.com/Xiatsuma
# =============================================================================
set -euo pipefail

FILE="${1:-}"
rm -f download_url.txt
if [ ! -f "$FILE" ]; then
  echo "[ERROR] File not found: $FILE"
  exit 1
fi

echo "Uploading to GoFile..."

TOKEN_RESPONSE=$(curl --fail --silent --show-error --retry 3 --retry-all-errors -X POST https://api.gofile.io/accounts)
TOKEN=$(echo "$TOKEN_RESPONSE" | jq -er '.data.token // empty' 2>/dev/null || true)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "[ERROR] Failed to get GoFile token"
  exit 1
fi

SERVER_RESPONSE=$(curl --fail --silent --show-error --retry 3 --retry-all-errors "https://api.gofile.io/servers?token=$TOKEN")
SERVER=$(echo "$SERVER_RESPONSE" | jq -er '.data.servers[0].name // empty' 2>/dev/null || true)
[ -z "$SERVER" ] && { echo "[ERROR] GoFile did not return an upload server"; exit 1; }

RESPONSE=$(curl --fail --silent --show-error --retry 3 --retry-all-errors -X POST \
  -F "file=@$FILE" \
  -F "token=$TOKEN" \
  "https://${SERVER}.gofile.io/uploadFile")

if DOWNLOAD_URL=$(echo "$RESPONSE" | jq -er 'select(.status == "ok") | .data.downloadPage | select(type == "string" and length > 0)' 2>/dev/null); then
  echo "[OK] Upload successful!"
  echo "$DOWNLOAD_URL"
  echo "$DOWNLOAD_URL" > download_url.txt
  exit 0
else
  echo "[ERROR] Upload failed"
  echo "Response: $RESPONSE"
  exit 1
fi
