#!/usr/bin/env bash
# ECP5 (IcePi Zero) build for MSXnano — open-source flow (yosys + ghdl + nextpnr-ecp5).
# Reads the source list from build.tcl, drops the Gowin-specific files, adds the lattice ones,
# defines ECP5. See BUILD_ECP5.md. WIP — first passes are for flushing compile errors.
set -u
OSS="/Volumes/External/MiniST_Project/tools/oss-cad-suite"
export PATH="$OSS/bin:$PATH"
export GHDL_PREFIX="$OSS/lib/ghdl"   # so the yosys ghdl plugin (libghdl) finds std/ieee
cd "$(dirname "$0")"   # fpga/

VHDL=""; VLOG=""
while read -r kw path _; do
  [ "$kw" = "add_file" ] || continue
  case "$path" in
    *.cst|*.sdc|*.gprj) continue;;
    src/gowin/clk_108p.v|src/gowin_clkdiv/gowin_clkdiv.v|src/gowin_clkdiv2/gowin_clkdiv2.vhd) continue;;
    tn_vdp_v3_v9958/src/gowin/clk_135.v|tn_vdp_v3_v9958/src/hdmi/serializer.sv) continue;;
  esac
  case "$path" in
    *.vhd) VHDL="$VHDL $path";;
    *.v|*.sv) VLOG="$VLOG $path";;
  esac
done < build.tcl

# ECP5-only sources
VLOG="$VLOG src/lattice/clocks_ecp5.v src/lattice/bufg_ecp5.v src/lattice/serializer_ecp5.sv"

echo "== VHDL files:"; echo $VHDL | tr ' ' '\n' | grep -c .
echo "== Verilog/SV files:"; echo $VLOG | tr ' ' '\n' | grep -c .

echo "== [1/3] ghdl analyze VHDL (fixpoint loop to resolve dependency order) =="
for pass in 1 2 3 4 5 6 7 8 9 10; do
  errs=0
  for f in $VHDL; do ghdl -a --std=08 -fsynopsys -frelaxed "$f" 2>/dev/null || errs=$((errs+1)); done
  echo "  pass $pass: $errs file(s) still unresolved"
  [ "$errs" = 0 ] && break
done
if [ "$errs" != 0 ]; then
  echo "-- remaining VHDL errors: --"
  for f in $VHDL; do ghdl -a --std=08 -fsynopsys -frelaxed "$f" 2>&1 | grep -i error | head -2; done | sort -u | head
  echo "GHDL ANALYZE FAILED"; exit 1
fi

echo "== [2/3] yosys synth_ecp5 =="
yosys -m ghdl -p "
  ghdl --std=08 -fsynopsys -frelaxed t80;
  read_verilog -sv -DECP5 $VLOG;
  hierarchy -top top;
  synth_ecp5 -top top -json msx_ecp5.json
" || { echo "YOSYS FAILED"; exit 1; }

echo "== [3/3] nextpnr-ecp5 (45F, CABGA256) =="
nextpnr-ecp5 --45k --package CABGA256 --json msx_ecp5.json --lpf icepi.lpf --textcfg msx_ecp5.config \
  && echo "P&R OK" || echo "P&R FAILED"
