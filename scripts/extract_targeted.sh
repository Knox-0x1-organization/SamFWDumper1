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
set -e

echo "---------------------------------------"
echo "   Samsung Special Targeted Extractor"
echo "---------------------------------------"

URL="$1"
COMPRESSION_LEVEL="${2:-0}"
SHOW_ALL="${3:-false}"
OUTPUT_NAME="${4:-Apps}"
SEARCH_NAME="${5:-}"

if [[ ! "$OUTPUT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]; then
  echo "[ERROR] Output name must be 1-64 letters, numbers, dots, underscores, or hyphens, and start with a letter or number."
  exit 1
fi

chmod +x tools/android-tools/* tools/erofs-utils/* 2>/dev/null || true

case "$COMPRESSION_LEVEL" in
  0) XZ_FLAGS="-0" ;;
  3) XZ_FLAGS="-3" ;;
  6) XZ_FLAGS="-6" ;;
  9) XZ_FLAGS="-9" ;;
  *) XZ_FLAGS="-0" ;;
esac

APP_FOLDERS=$(cat targets/system/app.txt 2>/dev/null | tr '\n' ' ')
PRIVAPP_FOLDERS=$(cat targets/system/priv-app.txt 2>/dev/null | tr '\n' ' ')
ETC_ITEMS=$(cat targets/system/etc.txt 2>/dev/null | tr '\n' ' ')
MEDIA_FILES=$(cat targets/system/media.txt 2>/dev/null | tr '\n' ' ')
LIB_FILES=$(cat targets/system/lib.txt 2>/dev/null | tr '\n' ' ')
LIB64_FILES=$(cat targets/system/lib64.txt 2>/dev/null | tr '\n' ' ')
FRAMEWORK_JARS=$(cat targets/system/framework.txt 2>/dev/null | tr '\n' ' ')
CAMERADATA_ITEMS=$(cat targets/system/cameradata.txt 2>/dev/null | tr '\n' ' ')

validate_search_name() {
  [ -z "$SEARCH_NAME" ] && return 0
  if [[ ! "$SEARCH_NAME" =~ ^[A-Za-z0-9_+.-]{1,128}$ || "$SEARCH_NAME" == "." || "$SEARCH_NAME" == ".." ]]; then
    echo "[ERROR] Enter one exact file or directory name (up to 128 letters, numbers, dots, underscores, plus signs, or hyphens)."
    return 1
  fi
  # Name search replaces the configured category list for this run.
  APP_FOLDERS=""; PRIVAPP_FOLDERS=""; ETC_ITEMS=""; MEDIA_FILES=""
  LIB_FILES=""; LIB64_FILES=""; FRAMEWORK_JARS=""; CAMERADATA_ITEMS=""
}

validate_search_name

if [ "${SAMFWDUMPER_VALIDATE_TARGETS_ONLY:-false}" = "true" ]; then
  printf 'search_name=%s\n' "$SEARCH_NAME"
  exit 0
fi

detect_fs_type() {
  local IMG="$1"
  local FS_TYPE=""
  FS_TYPE=$(blkid -o value -s TYPE "$IMG" 2>/dev/null)
  if [ -z "$FS_TYPE" ]; then
    local FILE_OUTPUT=$(file "$IMG" 2>/dev/null)
    if echo "$FILE_OUTPUT" | grep -qi "f2fs"; then
      FS_TYPE="f2fs"
    elif echo "$FILE_OUTPUT" | grep -qi "erofs"; then
      FS_TYPE="erofs"
    elif echo "$FILE_OUTPUT" | grep -qi "ext4\|ext3\|ext2"; then
      FS_TYPE="ext4"
    elif echo "$FILE_OUTPUT" | grep -qi "android sparse"; then
      FS_TYPE="sparse"
    fi
  fi
  if [ -z "$FS_TYPE" ]; then
    local MAGIC=$(xxd -l 4 -p "$IMG" 2>/dev/null)
    case "$MAGIC" in
      1020f5f2) FS_TYPE="f2fs" ;;
      e2e1f5e0) FS_TYPE="erofs" ;;
      53ef*)    FS_TYPE="ext4" ;;
      3aff*)    FS_TYPE="sparse" ;;
    esac
  fi
  echo "$FS_TYPE"
}

extract_f2fs_mount() {
  local IMG="$1" OUT_DIR="$2"
  sudo modprobe f2fs 2>/dev/null || true
  local MNT="/tmp/f2fs_mount_$$"
  mkdir -p "$MNT"
  if ! sudo mount -t f2fs -o ro,loop "$IMG" "$MNT" 2>/dev/null; then
    echo "  [ERROR] f2fs mount failed"
    rm -rf "$MNT"
    return 1
  fi
  echo "  [OK] Mounted f2fs successfully"

  for FOLDER in $APP_FOLDERS; do
    FOUND=false
    for SRC_PATH in "$MNT/app/$FOLDER" "$MNT/system/app/$FOLDER"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/app/$(dirname "$FOLDER")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/app/$FOLDER" 2>/dev/null
        sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR/app/$FOLDER"
        FOUND=true; break
      fi
    done
    $FOUND || echo "  [WARN] app/$FOLDER not found"
  done

  for FOLDER in $PRIVAPP_FOLDERS; do
    FOUND=false
    for SRC_PATH in "$MNT/priv-app/$FOLDER" "$MNT/system/priv-app/$FOLDER"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/priv-app/$(dirname "$FOLDER")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/priv-app/$FOLDER" 2>/dev/null
        sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR/priv-app/$FOLDER"
        FOUND=true; break
      fi
    done
    if ! $FOUND; then
      for ALT in "PhotoEditor_AIFull" "PhotoEditor_Full" "PhotoEditor"; do
        [ "$ALT" = "$FOLDER" ] && continue
        for SRC_PATH in "$MNT/priv-app/$ALT" "$MNT/system/priv-app/$ALT"; do
          if sudo test -e "$SRC_PATH" 2>/dev/null; then
            mkdir -p "$OUT_DIR/priv-app/$(dirname "$FOLDER")"
            sudo cp -r "$SRC_PATH" "$OUT_DIR/priv-app/$FOLDER" 2>/dev/null
            sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR/priv-app/$FOLDER"
            FOUND=true; break 2
          fi
        done
      done
    fi
    $FOUND || echo "  [WARN] priv-app/$FOLDER not found"
  done

  for ITEM in $ETC_ITEMS; do
    FOUND=false
    for SRC_PATH in "$MNT/etc/$ITEM" "$MNT/system/etc/$ITEM"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/etc/$(dirname "$ITEM")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/etc/$ITEM" 2>/dev/null
        sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR/etc/$ITEM"
        FOUND=true; break
      fi
    done
    $FOUND || echo "  [WARN] etc/$ITEM not found"
  done

  for ITEM in $CAMERADATA_ITEMS; do
    FOUND=false
    for SRC_PATH in "$MNT/cameradata/$ITEM" "$MNT/system/cameradata/$ITEM"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/cameradata/$(dirname "$ITEM")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/cameradata/$ITEM" 2>/dev/null
        sudo chown -R "$(id -u):$(id -g)" "$OUT_DIR/cameradata/$ITEM"
        FOUND=true; break
      fi
    done
    $FOUND || echo "  [WARN] cameradata/$ITEM not found"
  done

  for FILE in $MEDIA_FILES; do
    FILE_FOUND=false
    for SRC_PATH in "$MNT/media/$FILE" "$MNT/system/media/$FILE"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/media/$(dirname "$FILE")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/media/$FILE"
        sudo chown $(id -u):$(id -g) "$OUT_DIR/media/$FILE"
        FILE_FOUND=true; break
      fi
    done
    $FILE_FOUND || echo "  [WARN] media/$FILE not found"
  done

  for FILE in $LIB_FILES; do
    FILE_FOUND=false
    for SRC_PATH in "$MNT/lib/$FILE" "$MNT/system/lib/$FILE"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/lib/$(dirname "$FILE")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/lib/$FILE"
        sudo chown $(id -u):$(id -g) "$OUT_DIR/lib/$FILE"
        FILE_FOUND=true; break
      fi
    done
    $FILE_FOUND || echo "  [WARN] lib/$FILE not found"
  done

  for FILE in $LIB64_FILES; do
    FILE_FOUND=false
    for SRC_PATH in "$MNT/lib64/$FILE" "$MNT/system/lib64/$FILE"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/lib64/$(dirname "$FILE")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/lib64/$FILE"
        sudo chown $(id -u):$(id -g) "$OUT_DIR/lib64/$FILE"
        FILE_FOUND=true; break
      fi
    done
    $FILE_FOUND || echo "  [WARN] lib64/$FILE not found"
  done

  for JAR in $FRAMEWORK_JARS; do
    JAR_FOUND=false
    for SRC_PATH in "$MNT/framework/$JAR" "$MNT/system/framework/$JAR"; do
      if sudo test -e "$SRC_PATH" 2>/dev/null; then
        mkdir -p "$OUT_DIR/framework/$(dirname "$JAR")"
        sudo cp -r "$SRC_PATH" "$OUT_DIR/framework/$JAR"
        sudo chown $(id -u):$(id -g) "$OUT_DIR/framework/$JAR"
        JAR_FOUND=true; break
      fi
    done
    $JAR_FOUND || echo "  [WARN] framework/$JAR not found"
  done

  sudo umount "$MNT"
  rm -rf "$MNT"
  return 0
}

case "$URL" in
  https://*) ;;
  *) echo "[ERROR] Firmware URL must use HTTPS."; exit 1 ;;
esac

echo ""; echo "[1/4] Reading the AP image archive from firmware..."
if ! python3 scripts/stream_ap_archive.py "$URL"; then
  echo "[ERROR] Failed to stream and extract the AP TAR."
  exit 1
fi
echo "[OK] Read the required image entries without storing the full firmware ZIP or AP TAR."
for file in super.img* system.img*; do
  [ -f "$file" ] && echo "  Found: $file"
done

AP_CODE=$(cat ap_code.txt)
CSC_CODE=$(cat csc_code.txt)
echo "Firmware: $AP_CODE | CSC: $CSC_CODE"
echo ""; echo "[2/4] Processing super.img..."
mkdir -p super_dump "output/$OUTPUT_NAME/system"

SUPER_FILE=$(find . -maxdepth 1 -name "super.img*" -o -name "super.img" | head -n 1)
SYSTEM_FS=""

if [ -n "$SUPER_FILE" ]; then
  echo "  Found: $(basename "$SUPER_FILE")"

  if [[ "$SUPER_FILE" == *.lz4 ]]; then
    echo "  Decompressing LZ4..."
    lz4 -d "$SUPER_FILE" "super.img" 2>/dev/null
    SUPER_FILE="super.img"
    echo "  [OK] Decompressed"
  fi

  SUPER_FS=$(detect_fs_type "$SUPER_FILE")
  echo "  Super format: $SUPER_FS"

  if [ "$SUPER_FS" = "sparse" ]; then
    echo "  Converting sparse to raw..."
    simg2img "$SUPER_FILE" "super.raw.img" 2>/dev/null || tools/android-tools/simg2img "$SUPER_FILE" "super.raw.img"
    SUPER_FILE="super.raw.img"
    SUPER_FS=$(detect_fs_type "$SUPER_FILE")
    echo "  [OK] Converted - new format: $SUPER_FS"
  fi

  echo "  Unpacking partitions..."
  SYSTEM_IMG=""
  SYSTEM_FS=""
  for PARTITION in system system_a system_b; do
    if tools/android-tools/lpunpack -p "$PARTITION" "$SUPER_FILE" super_dump >/dev/null 2>&1 \
      && [ -f "super_dump/$PARTITION.img" ]; then
      SYSTEM_IMG="super_dump/$PARTITION.img"
      SYSTEM_FS=$(detect_fs_type "$SYSTEM_IMG")
      break
    fi
  done
  if [ -z "$SYSTEM_IMG" ]; then
    echo "  [ERROR] No system partition found in super.img"
    exit 1
  fi
  find . -maxdepth 1 -type f \( -name 'super.img*' -o -name 'super.raw.img' \) -delete
  echo "  [OK] Removed the unpacked super image to free runner storage"

  echo ""
  echo "  Partitions detected:"
  printf "  %-15s | %-6s | %s\n" "Partition" "Format" "Size"
  PART_SIZE=$(numfmt --to=iec "$(stat -c%s "$SYSTEM_IMG")" 2>/dev/null || echo "?")
  printf "  %-15s | %-6s | %s\n" "$(basename "$SYSTEM_IMG" .img)" "$SYSTEM_FS" "$PART_SIZE"
  echo "  System: $(basename "$SYSTEM_IMG") ($SYSTEM_FS)"

else
  echo "  No super.img found - legacy device"

  SYSTEM_IMG=$(find . -maxdepth 1 -name "system.img.lz4" -o -name "system.img" | head -n 1)
  if [ -n "$SYSTEM_IMG" ]; then
    if [[ "$SYSTEM_IMG" == *.lz4 ]]; then
      lz4 -d "$SYSTEM_IMG" "system_raw.img" 2>/dev/null
      SYSTEM_IMG="system_raw.img"
    fi
    SYSTEM_FS=$(detect_fs_type "$SYSTEM_IMG")
    if [ "$SYSTEM_FS" = "sparse" ]; then
      simg2img "$SYSTEM_IMG" "system_unsparse.img" 2>/dev/null
      SYSTEM_IMG="system_unsparse.img"
      SYSTEM_FS=$(detect_fs_type "$SYSTEM_IMG")
    fi
    echo "  System: $(basename "$SYSTEM_IMG") ($SYSTEM_FS)"
  fi
fi

if [ -z "$SYSTEM_IMG" ] || [ ! -f "$SYSTEM_IMG" ]; then
  echo "[ERROR] system.img not found"
  exit 1
fi
echo "[OK] Done"

echo ""; echo "[5/6] Extracting system.img..."
mkdir -p system_extracted

echo "  System FS: $SYSTEM_FS"

SEARCH_MATCHES_FILE="search_matches.nul"
if [ -n "$SEARCH_NAME" ]; then
  echo "  Searching system image recursively for: $SEARCH_NAME"
  SEARCH_MOUNT="/tmp/system_search_$$"
  mkdir -p "$SEARCH_MOUNT"
  SEARCH_MOUNTED=false
  case "$SYSTEM_FS" in
    f2fs)
      sudo modprobe f2fs 2>/dev/null || true
      if sudo mount -t f2fs -o ro,loop "$SYSTEM_IMG" "$SEARCH_MOUNT" 2>/dev/null; then
        SEARCH_MOUNTED=true
      fi
      ;;
    erofs)
      if tools/erofs-utils/fuse.erofs "$SYSTEM_IMG" "$SEARCH_MOUNT" 2>/dev/null; then
        SEARCH_MOUNTED=true
      fi
      ;;
    ext4|ext3|ext2)
      if command -v fuse2fs >/dev/null 2>&1 && fuse2fs -o ro "$SYSTEM_IMG" "$SEARCH_MOUNT" 2>/dev/null; then
        SEARCH_MOUNTED=true
      fi
      ;;
  esac
  if ! $SEARCH_MOUNTED; then
    echo "[ERROR] Could not mount the $SYSTEM_FS system image for recursive search."
    exit 1
  fi
  : > "$SEARCH_MATCHES_FILE"
  while IFS= read -r -d '' MATCH; do
    RELATIVE_PATH="${MATCH#"$SEARCH_MOUNT"/}"
    mkdir -p "system_extracted/$(dirname "$RELATIVE_PATH")"
    cp -a "$MATCH" "system_extracted/$RELATIVE_PATH"
    printf '%s\0' "$RELATIVE_PATH" >> "$SEARCH_MATCHES_FILE"
    echo "  [FOUND] /$RELATIVE_PATH"
  done < <(find "$SEARCH_MOUNT" -mindepth 1 \( -type f -o -type d \) -name "$SEARCH_NAME" -print0)
  case "$SYSTEM_FS" in
    f2fs) sudo umount "$SEARCH_MOUNT" 2>/dev/null || true ;;
    *) fusermount3 -u "$SEARCH_MOUNT" 2>/dev/null || fusermount -u "$SEARCH_MOUNT" 2>/dev/null || true ;;
  esac
  rmdir "$SEARCH_MOUNT" 2>/dev/null || true
  if [ ! -s "$SEARCH_MATCHES_FILE" ]; then
    echo "[ERROR] No file or directory named '$SEARCH_NAME' was found in system.img."
    mkdir -p "output/$OUTPUT_NAME/system"
    printf 'MISSING name:%s\n' "$SEARCH_NAME" > "output/$OUTPUT_NAME/system/EXTRACTION_REPORT.txt"
    cp "output/$OUTPUT_NAME/system/EXTRACTION_REPORT.txt" output/extraction-report.txt
    exit 1
  fi
elif [ "$SYSTEM_FS" = "f2fs" ]; then
  echo "  Mounting f2fs..."
  extract_f2fs_mount "$SYSTEM_IMG" "system_extracted" || true
elif [ "$SYSTEM_FS" = "erofs" ]; then
  echo "  Extracting requested paths from erofs..."
  EROFS_TARGETS_FILE="system_extracted_targets.txt"
  : > "$EROFS_TARGETS_FILE"
  add_ero_target() {
    printf '/%s\n' "$1" >> "$EROFS_TARGETS_FILE"
    printf '/system/%s\n' "$1" >> "$EROFS_TARGETS_FILE"
  }
  add_ero_category() {
    local category="$1" targets="$2" target
    for target in $targets; do
      add_ero_target "$category/$target"
    done
  }
  add_ero_category app "$APP_FOLDERS"
  add_ero_category priv-app "$PRIVAPP_FOLDERS"
  add_ero_category etc "$ETC_ITEMS"
  add_ero_category cameradata "$CAMERADATA_ITEMS"
  add_ero_category media "$MEDIA_FILES"
  add_ero_category lib "$LIB_FILES"
  add_ero_category lib64 "$LIB64_FILES"
  add_ero_category framework "$FRAMEWORK_JARS"
  if [ "$SHOW_ALL" = "true" ]; then
    printf '/app\n/system/app\n/priv-app\n/system/priv-app\n' >> "$EROFS_TARGETS_FILE"
  fi
  sort -u -o "$EROFS_TARGETS_FILE" "$EROFS_TARGETS_FILE"
  mkdir -p system_extracted
  if tools/erofs-utils/extract.erofs -i "$SYSTEM_IMG" -X / -c "$EROFS_TARGETS_FILE" -r -s -o system_extracted >/dev/null 2>&1; then
    echo "  [OK] Extracted requested paths"
  else
    echo "  [WARN] One or more requested paths could not be extracted; checking the target list"
  fi
else
  echo "  Extracting ext4 via debugfs..."

  for FOLDER in $APP_FOLDERS; do
    for TARGET in "app/$FOLDER" "system/app/$FOLDER"; do
      if debugfs -R "ls $TARGET" "$SYSTEM_IMG" 2>/dev/null | grep -q .; then
        mkdir -p "system_extracted/app/$FOLDER"
        debugfs -R "rdump $TARGET system_extracted/app/$FOLDER" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
  done

  for FOLDER in $PRIVAPP_FOLDERS; do
    for TARGET in "priv-app/$FOLDER" "system/priv-app/$FOLDER"; do
      if debugfs -R "ls $TARGET" "$SYSTEM_IMG" 2>/dev/null | grep -q .; then
        mkdir -p "system_extracted/priv-app/$FOLDER"
        debugfs -R "rdump $TARGET system_extracted/priv-app/$FOLDER" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
    if [ ! -d "system_extracted/priv-app/$FOLDER" ]; then
      for ALT in "PhotoEditor_AIFull" "PhotoEditor_Full" "PhotoEditor"; do
        [ "$ALT" = "$FOLDER" ] && continue
        for TARGET in "priv-app/$ALT" "system/priv-app/$ALT"; do
          if debugfs -R "ls $TARGET" "$SYSTEM_IMG" 2>/dev/null | grep -q .; then
            mkdir -p "system_extracted/priv-app/$FOLDER"
            debugfs -R "rdump $TARGET system_extracted/priv-app/$FOLDER" "$SYSTEM_IMG" 2>/dev/null
            break 2
          fi
        done
      done
    fi
  done

  for ITEM in $ETC_ITEMS; do
    for TARGET in "etc/$ITEM" "system/etc/$ITEM"; do
      if debugfs -R "ls $TARGET" "$SYSTEM_IMG" 2>/dev/null | grep -q .; then
        mkdir -p "system_extracted/etc"
        debugfs -R "rdump $TARGET system_extracted/etc/$ITEM" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
  done

  for ITEM in $CAMERADATA_ITEMS; do
    for TARGET in "cameradata/$ITEM" "system/cameradata/$ITEM"; do
      if debugfs -R "ls $TARGET" "$SYSTEM_IMG" 2>/dev/null | grep -q .; then
        mkdir -p "system_extracted/cameradata"
        debugfs -R "rdump $TARGET system_extracted/cameradata/$ITEM" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
  done

  for FILE in $MEDIA_FILES; do
    for SRC in "media/$FILE" "system/media/$FILE"; do
      if debugfs -R "stat $SRC" "$SYSTEM_IMG" 2>/dev/null | grep -q "Type: regular"; then
        mkdir -p "system_extracted/media"
        debugfs -R "dump $SRC system_extracted/media/$FILE" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
  done

  for FILE in $LIB_FILES; do
    for SRC in "lib/$FILE" "system/lib/$FILE"; do
      if debugfs -R "stat $SRC" "$SYSTEM_IMG" 2>/dev/null | grep -q "Type: regular"; then
        mkdir -p "system_extracted/lib"
        debugfs -R "dump $SRC system_extracted/lib/$FILE" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
  done

  for FILE in $LIB64_FILES; do
    for SRC in "lib64/$FILE" "system/lib64/$FILE"; do
      if debugfs -R "stat $SRC" "$SYSTEM_IMG" 2>/dev/null | grep -q "Type: regular"; then
        mkdir -p "system_extracted/lib64"
        debugfs -R "dump $SRC system_extracted/lib64/$FILE" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
  done

  for JAR in $FRAMEWORK_JARS; do
    for SRC in "framework/$JAR" "system/framework/$JAR"; do
      if debugfs -R "stat $SRC" "$SYSTEM_IMG" 2>/dev/null | grep -q "Type: regular"; then
        mkdir -p "system_extracted/framework"
        debugfs -R "dump $SRC system_extracted/framework/$JAR" "$SYSTEM_IMG" 2>/dev/null
        break
      fi
    done
  done
fi

echo ""; echo "[6/6] Copying targets..."

get_size() {
  local BYTES
  if [ -f "$1" ]; then
    BYTES=$(stat -c%s "$1" 2>/dev/null)
  elif [ -d "$1" ]; then
    BYTES=$(du -sb "$1" 2>/dev/null | cut -f1)
  else
    echo "?"
    return
  fi
  if [ -z "$BYTES" ]; then echo "?"; return; fi
  if [ "$BYTES" -ge 1048576 ]; then
    echo "$(( (BYTES + 524288) / 1048576 ))M"
  else
    echo "$(( (BYTES + 512) / 1024 ))K"
  fi
}

is_target() {
  local item="$1" list="$2"
  for i in $list; do
    [ "$i" = "$item" ] && return 0
  done
  return 1
}

SYS_OUT="output/$OUTPUT_NAME/system"
HAS_ANY=false
MISSING_COUNT=0
EXTRACTED_COUNT=0
REPORT_FILE="$SYS_OUT/EXTRACTION_REPORT.txt"
mkdir -p "$SYS_OUT"
: > "$REPORT_FILE"

record_missing() {
  local label="$1"
  echo "    [ERROR] $label not found"
  printf 'MISSING %s\n' "$label" >> "$REPORT_FILE"
  MISSING_COUNT=$((MISSING_COUNT + 1))
}

copy_item() {
  local SRC="$1" DST_DIR="$2" DST_NAME="$3" LABEL="$4"
  if [ -e "$SRC" ]; then
    mkdir -p "$DST_DIR/$(dirname "$DST_NAME")"
    cp -r "$SRC" "$DST_DIR/$DST_NAME"
    echo "    [OK] $LABEL"
    printf 'EXTRACTED %s\n' "$LABEL" >> "$REPORT_FILE"
    EXTRACTED_COUNT=$((EXTRACTED_COUNT + 1))
    return 0
  fi
  return 1
}

if [ -n "$SEARCH_NAME" ]; then
  while IFS= read -r -d '' RELATIVE_PATH; do
    if copy_item "system_extracted/$RELATIVE_PATH" "$SYS_OUT" "$RELATIVE_PATH" "/$RELATIVE_PATH"; then
      HAS_ANY=true
    fi
  done < "$SEARCH_MATCHES_FILE"
elif [ -n "$APP_FOLDERS" ]; then
  if [ "$SHOW_ALL" = "true" ]; then
    echo ""
    echo "--- system/app ---"
    APP_FOUND=false
    for BASE in \
      "system_extracted/app" \
      "system_extracted/system/app" \
      "system_extracted/system_a/app" \
      "system_extracted/system/system/app" \
      "system_extracted/system_a/system/app"; do
      if [ -d "$BASE" ]; then
        while IFS= read -r -d '' ITEM; do
          NAME=$(basename "$ITEM")
          RELATIVE="${ITEM#"$BASE"/}"
          RELATIVE="${RELATIVE%/}"
          SIZE=$(get_size "$ITEM")
          if is_target "$RELATIVE" "$APP_FOLDERS" || is_target "$NAME" "$APP_FOLDERS"; then
            printf "    %-40s %8s [selected]\n" "$RELATIVE" "$SIZE"
            mkdir -p "$SYS_OUT/app/$(dirname "$RELATIVE")"
            cp -r "$ITEM" "$SYS_OUT/app/$RELATIVE"
            printf 'EXTRACTED app/%s\n' "$RELATIVE" >> "$REPORT_FILE"
            EXTRACTED_COUNT=$((EXTRACTED_COUNT + 1))
            HAS_ANY=true
          else
            printf "      %-40s %8s\n" "$NAME" "$SIZE"
          fi
        done < <(find "$BASE" -mindepth 1 -type d -print0)
        APP_FOUND=true
        break
      fi
    done
    $APP_FOUND || echo "    (empty)"
  else
    for FOLDER in $APP_FOLDERS; do
      FOUND=false
      for BASE in \
        "system_extracted/app/$FOLDER" \
        "system_extracted/system/app/$FOLDER" \
        "system_extracted/system_a/app/$FOLDER" \
        "system_extracted/system/system/app/$FOLDER" \
        "system_extracted/system_a/system/app/$FOLDER"; do
        if [ -e "$BASE" ]; then
          copy_item "$BASE" "$SYS_OUT/app" "$FOLDER" "app/$FOLDER" && HAS_ANY=true && FOUND=true && break
        fi
      done
      $FOUND || record_missing "app/$FOLDER"
    done
  fi
fi

if [ -n "$PRIVAPP_FOLDERS" ]; then
  if [ "$SHOW_ALL" = "true" ]; then
    echo ""
    echo "--- system/priv-app ---"
    PRIVAPP_FOUND=false
    for BASE in \
      "system_extracted/priv-app" \
      "system_extracted/system/priv-app" \
      "system_extracted/system_a/priv-app" \
      "system_extracted/system/system/priv-app" \
      "system_extracted/system_a/system/priv-app"; do
      if [ -d "$BASE" ]; then
        while IFS= read -r -d '' ITEM; do
          NAME=$(basename "$ITEM")
          RELATIVE="${ITEM#"$BASE"/}"
          RELATIVE="${RELATIVE%/}"
          SIZE=$(get_size "$ITEM")
          if is_target "$RELATIVE" "$PRIVAPP_FOLDERS" || is_target "$NAME" "$PRIVAPP_FOLDERS"; then
            printf "    %-40s %8s [selected]\n" "$RELATIVE" "$SIZE"
            mkdir -p "$SYS_OUT/priv-app/$(dirname "$RELATIVE")"
            cp -r "$ITEM" "$SYS_OUT/priv-app/$RELATIVE"
            printf 'EXTRACTED priv-app/%s\n' "$RELATIVE" >> "$REPORT_FILE"
            EXTRACTED_COUNT=$((EXTRACTED_COUNT + 1))
            HAS_ANY=true
          else
            printf "      %-40s %8s\n" "$NAME" "$SIZE"
          fi
        done < <(find "$BASE" -mindepth 1 -type d -print0)
        PRIVAPP_FOUND=true
        break
      fi
    done
    $PRIVAPP_FOUND || echo "    (empty)"
  else
    for FOLDER in $PRIVAPP_FOLDERS; do
      FOUND=false
      for BASE in \
        "system_extracted/priv-app/$FOLDER" \
        "system_extracted/system/priv-app/$FOLDER" \
        "system_extracted/system_a/priv-app/$FOLDER" \
        "system_extracted/system/system/priv-app/$FOLDER" \
        "system_extracted/system_a/system/priv-app/$FOLDER"; do
        if [ -e "$BASE" ]; then
          copy_item "$BASE" "$SYS_OUT/priv-app" "$FOLDER" "priv-app/$FOLDER" && HAS_ANY=true && FOUND=true && break
        fi
      done
      if ! $FOUND; then
        for ALT in "PhotoEditor_AIFull" "PhotoEditor_Full" "PhotoEditor"; do
          [ "$ALT" = "$FOLDER" ] && continue
          for BASE in \
            "system_extracted/priv-app/$ALT" \
            "system_extracted/system/priv-app/$ALT" \
            "system_extracted/system_a/priv-app/$ALT" \
            "system_extracted/system/system/priv-app/$ALT" \
            "system_extracted/system_a/system/priv-app/$ALT"; do
            if [ -e "$BASE" ]; then
              copy_item "$BASE" "$SYS_OUT/priv-app" "$FOLDER" "priv-app/$FOLDER (found as $ALT)" && HAS_ANY=true && FOUND=true && break 2
            fi
          done
        done
      fi
      $FOUND || record_missing "priv-app/$FOLDER"
    done
  fi
fi

if [ -n "$ETC_ITEMS" ]; then
  for ITEM in $ETC_ITEMS; do
    FOUND=false
    for BASE in \
      "system_extracted/etc/$ITEM" \
      "system_extracted/system/etc/$ITEM" \
      "system_extracted/system_a/etc/$ITEM" \
      "system_extracted/system/system/etc/$ITEM" \
      "system_extracted/system_a/system/etc/$ITEM"; do
      if [ -e "$BASE" ]; then
        copy_item "$BASE" "$SYS_OUT/etc" "$ITEM" "etc/$ITEM" && HAS_ANY=true && FOUND=true && break
      fi
    done
    $FOUND || record_missing "etc/$ITEM"
  done
fi

if [ -n "$CAMERADATA_ITEMS" ]; then
  for ITEM in $CAMERADATA_ITEMS; do
    FOUND=false
    for BASE in \
      "system_extracted/cameradata/$ITEM" \
      "system_extracted/system/cameradata/$ITEM" \
      "system_extracted/system_a/cameradata/$ITEM" \
      "system_extracted/system/system/cameradata/$ITEM" \
      "system_extracted/system_a/system/cameradata/$ITEM"; do
      if [ -e "$BASE" ]; then
        copy_item "$BASE" "$SYS_OUT/cameradata" "$ITEM" "cameradata/$ITEM" && HAS_ANY=true && FOUND=true && break
      fi
    done
    $FOUND || record_missing "cameradata/$ITEM"
  done
fi

if [ -n "$MEDIA_FILES" ]; then
  for FILE in $MEDIA_FILES; do
    FOUND=false
    for BASE in \
      "system_extracted/media/$FILE" \
      "system_extracted/system/media/$FILE" \
      "system_extracted/system_a/media/$FILE" \
      "system_extracted/system/system/media/$FILE" \
      "system_extracted/system_a/system/media/$FILE"; do
      if [ -e "$BASE" ]; then
        copy_item "$BASE" "$SYS_OUT/media" "$FILE" "media/$FILE" && HAS_ANY=true && FOUND=true && break
      fi
    done
    $FOUND || record_missing "media/$FILE"
  done
fi

if [ -n "$LIB_FILES" ]; then
  for FILE in $LIB_FILES; do
    FOUND=false
    for BASE in \
      "system_extracted/lib/$FILE" \
      "system_extracted/system/lib/$FILE" \
      "system_extracted/system_a/lib/$FILE" \
      "system_extracted/system/system/lib/$FILE" \
      "system_extracted/system_a/system/lib/$FILE"; do
      if [ -e "$BASE" ]; then
        copy_item "$BASE" "$SYS_OUT/lib" "$FILE" "lib/$FILE" && HAS_ANY=true && FOUND=true && break
      fi
    done
    $FOUND || record_missing "lib/$FILE"
  done
fi

if [ -n "$LIB64_FILES" ]; then
  for FILE in $LIB64_FILES; do
    FOUND=false
    for BASE in \
      "system_extracted/lib64/$FILE" \
      "system_extracted/system/lib64/$FILE" \
      "system_extracted/system_a/lib64/$FILE" \
      "system_extracted/system/system/lib64/$FILE" \
      "system_extracted/system_a/system/lib64/$FILE"; do
      if [ -e "$BASE" ]; then
        copy_item "$BASE" "$SYS_OUT/lib64" "$FILE" "lib64/$FILE" && HAS_ANY=true && FOUND=true && break
      fi
    done
    $FOUND || record_missing "lib64/$FILE"
  done
fi

if [ -n "$FRAMEWORK_JARS" ]; then
  for JAR in $FRAMEWORK_JARS; do
    FOUND=false
    for BASE in \
      "system_extracted/framework/$JAR" \
      "system_extracted/system/framework/$JAR" \
      "system_extracted/system_a/framework/$JAR" \
      "system_extracted/system/system/framework/$JAR" \
      "system_extracted/system_a/system/framework/$JAR"; do
      if [ -e "$BASE" ]; then
        copy_item "$BASE" "$SYS_OUT/framework" "$JAR" "framework/$JAR" && HAS_ANY=true && FOUND=true && break
      fi
    done
    $FOUND || record_missing "framework/$JAR"
  done
fi

if [ "$SHOW_ALL" = "true" ]; then
  for category in app priv-app etc cameradata media lib lib64 framework; do
    case "$category" in
      app) targets="$APP_FOLDERS" ;;
      priv-app) targets="$PRIVAPP_FOLDERS" ;;
      etc) targets="$ETC_ITEMS" ;;
      cameradata) targets="$CAMERADATA_ITEMS" ;;
      media) targets="$MEDIA_FILES" ;;
      lib) targets="$LIB_FILES" ;;
      lib64) targets="$LIB64_FILES" ;;
      framework) targets="$FRAMEWORK_JARS" ;;
    esac
    for target in $targets; do
      if [ ! -e "$SYS_OUT/$category/$target" ]; then
        record_missing "$category/$target"
      fi
    done
  done
fi

cp "$REPORT_FILE" output/extraction-report.txt
rm -rf system_extracted super_dump *.img system_extracted_targets.txt

if ! $HAS_ANY; then
  echo ""
  echo "[ERROR] Nothing extracted!"
  exit 1
fi

echo ""; echo "Packaging..."
cd output
PKG_NAME="${OUTPUT_NAME}.zip"
if [ "$COMPRESSION_LEVEL" != "0" ]; then
  tar -cf - "$OUTPUT_NAME" | xz $XZ_FLAGS -T0 2>/dev/null > "${OUTPUT_NAME}.tar.xz"
  rm -rf "$OUTPUT_NAME"
  echo "    [OK] ${OUTPUT_NAME}.tar.xz"
else
  zip -r "$PKG_NAME" "$OUTPUT_NAME" >/dev/null 2>&1
  rm -rf "$OUTPUT_NAME"
  echo "    [OK] $PKG_NAME"
fi

echo ""; echo "---------------------------------------"
FILE_COUNT=$(ls -1 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh . | cut -f1)
echo "[OK] Extracted $FILE_COUNT items"
echo "Total size: $TOTAL_SIZE"
ls -lh
echo "---------------------------------------"
echo "Requested targets extracted: $EXTRACTED_COUNT"
echo "Requested targets missing: $MISSING_COUNT"
if [ "$MISSING_COUNT" -gt 0 ]; then
  echo "[ERROR] Some requested targets were not found. See $OUTPUT_NAME/system/EXTRACTION_REPORT.txt."
  exit 1
fi
echo "[OK] Done!"
