#!/usr/bin/env bash
set -euo pipefail

DESTINATION="${1:-}"
RELEASE_TAG="${2:-}"
RELEASE_TITLE="${3:-Firmware files}"
OUTPUT_DIR="${4:-output}"
GOFILE_UPLOADER="${GOFILE_UPLOADER:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/upload_gofile.sh}"
SIZE_LIMIT=2147483648

if [[ -z "$RELEASE_TAG" ]]; then
  echo "[ERROR] A release tag is required."
  exit 2
fi
if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "[ERROR] Output directory not found: $OUTPUT_DIR"
  exit 1
fi
shopt -s nullglob dotglob
FILES=("$OUTPUT_DIR"/*)
if ((${#FILES[@]} == 0)); then
  echo "[ERROR] No output files to upload."
  exit 1
fi

NOTES_FILE=$(mktemp)
LINKS_FILE="$(mktemp --suffix=.txt)"
LINKS_ASSET="$OUTPUT_DIR/links.txt"
ASSETS=()
FAILED=0
TEMP_ARCHIVES=()
cleanup() {
  rm -f "$NOTES_FILE" "$LINKS_FILE" "$LINKS_ASSET"
  for temporary_directory in "${TEMP_ARCHIVES[@]}"; do
    rm -rf "$temporary_directory"
  done
}
trap cleanup EXIT
rm -f "$LINKS_ASSET"

upload_external() {
  local source="$1" name="$2" upload_file="$1" temporary=""
  if [[ -d "$source" ]]; then
    temporary=$(mktemp --suffix=.tar.gz)
    tar -czf "$temporary" -C "$(dirname "$source")" "$(basename "$source")"
    upload_file="$temporary"
  fi
  rm -f download_url.txt
  if bash "$GOFILE_UPLOADER" "$upload_file" >/dev/null && [[ -s download_url.txt ]]; then
    local url
    url=$(<download_url.txt)
    if [[ "$url" == https://* ]]; then
      printf '%s: %s\n' "$name" "$url" >> "$NOTES_FILE"
      printf '%s\n' "$url" >> "$LINKS_FILE"
      echo "[OK] Uploaded $name to GoFile: $url"
    else
      echo "[ERROR] GoFile returned an invalid download URL for $name"
      FAILED=1
    fi
  else
    echo "[ERROR] GoFile upload failed for $name"
    FAILED=1
  fi
  [[ -z "$temporary" ]] || rm -f "$temporary"
}

for file in "${FILES[@]}"; do
  name=$(basename "$file")
  [[ "$name" == extraction-report.txt ]] && continue
  if [[ -d "$file" ]]; then
    archive_directory=$(mktemp -d)
    TEMP_ARCHIVES+=("$archive_directory")
    archive="$archive_directory/$name.tar.gz"
    tar -czf "$archive" -C "$(dirname "$file")" "$(basename "$file")"
    file_to_upload="$archive"
    name="$name.tar.gz"
    size=$(stat -c%s -- "$archive")
  else
    archive=""
    file_to_upload="$file"
    size=$(stat -c%s -- "$file")
  fi

  case "$DESTINATION" in
    gofile)
      upload_external "$file_to_upload" "$name"
      ;;
    'github releases')
      if ((size > SIZE_LIMIT)); then
        upload_external "$file_to_upload" "$name"
      else
        ASSETS+=("$file_to_upload")
        printf '%s: attached to GitHub release\n' "$name" >> "$NOTES_FILE"
      fi
      ;;
    *)
      echo "[ERROR] Unknown upload destination: $DESTINATION"
      exit 2
      ;;
  esac
done

if [[ -s "$LINKS_FILE" ]]; then
  cp "$LINKS_FILE" "$LINKS_ASSET"
  ASSETS+=("$LINKS_ASSET")
fi

if ((FAILED != 0)); then
  echo "[ERROR] One or more external uploads failed; no release was created."
  exit 1
fi

if (( ${#ASSETS[@]} > 0 )); then
  gh release create "$RELEASE_TAG" \
    --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE" \
    "${ASSETS[@]}"
else
  gh release create "$RELEASE_TAG" \
    --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE"
fi

echo "[OK] Release upload completed."
