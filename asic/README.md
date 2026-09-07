# ASIC Flow — OpenLane 2 + Sky130 130nm

Two designs taken through the open-source ASIC flow as a complement to the FPGA
implementation in Vivado. FPGA synthesis targets a vendor-specific fabric and does
not produce standard-cell netlists, place-and-route, or GDSII — this flow does.

---

## Designs

### `alu/` — zero-risk first pass
The RV32I ALU (`src/alu.sv`). Purely combinational: 32-bit ADD/SUB/AND/OR/XOR/shifts/SLT.
No sequential state. Good first run because the RTL is trivial — any flow issue is
a tool or PDK configuration problem, not an RTL problem.

### `pe_cell/` — portfolio piece
A single output-stationary PE extracted from the 4×4 parallel MAC accelerator
(`src/pe_cell.sv`). Sequential: 8×8 multiplier feeding a 32-bit accumulator register.
This is the building block tiled 16× in the hardware accelerator. Taking it through
ASIC flow is meaningful because ML hardware teams (Tenstorrent, AMD AI engines) think
in terms of PE arrays — the GDSII and timing report for one PE is directly relatable
to a production tapeout conversation.

RTL verified standalone before OpenLane — `make sim MODULE=pe_cell` runs 6 tests
including a PDOT cross-validation against the full pipeline testbench (expected 70,
confirmed 70).

---

## Setup

### Prerequisites
- Docker Desktop (macOS or Linux)
- ~20 GB free disk (image + PDK)

### Pull the toolchain
```bash
docker pull ghcr.io/iic-jku/iic-osic-tools:latest
```

### Start the container
Run from the repo root (`rv32i-core-cpu/`):
```bash
docker run -it --rm \
  -v $(pwd):/foss/designs \
  ghcr.io/iic-jku/iic-osic-tools:latest
```

The container pre-configures `PDK_ROOT=/foss/pdks`, `OPENLANE_ROOT`, and the
`openlane` command. Your repo is mounted at `/foss/designs`.

If OpenLane asks for `--pdk-root` explicitly:
```bash
docker run -it --rm \
  -v $(pwd):/foss/designs \
  -e PDK_ROOT=/foss/pdks \
  ghcr.io/iic-jku/iic-osic-tools:latest
```

---

## Running the flow

### Step 1 — ALU (learn the tool)
```bash
cd /foss/designs
openlane asic/alu/config.json
```

### Step 2 — PE cell (the portfolio piece)
```bash
openlane asic/pe_cell/config.json
```

Results land in `runs/RUN_<timestamp>/` under each design directory.

---

## Key output files

| File | What it tells you |
|------|-------------------|
| `runs/.../final/gds/*.gds` | GDSII — open in KLayout (`klayout <file>.gds`) |
| `runs/.../final/nl/*.v` | Gate-level netlist after technology mapping |
| `runs/.../reports/signoff/25-sta-rcx_nom/*.rpt` | STA timing report — Fmax, setup/hold slack |
| `runs/.../reports/synthesis/1-synthesis.stat.rpt` | Cell count, area |
| `runs/.../reports/routing/5-antenna.rpt` | Antenna violations (should be 0) |

### Numbers to record
For the pe_cell run, note and commit:
- **Cell count** and **area** (µm²) from the synthesis stat report
- **Fmax** derived from worst negative slack: `Fmax = 1 / (period - WNS)`
- **Critical path** description from the STA report

These go in the main project README next to the Vivado numbers once the run
completes.

---

## FPGA vs. ASIC — what changes

| | FPGA (Vivado, Artix-7) | ASIC (OpenLane, Sky130) |
|---|---|---|
| Synthesis target | LUT4/6 + flip-flops + DSP48 | Standard cells (AND/OR/FF/MUX…) |
| Place & route | Vendor tool, fixed fabric grid | Free-form standard-cell P&R |
| Timing sign-off | Vivado STA (vendor SDF) | OpenSTA with RC extraction |
| Output | Bitstream | GDSII (send to fab) |
| Multiplier | DSP48E1 (hard block) | Synthesized from gates |
| Clock | 79 MHz (10 ns constraint, -2.730 ns WNS) | TBD after run |
