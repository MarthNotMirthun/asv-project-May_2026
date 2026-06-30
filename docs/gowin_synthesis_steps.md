# Gowin EDA Synthesis Checklist — top_level.v (Tang Nano 20K)

**Date:** 2026-06-30 (Week 6 Day 2)
**Goal:** Synthesize the full 9-module pipeline (`top_level.v`) for the GW2AR-18C
and confirm it fits the device with positive timing slack at 27MHz.
This is the single highest-value de-risking action remaining on the FPGA
side (TRAJECTORY.md Section 4) — resource estimates have never been
checked against real synthesis numbers until this step.

---

## 1. Project Setup (GW2AR-18C Tang Nano 20K)

1. Open Gowin EDA (IDE mode, not the standalone Programmer).
2. **File → New → FPGA Design Project.**
3. Project name: `asv_top` (or similar) — location anywhere outside `fpga/` is fine,
   or directly in `fpga/gowin_project/` if you want it tracked.
4. **Select device:** family **GW2AR-18C**, part number **GW2AR-LV18QN88C8/I7**
   (Tang Nano 20K's exact part — confirm against the Sipeed Tang Nano 20K
   datasheet if the dropdown shows multiple GW2AR-18 variants; the Tang Nano
   20K ships the `QN88` package, speed grade `C8/I7`).
5. Leave default synthesis/place&route tool selections (Gowin Synthesize,
   Gowin Place & Route) — do not switch to a third-party synthesis engine.

## 2. Add Source Files

Add ALL of the following from `fpga/src/` (and only these — confirm
`fir_test_top.v` is NOT present per FC-4):

```
fpga/src/uart_tx.v
fpga/src/adc_interface.v
fpga/src/cic_decimator.v
fpga/src/fir_filter_bank1.v
fpga/src/fir_filter_bank2.v
fpga/src/matched_filter_1.v
fpga/src/matched_filter_2.v
fpga/src/peak_detector.v
fpga/src/packet_framer.v
fpga/src/top_level.v
```

Add as **Design Files** (not simulation-only). `top_level.v` must be set as
the **top module** (right-click → Set as Top Module if Gowin doesn't infer
it automatically).

Add the constraint file:

```
fpga/constraints/top_level.cst
```

as a **Constraint File** (Project → Add File → filter to `.cst`). Do NOT
add `uart_tx.cst` or `adc_interface.cst` separately — `top_level.cst`
supersedes them for the integrated design; adding both will cause pin
assignment conflicts.

## 3. Clock Constraint (enter manually)

Gowin's `.cst` file carries pin assignments but **not** timing constraints —
those go in a separate `.sdc` (Synopsys Design Constraints) file, or can be
entered directly in the Gowin Timing Constraints Editor GUI.

- Open **Tools → Timing Constraints Editor** (or create `top_level.sdc`).
- Add a clock constraint on the 27MHz input pin (`clk`, pin 4 per
  CLAUDE.md/adc_interface.cst pin table):

```
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]
```

  `37.037ns` = 1/27MHz (CLAUDE.md target clock period — do not round to 37ns).

- If the tool prompts for additional generated/derived clocks (e.g. the
  internally-divided `adc_clk` at 3.375MHz from `adc_interface.v`), let Gowin
  auto-derive them from the source clock relationship — do not hand-enter a
  second top-level clock unless the timing report flags an unconstrained path.

## 4. Run Synthesis → Place & Route

1. Run **Synthesize** first in isolation (Process → Synthesize) and confirm
   zero errors before proceeding — warnings about unused signals are fine,
   errors are not.
