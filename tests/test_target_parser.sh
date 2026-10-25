#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/extract_targeted.sh"
run_parser() {
  SAMFWDUMPER_VALIDATE_TARGETS_ONLY=true bash "$SCRIPT" \
    https://example.invalid/firmware.zip 0 false ParserTest "$1"
}

result=$(run_parser 'app=Settings,ImsSettings;etc=permissions/example.xml;framework=services.jar,framework-res.apk;lib64=hw/vulkan.samsung.so')
[[ "$result" == *$'app=Settings ImsSettings'* ]]
[[ "$result" == *$'etc=permissions/example.xml'* ]]
[[ "$result" == *$'framework=services.jar framework-res.apk'* ]]
[[ "$result" == *$'lib64=hw/vulkan.samsung.so'* ]]

result=$(run_parser 'app=Settings;app=DeviceCare;etc=')
[[ "$result" == *$'app=DeviceCare'* ]]
[[ "$result" == *$'etc='* ]]

for invalid in \
  'unknown=foo' \
  'app=/system/app/Foo' \
  'app=../private/file' \
  'app=foo/../../private' \
  'app=foo bar' \
  'app=foo;broken'; do
  if run_parser "$invalid" >/dev/null 2>&1; then
    echo "[ERROR] Invalid target input was accepted: $invalid" >&2
    exit 1
  fi
done

printf '%s\n' '[OK] Target parser checks passed.'
