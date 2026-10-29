# Black Hole Renderer on the RV32IM Core

> *"If you gaze long into an abyss, the abyss also gazes into you."*
> — Friedrich Nietzsche

A general-relativity ray tracer written in RISC-V assembly and run on this repo's 5-stage pipelined CPU (in simulation, through the real UART). It renders a 64×64 image of a non-spinning (Schwarzschild) black hole in front of a checkerboard sky.

![black hole rendered by the CPU](out/blackhole_cpu.png)

## Why I built this

Black holes have been an interesting topic to me since I was a child, and the more TED-Ed, Kurzgesagt, and other relevant YouTube videos I watched, the more it fascinated me that such a celestial object could exist. The mysteries and physics that black holes contain have been an exciting topic to not just me but countless people. When I first made the core, I thought about making sure it would work in the real world. The ASIC project showed me the physical side of one piece of it, so all that was left was to prove that the core could handle software and computation. What better way to satisfy my excitement for a certain celestial object, and to find out whether the core could handle computation, than with a black hole ray tracer? While the limits of the core kept me from a high-resolution, fully accurate render, I learned a very valuable skill of working under constraints.

Every time an identified constraint prevented me from fully realizing my dream of a realistic black hole, it only furthered my resolve to get a black hole running. Whether it was the lack of memory, the lack of a floating point ISA, or the lack of trig on the core, it only made my brain think, "How could I get this to work under this limitation?" That led to ideas such as radial symmetry to limit the number of rays I needed to handle, and a deep rabbit hole into CORDIC that allowed me to compute sin and cos with integer math. I hope that as I learn more, individually and on a professional team, I can improve this project and one day run the accurate black hole of my dreams on my own CPU.

## What it computes

In units where G = c = M = 1 (event horizon at r = 2), a light ray near the black hole stays in a plane and obeys the photon orbit equation

```
u'' = 3u² − u        u = 1/r,  ' = d/dφ
```

For each pixel, the program fires a ray from a camera at r = 30 and integrates that equation until the ray either falls through the horizon (black pixel) or escapes to r > 1000. An escaped ray's final direction says which checker square of the sky it sees. Rays bent by more than 90° see the sky behind the camera (gray).

The image shows:
- **The shadow**: the black disk. GR predicts its edge from the critical impact parameter b = 3√3 M; with this camera that's 20.03 half-pixels from the center, and the renderer's edge lands on exactly that table entry.
- **The photon ring**: just outside the shadow, light that went most of the way around the black hole. The whole sky gets squeezed into a thin band here, which is why it looks noisy at 64×64.
- **Lensed squares**: further out, straight checker lines bend into arcs.

## How it fits on a small integer CPU

| Constraint | How the program handles it |
|------------|----------------------------|
| No floating point | Q8.24 fixed point. A multiply is `mul` + `mulh` + 3 shifts/ors. |
| 1 KB of data memory | All pixels at the same distance from the center follow the same (rotated) path, so it traces 89 rays once and stores a 712-byte table, instead of 4,096 rays. |
| No trig instructions | The integration step is h = 2⁻¹⁰ rad, so "× h" is a shift. Sine and cosine of each ray's final angle come from CORDIC (shift-and-add). |
| 1 KB of instruction memory | The whole program is 228 instructions. |

The integrator is leapfrog (second order, energy-conserving), the same family used in orbital mechanics codes.

## Measured on the core

From the hardware performance counters during the full render (`make`):

| Metric | Value |
|--------|-------|
| Cycles | 5,468,472 (≈ 69 ms at the core's 79 MHz) |
| Instructions retired | 4,039,097 |
| CPI | 1.354 |
| Branch mispredicts | 2.63% of 900,016 branches |
| D-cache misses | 51 (the whole table fits in cache) |
| I-cache misses | 58 (the whole program fits in cache) |

About 84% of the cycles go to tracing the 89 rays; shading and sending 4,096 pixels takes the rest. On a real board the UART would dominate: 4,096 bytes at 115200 baud is about 0.36 s.

## Bug it found in the CPU

The first run failed the bit-exact check: every ray inside the shadow came back as "escaped", and 2,240 of the 4,096 pixels (55%) differed from the reference. The cause was in the core, not the program. A DIV instruction returned the *previous* division's result, because the divider didn't stall the pipeline in the cycle it started. No earlier program divided, and the divider's unit test checked it in isolation. The divider's `busy` was only high in `RUNNING`, so in the cycle a divide reached EX (state still `IDLE`) the pipeline advanced and EX/MEM captured the old quotient. The fix is one line in [`src/mul_div_unit.sv`](../src/mul_div_unit.sv), plus a new pipeline-level test, [`tb/tb_div_pipeline.sv`](../tb/tb_div_pipeline.sv), which failed 7 of its 12 checks before the fix. See commit [69fa49f](https://github.com/abishekmatevannan-afk/riscv-rv32im-gemm/commit/69fa49f).

## Verification

1. **Bit-exact:** `blackhole_ref.py` is a Python copy of the exact fixed-point algorithm (same rounding, same RISC-V `div`/`rem` behavior). The 4,096 bytes received from the CPU's UART must match it exactly. A mismatch would mean a bug in the CPU or the assembler.
2. **Physics:** the shadow edge must land where GR predicts (above).
3. **Precision:** the fixed-point image vs. the same physics in float64 with a fine RK4 integrator differs on 1.37% of pixels, all in the photon ring and on checker edges.

## Run it

```bash
cd blackhole
make          # assemble, build expected image, simulate the CPU, write out/*.png
make test     # assembler self-test
```

Requires Icarus Verilog and Python 3 (standard library only).

## Files

| File | What |
|------|------|
| `blackhole.s` | The ray tracer, RISC-V assembly |
| `rvasm.py` | Two-pass RV32IM assembler (labels, `.equ`, common pseudo-ops), self-tested against encodings from this repo |
| `blackhole_ref.py` | Bit-exact fixed-point model, float64 reference, physics check, PNG writer |
| `tb_blackhole.sv` | Runs the CPU, receives the image over UART, compares it with the model |
