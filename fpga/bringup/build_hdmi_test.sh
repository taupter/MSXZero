#!/usr/bin/env bash
# build_hdmi_test.sh — standalone HDMI test-pattern bitstream for IcePi Zero bring-up (stage 3).
# Video output path ONLY (clocks_ecp5 + hdl-util hdmi + serializer_ecp5) — no VHDL, no ghdl, no MSX.
# Run from the fpga/ dir:  bash bringup/build_hdmi_test.sh   ->  bringup/hdmi_test.bit
set -e
cd "$(dirname "$0")/.."                      # -> fpga/
OSS="/Volumes/External/MiniST_Project/tools/oss-cad-suite"
[ -d "$OSS/bin" ] && export PATH="$OSS/bin:$PATH"
mkdir -p bringup/gen

H=tn_vdp_v3_v9958/src/hdmi
# All HDMI .sv EXCEPT the Gowin serializer.sv; plus serializer_ecp5.sv and our top.
SV="$H/hdmi.sv $H/tmds_channel.sv $H/packet_assembler.sv $H/packet_picker.sv \
    $H/audio_clock_regeneration_packet.sv $H/audio_sample_packet.sv $H/audio_info_frame.sv \
    $H/auxiliary_video_information_info_frame.sv $H/source_product_description_info_frame.sv \
    $H/serializer_ecp5.sv bringup/hdmi_test_top.sv"

echo "== [0/3] sv2v: SystemVerilog -> Verilog =="
sv2v -DECP5 $SV -w bringup/gen/hdmi_test_sv2v.v
echo "   wrote bringup/gen/hdmi_test_sv2v.v ($(wc -l < bringup/gen/hdmi_test_sv2v.v) lines)"

echo "== [1/3] synth_ecp5 (top=hdmi_test_top) =="
yosys -q -p "
  read_verilog -sv -DECP5 src/lattice/clocks_ecp5.v bringup/gen/hdmi_test_sv2v.v;
  synth_ecp5 -top hdmi_test_top -flatten -run :map_luts;
  abc -lut 4:7;
  clean;
  synth_ecp5 -top hdmi_test_top -run map_cells:;
  write_json bringup/gen/hdmi_test.json;
  stat
"

echo "== [2/3] nextpnr-ecp5 =="
nextpnr-ecp5 --45k --package CABGA256 \
  --json bringup/gen/hdmi_test.json --lpf bringup/hdmi_test.lpf \
  --textcfg bringup/gen/hdmi_test.config

echo "== [3/3] ecppack =="
ecppack bringup/gen/hdmi_test.config bringup/hdmi_test.bit
echo "== done: bringup/hdmi_test.bit ($(ls -la bringup/hdmi_test.bit | awk '{print $5}') bytes) =="
