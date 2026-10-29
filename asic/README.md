# ASIC Flow: LibreLane + Sky130 130nm

Two designs taken through an open-source ASIC flow to compare with the FPGA implementation in Vivado. 

**Note on tooling:** OpenLane 2 was renamed to LibreLane in early 2026, and it's
the same codebase and backward-compatible. Commands below use `librelane`, not
`openlane`.

---

## Designs

### `alu/`: zero-risk first pass
The RV32I ALU (`src/alu.sv`). Is purely combinational 32-bit ADD/SUB/AND/OR/XOR/shifts/SLT, Which has no sequential state (`CLOCK_PORT: null`), so it was used only to validate
the toolchain.

**Result:** Antenna, LVS, and DRC all passed clean. However, one item got flagged (`1 XOR
difference`), which was confirmed to be harmless and didnt affect anything. Both the ALU run and the pe_cell run below
produce the same single-shape mismatch on GDS layer `235/4` (`prBoundary.boundary`),
a non-fabrication placement/routing marker layer where Magic and KLayout's GDS
stream out tools disagreed on rendering, so it isn't a real issue. Setup timing
violations on this run are also a config artifact rather than a legitamite result to consider,
due to a purely combinational design still getting a virtual clock from
`CLOCK_PERIOD`, and the ALU's actual delay exceeding the placeholder period. That
wasn't worth fixing and improving since the ALU run's only purpose was proving the toolchain actually worked.

### `pe_cell/`: portfolio piece

![pe_cell placed-and-routed layout, full hierarchy, KLayout / Sky130](pe_cell/layout.png)

A single output-stationary PE extracted from the 4×4 parallel MAC accelerator's
compute loop (`src/pe_cell.sv`). It is a two-stage pipeline: an 8×8 multiplier
writes a 16-bit product register, and the next cycle that product is added into
a 32-bit accumulator register. `parallel_mac_sub.sv` doesn't instantiate this
module, it writes the same multiply-add inline for all 16 PEs in a single cycle,
so the pipelining described below applies to the ASIC module only.

The RTL was verified before touching LibreLane via `make sim MODULE=pe_cell`, which
runs 10 of 10 passing tests, including a PDOT cross-validation against the full
pipeline testbench (expected 70, confirmed 70) and a signed/unsigned
discriminator. Feeding `a=0xFF, b=0x02` and getting 510 confirms the module
uses zero-extension and unsigned multiply, matching the original
`parallel_mac_sub.sv` compute loop, since a signed version would have
produced -2 instead. The other tests cover the one-cycle product latency,
`en` held low, `en` held high during reset (must not be accumulated), and `en`
toggling mid-stream.

**Clock constraint:** 16 ns (62.5 MHz). Closes at all nine PVT corners,
including the slow-process, 100°C corner. See "What the timing result actually
shows" below for how it got there.

The layout image above is from the earlier single-cycle run.

---

## Setup

### Prerequisites
- Docker Desktop (macOS or Linux)
- ~20 GB free disk (image + PDK)

### Pull and start the toolchain

The correct image is `hpretl/iic-osic-tools`, pulled through the project's own
launch scripts.

```bash
git clone --depth=1 https://github.com/iic-jku/iic-osic-tools.git
cd iic-osic-tools
./start_shell.sh
```

This mounts a design directory (auto detected, and shown in the script's own
output as "Design directory auto-set to...") into the container at
`/foss/designs`. Use `./start_shell.sh` for everything below, since it's a
plain terminal with working copy and paste. Only use `./start_vnc.sh` (which
opens a browser-based desktop at `http://localhost:80`) when you actually need
KLayout's GUI to view a GDS file.

Copy this repo into that mounted design directory from your host machine, not
from inside the container:
```bash
cp -r /path/to/riscv-rv32im-gemm /path/to/mounted/designs/
```

### Install LibreLane inside the container
```bash
pip install --upgrade librelane
librelane --version
librelane --smoke-test
```
A passing smoke test ends with `Smoke test passed.` along with clean Antenna/LVS/DRC checks. Warnings about thread count, IO placement defaults, or
`VSRC_LOC_FILES` are expected on the given example design and don't indicate
an issue, so do not worry.

---

## Running the flow

From `/foss/designs/riscv-rv32im-gemm` inside the container:

```bash
librelane asic/alu/config.json
librelane asic/pe_cell/config.json
```

Results land in `asic/<design>/runs/RUN_<timestamp>/`.

---

## What the timing result actually shows

### Before: single-cycle MAC

The original single-cycle pe_cell closed at typical (`tt`) and fast-process
(`ff`) corners at 16 ns but **not** at the slow-process/100°C (`ss`) corners:
worst slack -0.370 ns (nominal: -0.220 ns, min: -0.123 ns, max: -0.370 ns).

The critical path (from `report_checks` at `max_ss_100C_1v60`) ran from an
input operand bit (`b[7]`) through the multiplier's partial-product reduction
tree (`maj3`/`xnor2`/`xor2` gates, the carry-save-adder signature) and directly
into the accumulator's carry-propagate adder chain (`a211oi`/`o31ai`/`nor2`/
`o311ai`/`and4` gates), landing on the accumulator's flip-flop: the entire 8×8
multiply feeding the 32-bit add as one combinational path in a single cycle.

