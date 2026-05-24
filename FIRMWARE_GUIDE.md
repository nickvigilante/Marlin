# Biqu BX firmware guide

## Hardware reference (BTT SKR SE BX V2.0)

- **K1** — Red RESET button on the mainboard, left of the USB port (bottom-left area of board)
- **P39** — 2-pin BOOT0 jumper header on the mainboard (NOT a button — must be shorted with a wire or jumper cap)
- **J14** — SWD debug port (4-pin, bottom-right of board)
- **USB port** — Micro USB on the mainboard; also accessible via the front panel of the printer
- **SD card slot** — Mainboard SD card slot, accessible via the front panel to the left of the TFT screen
- **Mainboard access** — Remove the bottom panel of the printer base enclosure

---

## Normal firmware flash (SD card method)

Use this when the printer is functioning normally.

### Steps

1. **Wait for the printer to fully start and for any existing firmware to finish flashing.** This is key to prevent a corrupt bootloader.

2. **Compile or obtain a `firmware.bin`** for the `BTT_SKR_SE_BX_BOOT` PlatformIO environment:

   ```bash
   cd /path/to/Marlin
   pio run -e BTT_SKR_SE_BX_BOOT
   # Output: .pio/build/BTT_SKR_SE_BX_BOOT/firmware.bin
   ```

3. **Remove the SD card from the printer.** It is safe to pull the firmware SD card while the printer is running — Marlin only reads it during the bootloader stage at startup and ignores it afterward. Do not remove it mid-print if you are printing from the SD card directly, but OctoPrint users can remove it freely.

4. **Insert the SD card into your Mac** and copy the firmware:

   ```bash
   cp .pio/build/BTT_SKR_SE_BX_BOOT/firmware.bin /Volumes/BIQU_BX/firmware.bin
   shasum -a 256 /Volumes/BIQU_BX/firmware.bin
   # Compare against: shasum -a 256 .pio/build/BTT_SKR_SE_BX_BOOT/firmware.bin
   diskutil eject /Volumes/BIQU_BX
   ```

   Or use the `flash.sh` script which does all of the above:

   ```bash
   ./flash.sh
   ```

5. **Power the printer off** using the physical power switch. Wait the full ~30 seconds for it to completely shut down before proceeding — the PSU takes time to discharge.

6. **Insert the SD card** into the front panel slot (left of the TFT screen).

7. **Power the printer on** and wait up to 2 minutes. The screen will show `firmware.bin / Program Size: XXX KB / Updating: %` while flashing.

8. The printer will make a series of high-pitched beeps and reboot into Marlin when done. Remove the SD card after reboot (optional but keeps the slot free).

### Known issue: SD card flash hangs at "Updating: %"

If the screen shows `firmware.bin / Program Size: XXX KB / Updating: %` and never progresses, the SD card bootloader has encountered a partially-corrupted flash state (usually from a previous interrupted flash). Proceed to **DFU recovery** below.

---

## DFU recovery (when SD card flash fails)

Use this when the printer screen is black, the SD card method hangs, or OctoPrint cannot connect via USB.

### What you need

- A micro USB cable, with one end being a micro USB plug and the other end being either a USB 2, USB 3, or USB C plug.
- A laptop or other portable computer.
- [`dfu-util`](https://dfu-util.sourceforge.net/) (`brew install dfu-util` on Mac).
- A small jumper cap or an **insulated**, flat-blade screwdriver (to short the P39 header).

### Steps

1. **Power the printer off** and unplug the Pi's USB cable from the printer.

2. **Connect** a micro USB cable from the printer's front USB port directly to your computer.

3. **Locate P39** on the mainboard (visible through the bottom panel of the printer base). It is a small 2-pin header near the bottom-left of the BTT SKR SE BX board, labeled BOOT0.

4. **Short P39** by placing a jumper cap across both pins, or by holding a flat screwdriver blade across them

5. While P39 is shorted, **press the red RESET button (K1)** and release it

6. Verify DFU mode on your computer:

   ```bash
   dfu-util -l
   # Should show: Found DFU: [0483:df11] ... "@Internal Flash /0x08000000/..."
   ```

7. **Flash the firmware** (you can now release the screwdriver/remove the jumper):

   ```bash
   dfu-util -a 0 -s 0x08020000:leave \
     -D ~/git/looxonline/biqubx-firmware/firmware.bin
   ```

   A passing output may look like this:

   ```
   Copyright 2005-2009 Weston Schmidt, Harald Welte and OpenMoko Inc.
   Copyright 2010-2021 Tormod Volden and Stefan Schmidt
   This program is Free Software and has ABSOLUTELY NO WARRANTY
   Please report bugs to http://sourceforge.net/p/dfu-util/tickets/

   dfu-util: Warning: Invalid DFU suffix signature
   dfu-util: A valid DFU suffix will be required in a future dfu-util release
   Opening DFU capable USB device...
   Device ID 0483:df11
   Device DFU version 011a
   Claiming USB DFU Interface...
   Setting Alternate Interface #0 ...
   Determining device status...
   DFU state(2) = dfuIDLE, status(0) = No error condition is present
   DFU mode device DFU version 011a
   Device returned transfer size 1024
   DfuSe interface name: "Internal Flash   "
   Downloading element to address = 0x08020000, size = 479604
   Erase       [=========================] 100%       479604 bytes
   Erase    done.
   Download    [=========================] 100%       479604 bytes
   Download done.
   File downloaded successfully
   Submitting leave request...
   dfu-util: Error during download get_status
   ```

   The printer will make a series of high-pitched beeps and reboot when done. The final `Error during download get_status` message is normal — it means the STM32 reset before dfu-util could check status. "Download done. File downloaded successfully" is the confirmation that matters.

8. **Remove the P39 short** (if using a permanent jumper cap — leave it off so the next power cycle boots normally into Marlin).

9. **Reconnect the Pi's USB cable** to the printer.

### After DFU recovery

DFU flashing bypasses EEPROM — your calibration settings are reset. Re-enter:

```gcode
M851 X-30.10 Y26.78 Z-1.85    ; probe offset (adjust Z as needed for your printer)
M914 X109 Y92                 ; StallGuard sensorless homing thresholds
M500                          ; save to EEPROM
G28                           ; home
G34                           ; dual-Z alignment, the dance of my people
G29                           ; bed mesh
M500                          ; save mesh
M420 S1                       ; enable bed leveling
```

---

## Firmware sources

| Source               | Path                                                            | Notes                                         |
| -------------------- | --------------------------------------------------------------- | --------------------------------------------- |
| Compiled (custom)    | `$REPO_ROOT/.pio/build/BTT_SKR_SE_BX_BOOT/firmware.bin`         | Your fork with config changes                 |
| Pre-compiled (stock) | `$REPO_ROOT/firmware.bin`                                       | looxonline's tested binary — use for recovery |
| Official BIQU        | [`bigtreetech/BIQU-BX`](https://github.com/bigtreetech/BIQU-BX) | Stock Marlin 2.0.6, different config          |

## Key Configuration Notes

- `PROBING_MARGIN` must stay at **30** — reducing it below 30 causes G29 to attempt Y=245, past the physical travel limit (~183mm), triggering M112
- G30 corner probing requires X≥30 and Y≥30 due to PROBING_MARGIN
- Valid back-corner G30 commands: `G30 X30 Y210` (back-left), `G30 X210 Y210` (back-right)
- Bed mesh Y display is inverted: row 0 in the visualizer = physical back (high Y), row 4 = front (low Y)
