#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
# PI_HOST and PI_USER come from ~/.config/shell/personal.zsh (via chezmoi).
# OCTOPRINT_KEY is fetched from Bitwarden at flash time (item "OctoPrint",
# field "API Key"). Requires an active BW_SESSION:
#   export BW_SESSION=$(bw unlock --raw)
PI_HOST="${PI_HOST:-octopi.local}"
PI_USER="${PI_USER:-pi}"
OCTOPRINT_KEY="${OCTOPRINT_KEY:-}"
# ───────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.pio/build/BTT_SKR_SE_BX_BOOT"
FIRMWARE="$BUILD_DIR/firmware.bin"
DFU_ADDRESS="0x08020000"
STM32_ID="0483:df11"
LOCAL_MODE=false

[[ "${1:-}" == "--local" ]] && LOCAL_MODE=true

echo "==> Compiling firmware..."
cd "$SCRIPT_DIR"
pio run -e BTT_SKR_SE_BX_BOOT

HASH=$(shasum -a 256 "$FIRMWARE" | awk '{print $1}')
echo "==> Built: $HASH"

if $LOCAL_MODE; then
  # ── Local DFU mode ─────────────────────────────────────────────────────────
  # Use this once to bootstrap M997 support onto the printer, then switch to
  # the default Pi mode for all future flashes.
  if ! dfu-util -l 2>/dev/null | grep -q "$STM32_ID"; then
    echo ""
    echo "==> Enter DFU mode:"
    echo "    1. Disconnect the Pi's USB cable from the printer"
    echo "    2. Connect a micro USB cable from the printer to your Mac"
    echo "    3. Short the P39 (BOOT0) header pins on the mainboard"
    echo "    4. Press the red RESET button (K1) and release"
    echo "    5. Remove the P39 short"
    echo ""
    echo "    Waiting for DFU device (Ctrl-C to cancel)..."
    while ! dfu-util -l 2>/dev/null | grep -q "$STM32_ID"; do
      sleep 1
    done
  fi

  echo "==> DFU device found. Flashing..."
  dfu-util -a 0 -s "${DFU_ADDRESS}:leave" -D "$FIRMWARE"

  echo ""
  echo "==> Flash complete."
  echo "    Reconnect the Pi's USB cable. Remove P39 short if still in place."
  echo "    Restore EEPROM if needed: M851 X-30.10 Y26.78 Z-1.90 / M914 X109 Y92 / M500"
  echo ""
  echo "    Future flashes: ./flash.sh (no --local needed)"

else
  # ── Pi-based DFU mode (default) ────────────────────────────────────────────
  # Sends M997 via OctoPrint API, which triggers the firmware to jump to DFU.
  # The Pi then runs dfu-util over its existing USB connection to the printer.
  if [[ -z "$OCTOPRINT_KEY" ]]; then
    if [[ -z "${BW_SESSION:-}" ]]; then
      echo "ERROR: OCTOPRINT_KEY not set and Bitwarden is locked."
      echo "  Unlock with: export BW_SESSION=\$(bw unlock --raw)"
      echo "  Or for a one-time flash without Bitwarden: ./flash.sh --local"
      exit 1
    fi
    OCTOPRINT_KEY=$(bw get item "OctoPrint" 2>/dev/null \
      | jq -r '(.fields // [])[] | select(.name == "API Key") | .value // empty' 2>/dev/null || true)
    if [[ -z "$OCTOPRINT_KEY" ]]; then
      echo "ERROR: Could not fetch 'API Key' from Bitwarden item 'OctoPrint'."
      echo "  Verify the item name and field name in Bitwarden, then retry."
      exit 1
    fi
    echo "==> (API key fetched from Bitwarden)"
  fi

  echo "==> Uploading firmware to $PI_USER@$PI_HOST..."
  scp "$FIRMWARE" "$PI_USER@$PI_HOST:/tmp/firmware.bin"

  echo "==> Sending M997 to trigger DFU mode..."
  ssh "$PI_USER@$PI_HOST" "curl -s -X POST http://localhost/api/printer/command \
    -H 'Content-Type: application/json' \
    -H 'X-Api-Key: $OCTOPRINT_KEY' \
    -d '{\"command\":\"M997\"}' || true"

  echo "    Waiting for DFU device on Pi (up to 20s)..."
  if ! ssh "$PI_USER@$PI_HOST" "
    for i in \$(seq 20); do
      if dfu-util -l 2>/dev/null | grep -q '$STM32_ID'; then exit 0; fi
      sleep 1
    done
    exit 1
  "; then
    echo "ERROR: DFU device did not appear on Pi within 20 seconds."
    echo "  If the printer hasn't been flashed with M997 support yet: ./flash.sh --local"
    exit 1
  fi

  echo "==> DFU device found. Flashing via Pi..."
  ssh "$PI_USER@$PI_HOST" "dfu-util -a 0 -s '${DFU_ADDRESS}:leave' -D /tmp/firmware.bin && rm -f /tmp/firmware.bin"

  echo ""
  echo "==> Flash complete. OctoPrint will reconnect automatically."
  echo "    Restore EEPROM if needed: M851 X-30.10 Y26.78 Z-1.90 / M914 X109 Y92 / M500"
fi
