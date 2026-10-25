#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/bin" "$TEMP/output/Bundle"
printf 'small file\n' > "$TEMP/output/small.zip"
printf 'bundle member\n' > "$TEMP/output/Bundle/member.txt"
truncate -s 2147483649 "$TEMP/output/large.img"
cat > "$TEMP/bin/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_CAPTURE"
while (($#)); do
  if [[ "$1" == --notes-file ]]; then
    cp "$2" "$GH_NOTES_CAPTURE"
    shift 2
  else
    shift
  fi
done
MOCK
cat > "$TEMP/upload_gofile.sh" <<'MOCK'
#!/usr/bin/env bash
if [[ "${GOFILE_FAIL:-false}" == true ]]; then exit 1; fi
printf 'https://gofile.io/d/test-link\n' > download_url.txt
MOCK
chmod +x "$TEMP/bin/gh" "$TEMP/upload_gofile.sh"
export PATH="$TEMP/bin:$PATH"
export GOFILE_UPLOADER="$TEMP/upload_gofile.sh"
export GH_CAPTURE="$TEMP/gh-args.txt"
export GH_NOTES_CAPTURE="$TEMP/release-notes.txt"

(
  cd "$TEMP"
  bash "$ROOT/scripts/upload_outputs.sh" 'github releases' test-release 'Test release' "$TEMP/output"
)
[[ -s "$GH_CAPTURE" ]]
grep -q 'small.zip' "$GH_CAPTURE"
grep -q 'Bundle.tar.gz' "$GH_CAPTURE"
grep -q 'large.img' "$GH_NOTES_CAPTURE"
grep -q 'https://gofile.io/d/test-link' "$GH_NOTES_CAPTURE"
grep -q 'links.txt' "$GH_CAPTURE"
[[ ! -e "$TEMP/output/links.txt" ]]

if (
  cd "$TEMP"
  GOFILE_FAIL=true bash "$ROOT/scripts/upload_outputs.sh" 'github releases' failed-release 'Failure test' "$TEMP/output"
) >/dev/null 2>&1; then
  echo '[ERROR] Release upload succeeded after an external upload failure.' >&2
  exit 1
fi

printf '%s\n' '[OK] Output upload checks passed.'