Two experiments from that phase, and what they actually show:
- *Larger floorplan.* A 150×150 die at 35% utilization made worst-corner slack
  *worse* (-0.483 ns vs. -0.370 ns), so routing congestion was not the problem.
- *Clock-period sweep.* Slack improved from -4.35 ns (10 ns period) to
  -0.370 ns (16 ns), then got *worse* at 17 ns (-0.567 ns). A fixed gate delay
  would have improved by about 1 ns with the looser clock. Slack getting worse
  means the flow built a different, slower netlist under the looser target.
  The post-pipelining runs below found the cause: the repair steps' buffering
  choices, which vary from run to run.

### Step 1: pipeline the RTL

`src/pe_cell.sv` registers the 16-bit product (`prod_q`) before it feeds the
32-bit adder, so the multiply and the accumulate land in separate cycles. A
valid bit (`en_q`, reset to 0) travels with the product, so `prod_q` needs no
reset or load enable, keeping a mux off the multiplier's D-input path. Each
product lands in `acc` one cycle after it is fed.

On its own this did **not** close timing. Max `ss` slack went to -0.534 ns.
Both failing paths, the multiplier stage (`b[0]` → `prod_q`) and the adder
stage (`acc` → `acc`), had logic that fit easily. What didn't fit was buffering
the flow had added:
- **Delay cells used as ordinary buffers.** The high-fanout and max-cap repair
  steps picked `clkdlybuf4s*` cells (built to add delay) to buffer input and
  internal nets: 2.60 ns of the multiplier path and 5.26 ns of the adder path.
- **No setup repair after routing.** Setup was last repaired after clock-tree
  synthesis, on estimated wire loads, and nothing checked it again once real
  routing existed.

### Step 2: fix the flow configuration

Each change was tested on its own, against the same pipelined RTL:

| Change in `asic/pe_cell/config.json` | max / nom / min `ss` setup slack (ns) | Max-slew violations |
|---|---|---|
| Pipelined RTL, default config | -0.534 / -0.401 / -0.312 | 16 |
| `RUN_POST_GRT_RESIZER_TIMING: true` | -0.121 / +0.014 / +0.111 | 5 |
| `GRT_RESIZER_SETUP_SLACK_MARGIN: 0.3` | -0.067 / +0.141 / +0.288 | 5 |
| `SYNTH_STRATEGY: "DELAY 1"` *(reverted)* | -0.416 / -0.186 / +0.022 | 18 |
| `EXTRA_EXCLUDED_CELLS: clkdlybuf4s*` | +0.063 / +0.187 / +0.282 | 104 |
| `RUN_POST_GRT_DESIGN_REPAIR: true` | +0.102 / +0.250 / +0.351 | 93 |
| Also exclude `buf_1`, `clkbuf_1` (**final**) | **+0.180 / +0.285 / +0.364** | **5** |

Notes on the less obvious rows:
- **Raising the setup margin to 0.3 ns** makes the post-route repair aim past
  the gap between its global-route estimates and the final extracted
  parasitics. It fixed the multiplier stage, but the adder stage still looked
  passing to the repair step, so it was never worked on.
- **`DELAY 1` synthesis made things worse.** The faster multiplier spreads each
  input bit across many more gates. The input nets then needed more fanout
  buffers, which were again delay cells (6.15 ns of the worst path). Area grew
  21%. Reverted.
- **Banning the delay cells closed setup but caused slew violations.** The
  repair steps fell back to size-1 buffers (`buf_1`, `clkbuf_1`), each driving
  about 10 loads, too weak at `ss`. The post-route slew repair saw only 4 of
  those 93 violations on its estimated parasitics. Banning size-1 buffers forced
  size 2 or larger and fixed both.

### Final result

Run `RUN_2026-10-29_04-53-28`, 16 ns (62.5 MHz):

| Corner | Setup worst slack | Hold worst slack |
|---|---|---|
| `ss` (max / nom / min) | +0.180 / +0.285 / +0.364 ns | +0.925 / +0.914 / +0.906 ns |
| `tt` (max / nom / min) | +6.532 / +6.598 / +6.657 ns | +0.350 / +0.343 / +0.337 ns |
| `ff` (max / nom / min) | +8.967 / +9.011 / +9.051 ns | +0.124 / +0.119 / +0.116 ns |

Zero setup or hold violations. DRC, LVS and antenna clean. The worst path is
now the multiplier stage: input `b[1]` through the partial-product tree into
`prod_q[15]`.

**Known remaining issue:** 5 max-slew violations, all on one net at the `ss`
corners. A size-1 four-input NOR (`nor4_1`, created by synthesis) drives 4 gates
plus a buffer with a 0.925 ns transition, against the 0.75 ns limit. No repair
step resized it. It meets timing, and it's within the library's own
characterized range (up to 1.5 ns), but a stricter sign-off would flag it.

