#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.pio/build/BTT_SKR_SE_BX_BOOT"
FIRMWARE="$BUILD_DIR/firmware.bin"
DEST_DIR="${1:-/Volumes/BIQU_BX}"
DEST="$DEST_DIR/firmware.bin"

echo "==> Compiling firmware..."
cd "$SCRIPT_DIR"
pio run -e BTT_SKR_SE_BX_BOOT

echo "==> Copying firmware to $DEST..."
cp "$FIRMWARE" "$DEST"

echo "==> Verifying hashes..."
SRC_HASH=$(shasum -a 256 "$FIRMWARE" | awk '{print $1}')
DST_HASH=$(shasum -a 256 "$DEST" | awk '{print $1}')

if [ "$SRC_HASH" != "$DST_HASH" ]; then
    echo "ERROR: Hash mismatch!"
    echo "  Source: $SRC_HASH"
    echo "  Dest:   $DST_HASH"
    exit 1
fi

echo "  Hash verified: $SRC_HASH"

echo "==> Ejecting $DEST_DIR..."
diskutil eject "$DEST_DIR"

echo "==> Done. Safe to remove the SD card and flash."