2. Run **Place & Route** (Process → Place & Route).
3. Open the **Timing Report** (`*.tr` or via the IDE's Reports panel) and the
   **Resource Utilization Report** (or check the Place & Route summary pane).

## 5. Numbers to Record

Copy these into `docs/progress.md` (or paste back into this conversation)
exactly as reported — do not round or approximate:

| Metric | Where to find it | Record |
|---|---|---|
| **WNS** (Worst Negative Slack) | Timing Report, top line, `clk` clock domain | ___ ns |
| **TNS** (Total Negative Slack) | Timing Report, same section | ___ ns |
| **LUT utilization** | Resource Report — `Logic LUT` or `LUT4` row, used/total + % | ___ / 20,736 (__%) |
| **DSP / multiplier blocks** | Resource Report — `MULT` / `DSP` / `Multiplier` row | ___ / 48 |
| **BSRAM blocks** | Resource Report — `BSRAM` row | ___ / 46 |
| **Register/FF count** | Resource Report — `Register` row (sanity check only, no hard limit) | ___ |
| **Max clock frequency achieved** (Fmax) | Timing Report, derived from WNS vs. 37.037ns target | ___ MHz |

## 6. Pass / Fail Criteria

| Metric | PASS | FAIL → action |
|---|---|---|
| **WNS** | **≥ 0 ns** (zero or positive slack) | See Section 7 below — do not proceed to bitstream/flash |
| **LUT utilization** | < 90% of 20,736 (comfortable margin; CLAUDE.md estimate was a small fraction of total) | If >90%, flag — likely a synthesis inference problem (e.g. unintended full unrolling of a MAC loop), not a true resource shortage given the design's small estimated footprint |
| **DSP/multiplier blocks** | ≤ 48, and consistent with the ~4 of 48 estimate in CLAUDE.md (1 each for FIR bank1/bank2, 1 each for matched_filter_1/2 — confirm sequential MAC inference did NOT get fully unrolled into more multipliers than expected) | If significantly >4-6, the sequential MAC pattern may not have inferred as intended — flag for fpga-verilog-engineer review before proceeding |
| **BSRAM blocks** | ≤ 46, and consistent with the ~14/46 (~30%) estimate in CLAUDE.md (validated Jun 29 — depth-bound 4-array matched filter architecture) | If significantly higher, the reference-chirp/window-buffer arrays may not be inferring as BSRAM (check for accidental distributed-RAM inference) |
| **Synthesis/P&R errors** | Zero | Any error blocks the run entirely — fix before re-running, do not skip |

**If ALL pass:** Week 6 Day 2 exit criterion (TRAJECTORY.md) is met —
`top_level.v synthesizes with positive timing slack`. Proceed to generate
the bitstream (Process → Place & Route → Generate Bitstream, or it may auto-
generate after P&R) for the eventual hardware flash step (deferred until
Layer A/B bench checks per the Week 6 plan — do not flash to hardware yet
unless you are specifically doing a synthesis-only smoke test).

## 7. If WNS Is Negative (timing failure)

Negative WNS means at least one path can't complete within 37.037ns at 27MHz.
Do NOT ignore this or try to "push through" to bitstream generation — a
negative-slack design can behave correctly in simulation but glitch or
produce wrong data on real hardware, and failures are intermittent/hard to
debug post-hoc.

1. **Identify the critical path.** In the Timing Report, find the path with
   the most negative slack — it lists the start register, end register, and
   every logic level/net in between with its delay contribution.
2. **Localize which module owns it.** Cross-reference the register names
   against `fpga/src/*.v` — the signal naming should make the owning module
   obvious (e.g. `matched_filter_1_*`, `cic_decimator_*`).
3. **Likely culprits given this design (check these first):**
   - **Matched filter accumulator** (`matched_filter_1.v` / `_2.v`): the
     48-bit accumulator with a 2109-tap window is the deepest arithmetic
     chain in the design. If untimed, this is the most probable offender.
   - **CIC decimator** integrator/comb chain: less likely (already pipelined
     per FC requirements) but check if WNS traces here.
   - **FIR sequential MAC**: 32-tap sequential MAC should be well within
     budget at 1 MAC/clock — if this is the critical path, something is
     wrong with the pipelining, not just timing margin.
4. **Standard fixes, in order of preference:**
   - Add a pipeline register (one more `<=` stage) to break the longest
     combinational chain — this is almost always correct per CLAUDE.md's
     "Pipeline ALL multiply-accumulate chains — never combinational MAC"
     rule; if a path is failing timing, it's a sign a chain wasn't fully
     pipelined.
   - Check for an accidentally-combinational comparison/mux feeding directly
     into a multiplier or wide adder — register the inputs.
   - As a last resort only (changes system behavior, needs re-verification
     and a CLAUDE.md update): reduce the target clock frequency. This is
     NOT preferred — 27MHz is the onboard oscillator and all sample-rate
     math (FC-3's 421,875 Hz) derives from it.
5. **After any RTL fix:** re-run `verilog-sim-runner` on the affected
   module(s) before re-synthesizing — a timing fix that breaks functional
   correctness is worse than the original timing failure.
6. **Re-run Place & Route** and re-check WNS. Repeat until WNS ≥ 0.
7. **Do not let a timing failure carry past today (Jun 30).** Per
   TRAJECTORY.md: "A synthesis failure found Week 6 is solvable; found
   Week 7 or later is a crisis." If a fix isn't obvious within a couple of
   hours, stop and report back with the specific failing path details
   (module, signal names, slack amount) rather than guessing further.

---

## Reference

- Target device: GW2AR-18C (GW2AR-LV18QN88C8/I7), Tang Nano 20K
- Target clock: 27MHz onboard oscillator, period 37.037ns (CLAUDE.md)
- Resource budget (CLAUDE.md, pre-synthesis estimates — this run produces the first real numbers):
  - ~4 of 48 HW multipliers (1 each: FIR bank1, FIR bank2, matched_filter_1, matched_filter_2)
  - ~14 of 46 BSRAM blocks (~30%) — validated Jun 29, depth-bound 4-array matched filter architecture
  - LUT4s: 20,736 total, small fraction expected used
- Constraint file format: `.cst` ONLY (Gowin proprietary) — never `.xdc`/`.ucf`
- `fir_test_top.v` must be confirmed absent from `fpga/src/` before this run (FC-4 — last verified absent Jun 16)
