#!/usr/bin/env bash
# build_sdram_test.sh — standalone SDRAM memtest bitstream for IcePi Zero bring-up (stage 4).
# The REAL memory_ctrl (src/memory.v) + clocks_ecp5 + a memtest FSM. No VHDL/ghdl, no MSX.
# Run from fpga/:  bash bringup/build_sdram_test.sh   ->  bringup/sdram_test.bit
set -e
cd "$(dirname "$0")/.."                       # -> fpga/
OSS="/Volumes/External II/tools/oss-cad-suite"
[ -d "$OSS/bin" ] && export PATH="$OSS/bin:$PATH"
mkdir -p bringup/gen

echo "== [1/3] synth_ecp5 (top=sdram_test_top) =="
yosys -q -p "
  read_verilog -DECP5 src/lattice/clocks_ecp5.v src/memory.v bringup/sdram_test_top.v;
  synth_ecp5 -top sdram_test_top -flatten -run :map_luts;
  abc -lut 4:7;
  clean;
  synth_ecp5 -top sdram_test_top -run map_cells:;
  write_json bringup/gen/sdram_test.json;
  stat
"

echo "== [2/3] nextpnr-ecp5 =="
# --lpf-allow-unconstrained: O_sdram_addr[11:12] exist in the 13-bit RTL bus but aren't wired on the IcePi.
nextpnr-ecp5 --45k --package CABGA256 \
  --json bringup/gen/sdram_test.json --lpf bringup/sdram_test.lpf --lpf-allow-unconstrained \
  --textcfg bringup/gen/sdram_test.config

echo "== [3/3] ecppack =="
ecppack bringup/gen/sdram_test.config bringup/sdram_test.bit
echo "== done: bringup/sdram_test.bit ($(ls -la bringup/sdram_test.bit | awk '{print $5}') bytes) =="
