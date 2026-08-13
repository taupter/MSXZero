#!/usr/bin/env bash
# build_goauld_cbios.sh — build a copyright-free "goauld" boot pack around C-BIOS, so the MSXnano
# boot MENU is present (the copyrighted MSX BIOS/sub-ROM/Kanji are swapped for C-BIOS + 0xFF filler).
# Layout matches src/rom/build.bat (the offsets the top.v slot decoder expects). Output:
#   sim/goauld_cbios.hex  (byte-per-line, for $readmemh in tb_menu.v; loaded to SDRAM @0x700000)
#
# Needs C-BIOS roms (BSD, redistributable) — point CBIOS at an extracted cbios-0.29a.
set -e
cd "$(dirname "$0")/.."                        # -> fpga/
CBIOS="${CBIOS:-$1}"                            # dir with cbios_main_msx2+.rom + cbios_sub.rom
[ -z "$CBIOS" ] && { echo "usage: CBIOS=/path/to/cbios sim/build_goauld_cbios.sh"; exit 1; }
R=src/rom; M=src/msxnano_menu; OUT=sim/goauld_cbios.bin

# 0xFF filler for the copyrighted Kanji ROMs (JIS1 128K, JIS2 128K, Kanji-font 32K)
python3 -c "open('/tmp/ff128k','wb').write(b'\xff'*131072); open('/tmp/ff32k','wb').write(b'\xff'*32768)"

# concatenate in build.bat order (C-BIOS in place of the MSX2+ BIOS + sub-ROM)
cat /tmp/ff128k /tmp/ff128k \
    "$R/Nextor-2.1.1.WonderTANG.ROM.bin" \
    "$CBIOS/cbios_main_msx2+.rom" "$CBIOS/cbios_sub.rom" \
    "$M/fm_logo_menu.bin" \
    /tmp/ff32k \
    "$R/esp8266e.rom" "$R/logo16k.bin" "$R/6b_config.bin" \
    > "$OUT"
sz=$(wc -c < "$OUT")
echo "built $OUT: $sz bytes (expect 524294 = 512K+6)"
[ "$sz" = 524294 ] || { echo "SIZE MISMATCH"; exit 1; }

# byte-per-line hex for the sim
od -An -v -tx1 "$OUT" | tr -s ' ' '\n' | grep -v '^$' > sim/goauld_cbios.hex
echo "wrote sim/goauld_cbios.hex ($(wc -l < sim/goauld_cbios.hex) lines) — load at SDRAM 0x700000"
echo "  BIOS@0x760000, sub@0x768000, MENU@0x76C000 (auto-boot 'AB' ROM, INIT 0x4760)"
