#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/extract_targeted.sh"
run_parser() {
  SAMFWDUMPER_VALIDATE_TARGETS_ONLY=true bash "$SCRIPT" \
    https://example.invalid/firmware.zip 0 false ParserTest "$1"
}

result=$(run_parser floating_feature)
[[ "$result" == *$'search_name=floating_feature'* ]]
result=$(run_parser framework-res.apk)
[[ "$result" == *$'search_name=framework-res.apk'* ]]

for invalid in \
  '/system/etc/floating_feature' \
  '../floating_feature' \
  'floating feature' \
  '.' \
  '..' \
  'foo/bar'; do
  if run_parser "$invalid" >/dev/null 2>&1; then
    echo "[ERROR] Invalid search name was accepted: $invalid" >&2
    exit 1
  fi
done

printf '%s\n' '[OK] Search name validation checks passed.'
