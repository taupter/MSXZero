#!/usr/bin/env bash
# Generate a single flattened Verilog of the WHOLE MSX core for full-design simulation
# (boot-in-sim). The mixed VHDL/Verilog/SV design -> one behavioral .v that iverilog can run,
# plus the ECP5 primitive models in ecp5_prims_sim.v.
#
# Prereq: run `./build_ecp5.sh` first (it produces gen/vhdl/*.il + gen/sv2v_out.v that this reuses).
# Output: sim/sim_msx.v  (module `top`).  Then:
#   iverilog -g2012 -o sim/simtop sim/tb_boot.v sim/sim_msx.v sim/ecp5_prims_sim.v sim/sdram_model.v
set -u
OSS="${OSS:-/Volumes/External II/tools/oss-cad-suite}"
export PATH="$OSS/bin:$PATH"; export GHDL_PREFIX="$OSS/lib/ghdl"
cd "$(dirname "$0")/.."   # fpga/
OUT="sim/sim_msx.v"

[ -f gen/sv2v_out.v ] && ls gen/vhdl/*.il >/dev/null 2>&1 || { echo "run ./build_ecp5.sh first (need gen/)"; exit 1; }

VLOG_V=""
while read -r kw path _; do
  [ "$kw" = "add_file" ] || continue
  case "$path" in
    *.cst|*.sdc|*.gprj) continue;;
    src/gowin/clk_108p.v|src/gowin_clkdiv/gowin_clkdiv.v|src/gowin_clkdiv2/gowin_clkdiv2.vhd) continue;;
    tn_vdp_v3_v9958/src/gowin/clk_135.v|tn_vdp_v3_v9958/src/hdmi/serializer.sv) continue;;
    tn_vdp_v3_v9958/src/v9958_top.v) continue;;
    *.sv) continue;;
    *.v) VLOG_V="$VLOG_V $path";;
  esac
done < build.tcl
VLOG_V="$VLOG_V src/lattice/clocks_ecp5.v src/lattice/bufg_ecp5.v gen/sv2v_out.v"
RD=""; for f in gen/vhdl/*.il; do RD="$RD read_rtlil $f;"; done

# EXTRA_DEFINES lets the caller add sim shortcuts, e.g.:
#   EXTRA_DEFINES="-DSIM_FAST_BOOT -DSIM_FAST_INIT" ./sim/gen_full_sim.sh
# (SIM_FAST_BOOT shortens the reset ramp + the ~3s ESP hold; SIM_FAST_INIT shortens SDRAM init.)
yosys -q -p "
  $RD
  read_verilog -sv -DECP5 ${EXTRA_DEFINES:-} $VLOG_V;
  hierarchy -top top; flatten; proc;
  memory_collect; setundef -init -zero;
  opt_clean;
  write_verilog -noattr $OUT
" || { echo "yosys failed"; exit 1; }

# iverilog can't take an inout port that write_verilog also emits as a driven `reg`.
# Split each such driver: reg X -> reg X_r + `assign X = X_r;`, and `X <= ` -> `X_r <= `.
# (setundef -init adds `= <val>` to the reg decls, so match both forms.)
perl -0pi -e '
  s/  reg \[15:0\] IO_sdram_dq(\s*=\s*16.h0000)?;/  reg [15:0] IO_sdram_dq_r$1;\n  assign IO_sdram_dq = IO_sdram_dq_r;/;
  s/    IO_sdram_dq <= /    IO_sdram_dq_r <= /g;
  s/  reg mspi_mosi(\s*=\s*1.h0)?;/  reg mspi_mosi_r$1;\n  assign mspi_mosi = mspi_mosi_r;/;
  s/ mspi_mosi <= / mspi_mosi_r <= /g;
' "$OUT"

echo "wrote $OUT ($(wc -l < "$OUT") lines)"
