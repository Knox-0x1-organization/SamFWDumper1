#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MKFS="$ROOT/tools/erofs-utils/mkfs.erofs"
EXTRACT="$ROOT/tools/erofs-utils/extract.erofs"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT

mkdir -p "$TEMP/source/app/Example" "$TEMP/source/etc/permissions" "$TEMP/source/media/unselected"
printf 'apk payload\n' > "$TEMP/source/app/Example/base.apk"
printf 'platform config\n' > "$TEMP/source/etc/permissions/platform.xml"
printf 'not selected\n' > "$TEMP/source/media/unselected/unused.bin"
"$MKFS" "$TEMP/system.img" "$TEMP/source" >/dev/null 2>&1
printf '/app/Example\n/etc/permissions/platform.xml\n' > "$TEMP/targets.txt"
"$EXTRACT" -i "$TEMP/system.img" -X / -c "$TEMP/targets.txt" -r -s -T1 -o "$TEMP/output" >/dev/null 2>&1

[[ -f "$TEMP/output/system/app/Example/base.apk" ]]
[[ -f "$TEMP/output/system/etc/permissions/platform.xml" ]]
[[ ! -e "$TEMP/output/system/media/unselected/unused.bin" ]]
printf '%s\n' '[OK] EROFS targeted extraction checks passed.'
