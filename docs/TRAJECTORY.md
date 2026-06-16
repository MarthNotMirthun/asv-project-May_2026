# TRAJECTORY.md — ASV Technical Compass

**Last Updated:** June 15, 2026 (Week 4 Day 1 of 11)

This is the living technical compass for the GPS-denied acoustic-homing
catamaran USV. It records the **verified pipeline state**, the
**forward constraints every future agent must respect**, and the
**physical verification queue** that must clear before first hardware
power-on. If you are an agent touching the FPGA pipeline, read the
FORWARD CONSTRAINTS section before writing a single line.

For full project context, hardware contracts, and locked decisions, see
`CLAUDE.md`. This document does not duplicate that — it captures the
cross-module reality that CLAUDE.md's status table cannot express.

---

## 1. PIPELINE STATUS (verified as of June 13, 2026)

Signal flow (the ONLY valid build order):

```
AD9226 → adc_interface → cic_decimator → FIR banks → matched filters → peak detector/TOF → uart_tx
```

| Module | Status | Verification notes |
|---|---|---|
| `uart_tx` | ✅ DONE & verified | 8-byte back-to-back packet verified in sim; .cst written and verified |
| `adc_interface` | ✅ DONE & verified | MSB-flip applied, OTR port added, signed declaration; all 14 pins LVCMOS33-compatible (.cst verified) |
| `cic_decimator` | ✅ DONE & verified | R=8, N=3, shift=5 corrected, saturation clamp added |
| `fir_filter_bank1` (34–38 kHz) | ✅ DONE & verified | 32-tap Hamming windowed-sinc, signed-16 integer scale |
| `fir_filter_bank2` (42–46 kHz) | ✅ DONE & verified | 32-tap Hamming windowed-sinc, signed-16 integer scale |
| `matched_filter` ×2 | ⏳ NOT STARTED | **NOW THE CRITICAL PATH** — see Section 4 |
| `peak_detector` + TOF | ⏳ NOT STARTED | Depends on matched filter |
| Full pipeline integration | ⏳ NOT STARTED | Blocked on the above |