The 7 `clkbuf_1` cells still in the netlist (`clkload0`-`clkload6`) are dummy
loads the clock-tree step adds to balance the tree. They ignore the exclusion
list and drive no logic.

**One caveat on the absolute numbers:** the multiplier path's first ~3.2 ns,
roughly 20% of the 16 ns budget, is a fixed input external delay that comes
from LibreLane's generic fallback SDC, since no `PNR_SDC_FILE` or
`SIGNOFF_SDC_FILE` is defined. A real sign-off would set this deliberately, and
doing so could change the reported numbers in either direction.

---

## Key output files

| File | What it tells you |
|------|-------------------|
| `runs/.../final/gds/*.gds` | GDSII, opened in KLayout (`klayout <file>.gds`), VNC mode only |
| `runs/.../final/nl/*.v` | Gate-level netlist after technology mapping |
| `runs/.../final/metrics.json` | All run metrics in one file, including timing (`timing__setup__ws__corner:*`), DRC/LVS/antenna counts, and power |
| `runs/.../resolved.json` | Every config variable the run actually used, including defaults |
| `runs/.../*-openroad-stapostpnr/<corner>/max.rpt` | Worst setup paths, cell by cell (startpoint, endpoint, delay) for that corner |
| `runs/.../*-openroad-stapostpnr/<corner>/checks.rpt` | Max-slew, max-cap and max-fanout violators for that corner |

The step number in front of `openroad-stapostpnr` changes when steps are added
(55 with the default config, 56 with the final one).

### Numbers pulled for this README and the main project README

| | Single-cycle (`RUN_2026-09-08_00-57-59`) | Pipelined, final config (`RUN_2026-10-29_04-53-28`) |
|---|---|---|
| Instances (including fill and tap) | 1,081 | 1,194 |
| Instances excluding fill | 657 | 706 |
| Flip-flops | 32 | 49 |
| Std-cell area (excluding fill) | 4,918.47 µm² | 5,285.07 µm² (+7.5%) |
| Core area | 6,831.55 µm² | 7,607.30 µm² |
| Std-cell utilization of core | 72.0% | 69.5% |

Utilization is above the 50% `FP_CORE_UTIL` setting, since that is a placement
target rather than a guaranteed result. An earlier version of this README
listed 6,831.55 µm² as cell area, but that figure is the core area, which
filler cells fill completely.

**Note on KLayout's technology display:** this container's KLayout only has
`sg13g2` (IHP's separate 130nm PDK, also bundled in this image) and a generic
`default` registered as selectable viewer technologies, meaning `sky130A` isn't in
that list. Because of that, KLayout's toolbar and layer panel show raw numeric
layer pairs (e.g. `64/5`) instead of proper sky130 layer names, and the
technology selector may still display "sg13g2" regardless of the actual PDK
used. This was confirmed to be a viewer and display gap in the container's KLayout setup, and not
a flow issue. The geometry itself is confirmed to be valid sky130A output through
the LibreLane run's own DRC and LVS checks, which already validated it
against the real sky130 rule deck and standard cell library before this
screenshot was ever taken.

---

## FPGA vs. ASIC, and what changes

| | FPGA (Vivado, Artix-7) | ASIC (LibreLane, Sky130) |
|---|---|---|
| Synthesis target | LUT4/6 + flip-flops + DSP48 | Standard cells (AND/OR/FF/MUX, etc.) |
| Place & route | Vendor tool, fixed fabric grid | Free-form standard-cell P&R |
| Timing sign-off | Vivado STA (vendor SDF) | OpenSTA with RC extraction, multi-corner (PVT) |
| Output | Bitstream | GDSII (send to fab) |
| PE multiplier | LUT logic (the 8 DSP48E1s are all used by the RV32M multiplier) | Synthesized from standard cells |
| Logic resources | 14,084 LUTs (full CPU, FPGA fabric-wide) | 706 standard cells (excluding fill), 5,285.07 µm² (pe_cell alone, so not comparable since it's a full design vs. a single extracted module) |
| Result | 79 MHz (10 ns constraint, -2.730 ns WNS after 3 critical-path fixes) | Closes at 62.5 MHz (16 ns) at all nine PVT corners, +0.180 ns worst slack at slow-process/100°C, after pipelining the MAC and tuning the flow's buffering |

**Why the two numbers aren't a like-for-like comparison:** 79 MHz is the
Fmax of the whole CPU, and it is set by the CPU's branch-resolution path
(forwarding, ALU compare, mispredict flush into the I-cache), not by the
PE. On the FPGA the accelerators' 8×8 multiplies are built in LUT logic
(SYNTHESIS.md module table: the parallel MAC and systolic array use 0 DSPs,
all 8 DSP48E1s belong to the RV32M multiplier), and none of the worst FPGA
timing paths go through them. In the ASIC flow the PE's multiply-accumulate
is the entire design, so it is the critical path by definition, built from
Sky130 130nm standard cells, an older node than the 28nm Artix-7. Neither
result is wrong. They measure different things: a full CPU limited
elsewhere, and one PE limited by its own multiply-accumulate.