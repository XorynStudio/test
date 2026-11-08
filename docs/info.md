<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

`tt_um_xorynstudios_chimera` is a gate-level silicon proof-of-concept slice of the **CHIMERA-1 Unified Elastic CPU/GPU Architecture** developed at Xoryn Studio.

Rather than partitioning silicon into separate scalar CPU cores and GPU shader units speaking incompatible instruction sets, a CHIMERA core unifies both roles into a single morphing execution pipeline backed by a reconfigurable multi-bank **Liquid SRAM** array:

1. **Single-Cycle Hardware Mode Morphing (`ui[3] / MORPH_WAVE_EN`):**
   * When `MORPH_WAVE_EN = 0` (**`FUSE` CPU Mode**), the core executes low-latency scalar integer and control operations on the active register window.
   * When `MORPH_WAVE_EN = 1` (**`WAVE` GPU Mode**), the core locks into wavefront execution mode (`uio[6] / MODE_GPU_ACT = 1`), enabling hardware graphics primitives and zero-cycle memory stall hiding.
2. **4-Bank Liquid SRAM & Zero-Cycle Wavefront Switching (`ui[4] / L1_MISS_SWAP`):**
   * On-chip storage is organized into 4 hardware Wavefront Register Banks (`W0`–`W3`, 4 × 8-bit registers per bank).
   * In `WAVE` GPU mode, asserting `L1_MISS_SWAP = 1` simulates an L1 texture/data cache miss: the hardware bank multiplexer rotates `active_wave_q` (`uio[5:4]`) to the next ready wavefront in **zero stall cycles**, keeping the ALU pipeline 100% utilized while background memory fetches complete.
3. **Unified ALU, FMA, 2D Morton Swizzler & Z-Buffer ROP (`ui[2:0] / OPCODE`):**
   * `000` (`MOVI`): Loads 4-bit immediate (`uio[3:0]`) + wavefront offset into the selected register (`ui[6:5]`).
   * `001` (`VADD`): Adds `op_a + op_b` and commits to the active Liquid SRAM bank.
   * `010` (`VSUB`): Subtracts `op_a - op_b` and commits to the active Liquid SRAM bank.
   * `011` (`VFMA`): Hardware Fused Multiply-Add (`(op_a[3:0] * imm_data) + op_c`).
   * `100` (`VDOT2`): 2D Vector Dot-Product (`(op_a * op_b) + (op_c * imm_data)`).
   * `101` (`TEX2D / MORTON`): Hardware 2D Morton Z-Order address encoder—interleaves `X[3:0]` and `Y[3:0]` coordinates into a single 8-bit spatial cache address on `uo[7:0]`.
   * `110` (`ROP.ZWRITE`): Hardware Z-Buffer Depth Test—compares fragment depth `op_a` against the on-chip `z_buffer_q` register (`op_a < z_buffer_q`). If closer, updates `z_buffer_q`, asserts `ROP_Z_PASS` (`uio[7] = 1`), and outputs the shaded pixel color `op_b` on `uo[7:0]`.
   * `111` (`SOLO.JOIN`): Clears the Z-buffer to `0xFF` (far plane) and collapses the core back into scalar `FUSE` CPU mode.

## How to test

1. **Reset & Initialization:** Drive `rst_n = 0` for at least 2 clock cycles, then release `rst_n = 1` with `ena = 1`. Verify that `uo[7:0] = 0x00` and `uio[7:4] = 0b0000` (CPU Mode, Wavefront `W0`).
2. **Load Registers in CPU Mode (`MOVI`):**
   * Set `ui[2:0] = 3'b000` (`MOVI`), `ui[3] = 0` (`FUSE` mode), `ui[6:5] = 2'b00` (`R0`), `uio[3:0] = 4'h5`, and pulse `ui[7]` (`EXEC_STROBE = 1`). `uo[7:0]` will output `0x05`.
   * Set `ui[6:5] = 2'b01` (`R1`), `uio[3:0] = 4'h3`, and pulse `EXEC_STROBE = 1`.
3. **Morph to GPU Wavefront Mode & Test 2D Morton Swizzle (`TEX2D`):**
   * Set `ui[3] = 1` (`MORPH_WAVE_EN = 1`), `ui[2:0] = 3'b101` (`MORTON`), `ui[6:5] = 2'b00`. On the next clock edge, `uio[6]` (`MODE_GPU_ACT`) goes high and `uo[7:0]` outputs the bit-interleaved 2D Morton Z-order address (`0x1F`) of `R0` (`X=5`) and `R1` (`Y=3`).
4. **Verify Zero-Cycle Wavefront Bank Switching:**
   * While in GPU mode (`ui[3] = 1`), assert `ui[4] = 1` (`L1_MISS_SWAP`). Observe `uio[5:4]` (`WAVE_ID`) increment (`00 -> 01 -> 10 -> 11`) on every clock cycle with zero pipeline bubble cycles.
5. **Verify Hardware Z-Buffer Depth Test (`ROP.ZWRITE`):**
   * Execute `opcode = 3'b110` (`ROP.ZWRITE`). Since `R0 = 0x05` is less than the initial far-plane Z-buffer (`0xFF`), `uio[7]` (`ROP_Z_PASS`) asserts high (`1`) and `uo[7:0]` commits the pixel color in `R1`.

## External hardware

No external PMODs are strictly required—all instructions, mode morphing signals, and telemetry outputs can be driven and inspected directly by the onboard RP2040 microcontroller on the Tiny Tapeout carrier board or observed via a logic analyzer / 7-segment display on `uo[7:0]`.