**Status as of June 16:** All five completed modules passed
hw-validation, dsp-signal-validator, systems-integrator, and
verilog-sim-runner on June 13. FC-5 and FC-6 (added June 15) are
**confirmed and resolved** — the system uses SNR-gradient homing, not
absolute ToF range. `peak_detector.v` outputs `corr_peak`/`snr` as
primary; `peak_lag` kept as diagnostic only. `acoustic_homing_node`
homes by gradient ascent on `/acoustic/corr_snr`. ARRIVED trigger uses
SNR plateau threshold (CQ-1, empirical at pool test #1). **Proceed to
matched filter implementation immediately.**

---

## 2. FORWARD CONSTRAINTS (mandatory — all future agents must respect)

These are non-negotiable contracts produced by verified work upstream.
Violating one will silently break the pipeline. Each is labeled `FC-#`
so other documents and agents can cite it.

### FC-1 — Coefficient & sample format is signed-16 INTEGER, NOT Q1.15
Reference chirps and FIR coefficients use **signed-16 integer scale**.
This was a deliberate correction from the original Q1.15 spec in
CLAUDE.md's coding standards. **Every** module that consumes FIR output
or feeds matched filter input must operate in integer scale. Do not
reintroduce Q1.15 scaling at any stage boundary downstream of the FIR banks.

### FC-2 — OTR (over-range) must propagate end-to-end
Every pipeline stage from `adc_interface` onward must carry
`otr_in` / `otr_out` ports. The over-range flag must travel the full
chain to `uart_tx` so the Pi can flag saturated readings in the packet.
A new module without OTR ports is incomplete by definition.

### FC-3 — TOF math uses exactly 421,875 samples/sec
Time-of-flight and range calculations must use the **exact** post-CIC
output rate: `27,000,000 / 8 / 8 = 421,875 Hz`. Do not use the "422 kSPS"
or "400 kSPS" approximations from earlier design notes. Range =
(peak_position / 421,875) × 343 m/s ÷ 2.

### FC-4 — `fir_test_top.v` must be deleted before integration
`fir_test_top.v` is a timing-wrapper artifact created to exercise the FIR
banks in isolation. It must **not** appear in the synthesis file list for
the full pipeline. Delete it before integration to avoid pulling a stray
top module into the build.

### FC-5 — Ranging Method Correction: NO absolute one-way ToF; peak_detector outputs CORRELATION LAG + SNR, not range
**This supersedes the `÷ 2` round-trip interpretation in FC-3.**

**What was assumed (wrong):** FC-3's `Range = (peak_position / 421,875)
× 343 ÷ 2` treats the correlation peak position as an absolute time-of-
flight. The `÷ 2` implies a round-trip (echo) ranging like the JSN-SR04T
sonar. That model does not match this system at all.

**What we actually have:**
- Buoys (ESP32 #2) transmit LFM chirps **autonomously and continuously**.
  There is NO trigger, echo, or transponder relationship with the vehicle.
- The vehicle has **no shared time reference** with the buoy: GPS-denied,
  no radio time-sync, no wired link. The vehicle therefore does NOT know
  `T_transmit`, so it cannot compute `T_receive − T_transmit`.
- **Absolute one-way ToF is impossible** with this hardware. The missing
  ingredient is a common clock / known transmit epoch. Nothing in the BOM
  provides it. (Two-way ToF is also impossible — the vehicle does not
  transmit and the buoy does not echo. The `÷ 2` has no physical meaning.)

**What the matched filter peak actually IS:** the correlation peak gives
the **sample lag within the 800-sample window at which the received chirp
best aligns with the stored reference**, plus the **peak magnitude
(correlation energy → SNR)**. The lag is a *relative arrival phase within
the free-running capture window*, NOT an absolute distance. Because buoy
and vehicle clocks are unsynchronized and free-running, the absolute lag
drifts and wraps; it cannot be anchored to a true `T_transmit`.

**Correct interpretation — what `peak_detector.v` must output:**
- `corr_peak` (peak magnitude, 16-bit) — the primary navigation signal.
- `snr` (peak-to-sidelobe / peak-to-noise ratio, 8-bit) — detection &
  proximity proxy. **Monotonic with proximity**: closer buoy → higher
  received SPL → higher correlation energy. THIS is the homing gradient.
- `peak_lag` (sample index, optional) — keep it in the packet as a
  diagnostic and as the hook for a future V2 TDOA dual-receiver bearing
  upgrade, but **do not convert it to meters** and do not gate any
  state transition on it in V1.
- `target_id` and over-range (per FC-2) still propagate.

**FPGA pipeline impact: NONE structural.** The matched filter correlator
and peak detector are still built exactly as planned (800-sample BSRAM
correlation, integer-scale reference per FC-1, OTR per FC-2, 421,875 Hz
per FC-3 for any lag-to-time diagnostic). Only the *meaning and labeling*
of the peak_detector output changes — `corr_peak`/`snr` are first-class,
`range_cm` becomes a diagnostic-only / deprecated field. Build the DSP;
do not redesign it.

### FC-6 — `acoustic_homing_node` Architecture Correction: SNR-gradient homing, not range homing
**The state machine still works**, because every transition in CLAUDE.md
can be driven by correlation SNR and bearing — none strictly requires
absolute range. Required modifications:

- **SCANNING:** rotate 360°, log `snr(θ)` per heading. Lock onto the
  bearing `θ*` that maximizes SNR for the active `target_id` band
  (Bank 1 for Buoy 1, Bank 2 for Buoy 2). *Unchanged in intent.*
- **ACQUIRING:** confirm SNR exceeds the lock threshold for N consecutive
  readings at `θ*` (rejects multipath: pool-wall reflections sit ~20–30%
  below the direct-path peak, so set the lock threshold above that floor).
- **HOMING:** drive forward on heading `θ*`; run **gradient ascent on
  SNR** instead of PID-on-range. Differential thrust corrects heading to
  keep SNR climbing; SNR rising ⇒ closing, SNR falling ⇒ steer back.
  EKF dead-reckoning still smooths between pings.
- **ARRIVED (trigger MUST change):** the `range < 0.4 m for 3 readings`
  test is no longer computable. Replace with a **near-field SNR plateau /
  saturation** trigger: SNR exceeds a high "very-close" threshold (and/or
  the correlation peak saturates / OTR asserts from high SPL) for 3
  consecutive readings. Calibrate the threshold value empirically at
  pool test #1 by recording SNR-vs-distance at known ranges. A short
  forward-creep timeout after plateau can confirm contact.

**ROS 2 topic change:** `/acoustic/range_m` (Float32) is misleading and
should be **renamed `/acoustic/corr_snr` (Float32, 20 Hz)** carrying the
SNR/correlation-strength metric. `fpga_uart_node` parses the same 8-byte
packet; the `range_cm` bytes may be republished as a diagnostic-only
`/acoustic/peak_lag` (do NOT label it meters). `acoustic_homing_node`
subscribes to `/acoustic/corr_snr` (+ `/odometry/filtered`) and publishes
`/cmd_vel` as before. The 8-byte UART packet format is **unchanged** —
only the Pi-side interpretation of the two `range_cm` bytes changes.

**Executive summary:** The `÷ 2` absolute-range model in FC-3 is
physically impossible for this hardware — buoy and vehicle share no time
reference, so neither one-way nor two-way ToF can be measured; the
matched filter peak is a correlation *lag + magnitude*, not a distance.
**What changes:** `peak_detector.v` is documented to output `corr_peak`/
`snr` as primary (lag kept as diagnostic only); `acoustic_homing_node`
homes by gradient ascent on SNR with an SNR-plateau ARRIVED trigger; the
ROS topic is renamed `/acoustic/corr_snr`. **What stays the same:** the
entire FPGA pipeline — ADC → CIC → FIR → matched filter → peak detector →
UART — is built exactly as planned (FC-1, FC-2, FC-3's 421,875 Hz, FC-4
all still hold), the 8-byte packet is unchanged, and the state machine
keeps its SCAN→ACQUIRE→HOME→ARRIVE shape. **August 10 demo: still
achievable** — SNR-gradient homing to ~0.4 m is actually *simpler* and
more robust than range-PID, requires zero new hardware, and removes the
impossible synchronization dependency. The only added cost is one
empirical SNR-threshold calibration during pool test #1.

---

## 3. PHYSICAL VERIFICATION QUEUE (before first hardware power-on)

These are multimeter/strap checks on the AD9226 board. They are not
optional — getting any one wrong can destroy the FPGA GPIO or produce
silently wrong data. Complete ALL before applying power to a wired ADC.

| # | Check | Required reading | Why it matters |
|---|---|---|---|
| PV-1 | AD9226 DRVDD rail | **3.3V** (not 5V) | DRVDD sets the D[11:0]/OTR output swing. 5V would exceed Tang Nano 20K LVCMOS33 GPIO and risk damage |
| PV-2 | DFS pin strap | tied to **AVSS** (ground), not AVDD | Determines offset-binary vs two's-complement output. Software MSB-flip is only correct for DFS=AVSS |
| PV-3 | OEB pin | tied **LOW** | If HIGH, D[11:0] outputs are tristated — FPGA reads garbage/floating |

---

## 4. CRITICAL PATH — Matched Filter Correlators ×2

The two matched filter correlators are now the single most important and
most time-sensitive deliverable. They are the centerpiece DSP that the
project is judged on. **Week 4 must start them immediately.**

Requirements (each inherits the forward constraints above):
- **2109-sample reference chirps in BSRAM** (5 ms × 421,875 SPS = 2109 samples per channel); correlation window slides over incoming samples
- **Reference chirps in signed-16 integer scale** (per **FC-1**)
- **`otr_in` / `otr_out` ports** carried through (per **FC-2**)
- `corr_peak` (32-bit magnitude) and `snr` (8-bit peak-to-noise) are primary outputs; `peak_lag` kept as diagnostic (per **FC-5**)
- `peak_lag` uses **421,875 Hz** sample clock for any lag-to-time diagnostic (per **FC-3**); do NOT convert to range_cm
- Pipeline all multiply-accumulate chains — never combinational MAC
- Companion testbench in `fpga/sim/`; simulate with iverilog, check for X/Z

### Schedule reality
Two weeks of carryover already exist. Weeks 3–6 are reserved as
FPGA-focused. ROS 2 work stays deferred until the FPGA pipeline is done.
The matched filter is the hardest block in the project — if it slips,
the demo slips. Protect this time above all else.

---

## 5. HOW TO USE THIS DOCUMENT

- **Before writing any new pipeline module:** read Section 2 (FC-1..FC-6) and apply every one.
- **Before any hardware power-on:** clear Section 3 (PV-1..PV-3).
- **When a module is verified:** update Section 1's table and add any new forward constraint it produces as the next `FC-#`.
- **When the critical path moves:** update Section 4 to point at the new hardest, most time-sensitive block.

This file is the source of truth for cross-module contracts. Keep it current.

---

## 6. CALIBRATION QUEUE (empirical — cannot be simulated)

These values must be measured at the pool venue with `rosbag2 record -a`. They cannot be computed in advance because they depend on buoy SPL, MAX9814 gain setting, and acoustic path loss at the specific venue.

| # | Item | What to measure | When |
|---|---|---|---|
| CQ-1 | SNR plateau / saturation threshold for ARRIVED state | Walk vehicle manually toward Buoy 1 at measured distances (0.1 m, 0.2 m, 0.4 m, 0.6 m, 1.0 m, 2.0 m). Record `/acoustic/corr_snr` at each distance. Identify the `corr_snr` value where readings plateau or OTR asserts — this is `SNR_ARRIVED_THRESHOLD`. Hard-code into `acoustic_homing_node` before pool test #2. | Pool test #1 (Week 9, Jul 20–26) |

**How to use CQ-1:** After pool test #1 bag capture, extract `/acoustic/corr_snr` from the bag, plot vs distance, and identify the near-field plateau knee. Set `SNR_ARRIVED_THRESHOLD` in `acoustic_homing_node` to 90% of the plateau value to give a margin before OTR saturation.
