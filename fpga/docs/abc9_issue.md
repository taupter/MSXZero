# abc9 / XAIGER "Visited AIG node more than once" — investigation

Status: open upstream (labelled `bug` + `ABC`). Worked around by using classic `abc -lut 4:7` in
`build_ecp5.sh` (the design synthesizes/fits/routes/bitstreams fine). abc9 (better timing) is unavailable.
WARNING: that workaround has an expiry date — upstream PR #6103 (merged 2026-08-19) removes classic
`abc` mapping and the `-noabc9` option. Toolchain is pinned; see the 2026-08-19 update at the end.

## The failure
Yosys `synth_ecp5` with abc9 dies at the AIG export, before abc9 maps anything:
```
68.46.24.3. Executing XAIGER backend.
ERROR: Visited AIG node more than once; this could be a combinatorial loop that has not been broken
```
Toolchain: Yosys 0.68+48 (dev build, OSS CAD Suite). Classic abc works; only abc9's
XAIGER export fails. Losing abc9 costs timing/retiming quality (see `clk_54m` timing).

## Ruled out (every one still fails with the IDENTICAL error)
1. Tri-state cells — `select t:$_TBUF_ t:$tbuf` = 0 cells (`proc` collapses them); `tribuf`/`tribuf -logic` are no-ops.
2. Internal tri-state in RTL — converted every internal `'z` to a defined value: internal
 bus (`en?data:8'hzz`→`:8'hff`), a debounce module's `1'bz`, and a tri-stated clock
 (`ena_n?1'bz:clk`→`?1'b0:clk`). Still fails. (Only true IO tri-states left: SD pins.)
3. Real combinational loop — `scc` reports 0 SCCs right before abc9 (`synth_ecp5 -run :map_luts`).
4. Wide-mux boxes — `-nowidelut`: fails.
5. DSP boxes — `-nodsp`: fails.
6. ALL black boxes — `-nobram -nolutram -nodsp -nowidelut` (pure LUT/FF): still fails.
7. `-flatten` and hierarchical: both fail.

Since a pure LUT/FF design with no tri-state and no SCC still trips XAIGER, this is not
structural in our design — it's a Yosys/abc9 (XAIGER) bug in this dev build.

## Expert analysis (summary)
- XAIGER must topologically order abc9 "boxes" (RAM/DSP); a box dependency cycle SCC can't see
 would explain it — BUT we ruled that out (item 6). Also: past abc9 flop-bypass rules could
 model a false set/reset→output combinational path.
- Likely a dev-build regression. Matching upstream reports:
 - yosys #4168 — identical error with `synth_ice40 -abc9`; removing `-abc9` fixed it.
 - yosys #4291 — same error on ECP5, `scc` reports no loops, XAIGER fails. Still OPEN (2026-08-13,
   label "pending-verification"), no fix merged, root cause not diagnosed by maintainers. The only
   documented workaround is `-noabc9` (i.e. classic abc, what this build uses). #4168 (ice40, same
   error) is likewise open. A minimal reproducer from our design could help move it forward.
 Our 0.68+48 is newer than that fix, but a dev branch can reintroduce a regression — the most
 likely explanation given every structural cause here is ruled out.

## What to try when revisiting (in rough priority)
1. Switch to a stable tagged Yosys (e.g. a release OSS CAD Suite snapshot), re-test abc9.
 verify the ghdl plugin + sv2v flow still work on that version first.
2. Diagnose with `write_xaiger`: `synth_ecp5 -run :map_luts` then `write_xaiger -map syms.txt out.xaig`;
 inspect `out.xaig` (text) for the offending node/box, or feed it to standalone `abc` for a better message.
3. Fall back stays valid: classic abc (current `build_ecp5.sh`) — stable, just weaker timing.

## Why it's not urgent
The only thing abc9 would buy is closing `clk_54m` timing. That path is the clock-enabled
(multicycle) T80 CPU, which very likely runs fine on hardware regardless (see the timing notes
in the main README / `project-msxnano-f45` memory). So: revisit abc9 only if hardware shows a
real CPU-domain timing problem.

## Update (2026-08-13): the latest OSS CAD Suite nightly also crashes
Tested the whole flow with a fresh OSS CAD Suite nightly (2026-08-13, Yosys 0.68+58, only ~10 commits
past our 0.68+48) — swapping in just the newer yosys for the synth step. abc9 (`synth_ecp5 -abc9`)
fails identically: "Visited AIG node more than once" in the XAIGER backend. So the fix is NOT in the
latest nightly; a working abc9 needs a release from before the regression, or a future fixed one.
Classic `abc -lut 4:7` remains the flow.

## Update (2026-08-19): upstream confirmed it — and our workaround has an expiry date
Reported on the upstream ticket (https://github.com/YosysHQ/yosys/issues/4291) and got a reply
the same day. The issue was relabelled from `pending-verification` to `bug` + `ABC`.

Two things came out of it.

**1. The cause is the `inout` port, not a loop.** Ravenslofty (Yosys maintainer):
"I think this is actually to do with the `inout` port in the minimised testcase. Bidirectional
port handling is *hard* in ABC9 because the XAIGER format does not natively support
bidirectional ports." This matches item 2 in "Ruled out" above — we had already narrowed it to
"only true IO tri-states left: SD pins". The misleading "combinatorial loop" text is a red herring.

**2. `-noabc9` and classic `abc` are being REMOVED.** PR https://github.com/YosysHQ/yosys/pull/6103
("synth_*: remove classic ABC mapping") was merged 2026-08-19 11:33 UTC. From the PR: "I intend to
remove `abc -lut`, so all users of it must be moved over to use `abc9 -lut` instead, and options
enabling/disabling ABC9 must be removed." Both halves of our workaround are going away: the
`abc -lut 4:7` call in build_ecp5.sh, and `-noabc9`.

**Where that leaves us.** Verified today: the minimised testcase still crashes on 0.68+48 AND on
0.68+86 (2026-08-19 nightly, 9eb62484d), so it is not a recent regression. abc9 is the default in
synth_ecp5 (`-noabc9` is documented as "disable use of new ABC9 flow", and `abc9 -W 300` sits in
the map_luts stage) — our two-phase split skips map_luts entirely, which is why our build works.

PINNED TOOLCHAIN: Yosys 0.68+86 (9eb62484d) at /Volumes/External II/tools/oss-cad-suite.
That nightly was built 02:42 UTC, ~9h BEFORE #6103 merged, so it still has `abc -lut` and
`-noabc9`. Tarball kept at /Volumes/External II/tools/oss-cad-suite-darwin-arm64-20260819.tgz.
DO NOT update the toolchain casually — the next nightly may break build_ecp5.sh outright.

**Real fix (survives the abc9 transition):** stop passing bidirectional ports through internal
modules. Carry `_i` / `_o` / `_oe` as separate signals and instantiate the actual bidirectional
buffer only at top level. Unproven for our design, but it follows from the maintainer's diagnosis
and is the only route that still works once classic abc is gone.
