#!/usr/bin/env bash
# ECP5 (IcePi Zero) build for MSXnano — open-source flow (yosys + ghdl + nextpnr-ecp5).
# Reads the source list from build.tcl, drops the Gowin-specific files, adds the lattice ones,
# defines ECP5. See BUILD_ECP5.md. WIP — first passes are for flushing compile errors.
set -u
OSS="/Volumes/External/MiniST_Project/tools/oss-cad-suite"
export PATH="$OSS/bin:$PATH"
export GHDL_PREFIX="$OSS/lib/ghdl"   # so the yosys ghdl plugin (libghdl) finds std/ieee
cd "$(dirname "$0")"   # fpga/

VHDL=""; VLOG_V=""; VLOG_SV=""
while read -r kw path _; do
  [ "$kw" = "add_file" ] || continue
  case "$path" in
    *.cst|*.sdc|*.gprj) continue;;
    src/gowin/clk_108p.v|src/gowin_clkdiv/gowin_clkdiv.v|src/gowin_clkdiv2/gowin_clkdiv2.vhd) continue;;
    tn_vdp_v3_v9958/src/gowin/clk_135.v|tn_vdp_v3_v9958/src/hdmi/serializer.sv) continue;;
  esac
  case "$path" in
    *.vhd) VHDL="$VHDL $path";;
    # v9958_top.v is .v but uses SV unpacked arrays internally to wire the HDMI
    # encoder + serializer; convert it in the SAME sv2v run so those flatten consistently.
    tn_vdp_v3_v9958/src/v9958_top.v) VLOG_SV="$VLOG_SV $path";;
    *.sv)  VLOG_SV="$VLOG_SV $path";;
    *.v)   VLOG_V="$VLOG_V $path";;
  esac
done < build.tcl

# ECP5-only sources
VLOG_V="$VLOG_V src/lattice/clocks_ecp5.v src/lattice/bufg_ecp5.v"
VLOG_SV="$VLOG_SV tn_vdp_v3_v9958/src/hdmi/serializer_ecp5.sv"

echo "== VHDL files:"; echo $VHDL | tr ' ' '\n' | grep -c .
echo "== Verilog (.v):"; echo $VLOG_V | tr ' ' '\n' | grep -c .
echo "== SystemVerilog (.sv):"; echo $VLOG_SV | tr ' ' '\n' | grep -c .

# yosys's Verilog frontend can't parse SV unpacked-array ports / casts (the HDMI
# packet code). Convert the .sv set to Verilog-2005 with sv2v first, into one file.
echo "== [0/3] sv2v: SystemVerilog -> Verilog =="
mkdir -p gen
sv2v -DECP5 $VLOG_SV -w gen/sv2v_out.v || { echo "SV2V FAILED"; exit 1; }
echo "  wrote gen/sv2v_out.v ($(wc -l < gen/sv2v_out.v) lines)"
VLOG="$VLOG_V gen/sv2v_out.v"

# VHDL in dependency order (packages/leaf entities before their users) so both the
# analyze step and `ghdl -read` see definitions first. Derived from vhdl_deps.py.
VHDL_ORDER="src/usb/usb_keyboard_msx.vhd G80A/t80_pack.vhd G80A/T80s.vhd G80A/g80a.vhd G80A/t80.vhd G80A/t80_alu.vhd G80A/t80_mcode.vhd G80A/t80_reg.vhd denoise/denoise.vhd monostable/monostable.vhd src/ocm/fifo.vhd src/ocm/lpf.vhd src/ocm/scc_wave2.vhd tn_vdp_v3_v9958/src/vdp/vdp_package.vhd src/ocm/swioports.vhd src/ocm/uart_lite.vhd src/ocm/wifi_lite.vhd tn_vdp_v3_v9958/src/ram.vhd tn_vdp_v3_v9958/src/vdp/vdp.vhd tn_vdp_v3_v9958/src/vdp/vdp_colordec.vhd tn_vdp_v3_v9958/src/vdp/vdp_command.vhd tn_vdp_v3_v9958/src/vdp/vdp_doublebuf.vhd tn_vdp_v3_v9958/src/vdp/vdp_graphic123m.vhd tn_vdp_v3_v9958/src/vdp/vdp_graphic4567.vhd tn_vdp_v3_v9958/src/vdp/vdp_hvcounter.vhd tn_vdp_v3_v9958/src/vdp/vdp_interrupt.vhd tn_vdp_v3_v9958/src/vdp/vdp_linebuf.vhd tn_vdp_v3_v9958/src/vdp/vdp_ntsc_pal.vhd tn_vdp_v3_v9958/src/vdp/vdp_register.vhd tn_vdp_v3_v9958/src/vdp/vdp_spinforam.vhd tn_vdp_v3_v9958/src/vdp/vdp_sprite.vhd tn_vdp_v3_v9958/src/vdp/vdp_ssg.vhd tn_vdp_v3_v9958/src/vdp/vdp_text12.vhd tn_vdp_v3_v9958/src/vdp/vdp_vga.vhd tn_vdp_v3_v9958/src/vdp/vdp_wait_control.vhd tn_vdp_v3_v9958/src/vdp/vencode.vhd"

echo "== [1/3] ghdl analyze VHDL (clean lib + skip-successful fixpoint) =="
# Clean slate: a stale work library is what lets a re-analyzed package obsolete
# an entity that already compiled (the T80/T80_Pack error). Start fresh.
rm -f work-obj08.cf work-obj93.cf 2>/dev/null
remaining="$VHDL"; GA="ghdl -a --std=08 -fsynopsys -frelaxed"
for pass in 1 2 3 4 5 6 7 8 9 10 11 12; do
  fail=""; n=0
  # only (re)try files not yet analyzed -> each file compiles exactly once,
  # so no package is ever re-analyzed after a dependent entity (no obsolescence).
  for f in $remaining; do
    if $GA "$f" >/dev/null 2>&1; then :; else fail="$fail $f"; n=$((n+1)); fi
  done
  echo "  pass $pass: $n file(s) still unresolved"
  remaining="$fail"
  [ -z "$remaining" ] && break
done
if [ -n "$remaining" ]; then
  echo "-- remaining VHDL errors: --"
  for f in $remaining; do echo "### $f"; $GA "$f" 2>&1 | grep -i error | head -3; done | head -40
  echo "GHDL ANALYZE FAILED"; exit 1
fi

echo "== [2/3] yosys synth_ecp5 =="
# Mixed-language import: `ghdl -read` loads ALL VHDL entities into the design as
# modules ONCE each (shared sub-entities like `ram` are not duplicated), visible to
# `hierarchy` so the Verilog instantiations bind to them. This replaces per-top
# elaboration, which re-defined any entity shared between two tops. VHDL is passed
# in dependency order (packages before users) via $VHDL_ORDER.
VHDL_READ="${VHDL_ORDER:-$VHDL}"
yosys -m ghdl -p "
  ghdl -read --std=08 -fsynopsys -frelaxed $VHDL_READ;
  read_verilog -sv -DECP5 $VLOG;
  hierarchy -top top;
  synth_ecp5 -top top -json msx_ecp5.json
" 2>&1 | tee yosys.log
[ "${PIPESTATUS[0]}" = 0 ] || { echo "YOSYS FAILED"; exit 1; }

echo "== [3/3] nextpnr-ecp5 (45F, CABGA256) =="
nextpnr-ecp5 --45k --package CABGA256 --json msx_ecp5.json --lpf icepi.lpf --textcfg msx_ecp5.config \
  && echo "P&R OK" || echo "P&R FAILED"
