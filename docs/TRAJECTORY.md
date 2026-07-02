# TRAJECTORY.md — ASV Technical Compass

**Last Updated:** July 1, 2026 (Week 6 Day 3 — FPGA 10/10 pipeline modules verified, uart_rx.v RTL complete, 6 ROS 2 nodes built, 40 days to August 10 demo)

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

## 1. PIPELINE STATUS (verified as of July 1, 2026)

Signal flow (the ONLY valid build order):

```
AD9226 → adc_interface → cic_decimator → FIR banks → matched filters → peak detector/TOF → uart_tx
```

| Module | Status | Verification notes |
|---|---|---|
| `uart_tx` | ✅ DONE & verified | 8-byte back-to-back packet verified in sim; .cst written and verified |
| `adc_interface` | ✅ DONE & verified | MSB-flip applied, OTR port added, signed declaration; all 14 pins LVCMOS33-compatible (.cst verified) |
| `cic_decimator` | ✅ DONE & verified | R=8, N=3, shift=5 corrected, saturation clamp added |
| `fir_filter_bank1` | ✅ DONE & verified | 38.5–41.5 kHz per FC-7; 32-tap Hamming windowed-sinc coefficients; passband ripple <1dB; stopband confirmed; RTL unchanged ← VALIDATED Jun 18 |
| `fir_filter_bank2` | ✅ DONE & verified | 38.5–41.5 kHz per FC-7 (identical coefficients to bank1); code-division beacon ID via sweep direction; RTL unchanged ← VALIDATED Jun 18 |
| `matched_filter_1` (Buoy 1 = UP-sweep) | ✅ RTL verified — NEW REFERENCE DATA (FC-7) | 2109-sample block correlator, 48-bit acc, CORR_SHIFT=16, OTR window-OR, 200Hz out ← VALIDATED Jun 16. RTL UNCHANGED; load UP-sweep 38.5→41.5 kHz reference over UART |
| `matched_filter_2` (Buoy 2 = DOWN-sweep) | ✅ RTL verified — NEW REFERENCE DATA (FC-7) | Same architecture ← VALIDATED Jun 16. RTL UNCHANGED; load DOWN-sweep 41.5→38.5 kHz reference over UART |
| `peak_detector` | ✅ DONE & verified | Dual-channel RELATIVE gating (abs → ratio `\|ch1\|>(\|ch2\|<<K_SHIFT)` AND `\|ch_n\|>FLOOR`) per FC-7; SNR proxy (8-bit), corr_peak (32-bit magnitude), peak_lag diagnostic (11-bit); 12/12 sim checks ALL PASS ← VALIDATED Jun 17 |
| `packet_framer` | ✅ DONE & verified | 8-byte FSM [target_id][peak_lag_H/L][corr_peak_H/L][snr][XOR checksum][0xFF], tx_busy gating between peak_detector and uart_tx; 12/12 sim checks ALL PASS ← VALIDATED Jun 17 |
| `uart_rx` (config + ref-chirp load) | ✅ RTL + sim DONE (Jul 1), pin assignment UNVERIFIED | 4-byte frame [addr_hi][addr_lo][data_hi][data_lo], CLKS_PER_BIT=234, 2-FF synchronizer, glitch rejection. Address-map convention in header (0x0000-0x0001=FLOOR, 0x0002=K_SHIFT, 0x0003=SNR_SHIFT, 0x1000-0x183C=ch1 ref, 0x2000-0x283C=ch2 ref). Config-register consumer module + matched-filter load-gate still deferred (documented in uart_rx.v header). Pin 87 candidate, flagged unverified — hw-validation physical check pending. |
| Full pipeline integration (top_level.v) | ✅ Synthesized & validated (Jun 29–30) | All 10 modules chained: AD9226 → adc_interface → CIC → FIR ×2 → matched_filter ×2 → peak_detector → packet_framer → uart_tx → (uart_rx inbound). Synthesis: +28.6ns setup slack, +0.3ns hold slack, 4% LUTs, 3% registers, 9% DSP. |

**Status as of July 1, 2026:** All TEN FPGA pipeline modules now VERIFIED and SIM-PASSING (9 synthesized, 1 new):
- **Outbound core pipeline (9):** ADC interface ✅ → CIC decimator ✅ → FIR banks ✅ → matched filters ✅ → peak detector ✅ → packet framer ✅ → UART TX ✅
- **Integration & synthesis (top_level.v):** All 9 chained end-to-end, synthesized Jun 29–30 with POSITIVE timing slack (+28.6ns setup, +0.3ns hold at 27MHz). 0 errors, 0 warnings. Resource utilization: 4% LUTs, 3% registers, 9% DSP.
- **Inbound config path (uart_rx.v):** New 4-byte frame protocol completed Jul 1, RTL + testbench sim-verified, pin assignment flagged for hw-validation physical check before wiring. Deferred config-register consumer module and matched-filter load-gate documented.
- **ROS 2 ecosystem (6 of 7 nodes):** motor_driver, collision_safety, dead_reckoning (EKF), acoustic_homing (state machine), mission_state_machine, telemetry all built Jul 1. 1 node remaining (fpga_uart_node, UART parser) not blocking hardware assembly. Wiring architecture corrected to defense-in-depth gating.
- **ESP32 firmware pre-existing:** vehicle_firmware.ino and buoy_firmware.ino built Jun 29 (pre-existing, now documented). Unflashed, untested. Ready for bench bring-up Week 6 Jul 3-5.

**Critical next step: Hardware bring-up & bench validation.** All FPGA code is synthesized and timing-verified. All ROS 2 software is written. Remaining tasks are physical: hull fabrication (PVC cut/fit), Layer A acoustic path verification (38.5–41.5 kHz scope check), ESP32 firmware flashing + motor control validation.

**Architecture frozen (FC-5/FC-6/FC-7/FC-8):**
- FC-5: SNR-gradient homing (not absolute range); `peak_detector` outputs `corr_peak`/`snr` as primary, `peak_lag` kept diagnostic only.
- FC-6: `acoustic_homing_node` homes by gradient ascent on SNR, ARRIVED trigger = SNR plateau/saturation (not 0.4 m range).
- FC-7: Code-division beacon ID (Buoy 1 = UP-sweep 38.5→41.5 kHz, Buoy 2 = DOWN-sweep 41.5→38.5 kHz, both in same 3 kHz transducer passband). Relative gating with UART-loadable K_SHIFT and FLOOR.
- FC-8: Egress maneuver required after each ARRIVED state to prevent cross-talk blinding at 1–2 m distance.

**Resource accounting note (Jun 16):** BSRAM usage was corrected upward
from 8/46 to **14/46 (~30%)** after manual verification against the
GW2AR-18 BSRAM primitive (UG285E): the 2109-sample arrays are
**depth-bound (1024 locations/block → 3 blocks/array), not
capacity-bound**. This correction was found by manual datasheet check,
not by trusting the pipeline's first answer. See Q1 audit note below
re: re-verifying remaining LUT/multiplier estimates the same way.

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

### FC-4 — `fir_test_top.v` must be deleted before integration — ✅ CLEARED (Jun 15)
`fir_test_top.v` was a timing-wrapper artifact created to exercise the FIR
banks in isolation. It is **confirmed absent from fpga/src/** as of Jun 15
(verified again Jun 16 — fpga/src/ contains exactly the 7 pipeline modules
and no test_top). This constraint is satisfied; retain the note for
history but it no longer gates integration.

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

### FC-7 — Beacon-ID is by CHIRP SWEEP DIRECTION (up vs down), NOT by frequency band. Both buoys share the 38.5–41.5 kHz transducer passband.
**This supersedes the two-band (34–38 / 42–46 kHz) beacon architecture in
CLAUDE.md. Resolves BLOCKER B1 (DL-1 addendum). PEAK_DETECTOR IS BLOCKED
until the new chirp specs below are accepted by the owner.**

**Confirmed hardware constraint:** the TCT40-16T/R are high-Q narrowband
resonant piezo transducers, efficient ONLY within ~**38.5–41.5 kHz**
(±1.5 kHz around 40 kHz resonance) — a usable passband of only ~3 kHz.
Both original chirp bands (34–38 kHz, 42–46 kHz) sit entirely OFF
resonance; neither buoy would radiate or the receiver capture meaningful
acoustic energy at those frequencies. Bench-confirmed by hw-validation
(DL-1 addendum, Jun 17). Verify on the scope at the Layer A bench check.

**Why not frequency-division (rejected):** two distinguishable LFM bands
cannot fit in 3 kHz. A 32-tap FIR at fs=421,875 Hz resolves a transition
width of fs/N ≈ 13.2 kHz and CANNOT produce meaningful rejection across
the ≤1 kHz guard a 3 kHz budget would allow (the existing banks already
admit only ~2–3 dB of selectivity at 8 kHz separation — see
fir_filter_bank1.v header). Frequency-division is physically impossible
with this transducer + this FIR.

**Why not time-division (rejected):** alternating transmit slots require
buoy-to-buoy slot synchronization with NO shared clock — the same
impossibility that killed absolute ToF in FC-5. Free-running ESP32 slot
timers drift and collide. More firmware risk, more failure modes, the
Pi must infer slot identity. Inferior to code-division.

**Why not wider-band transducers (rejected for V1):** broadband
ultrasonic transducers are ~$15–40 each (×6 = ~$90–240, a real budget
hit on a $310–463 project) and may force a different drive/preamp chain.
Unnecessary because code-division works within the transducers in hand.

**Chosen architecture — CODE-DIVISION by sweep direction:**
- **Buoy 1:** UP-sweep LFM chirp, **38.5 → 41.5 kHz**.
- **Buoy 2:** DOWN-sweep LFM chirp, **41.5 → 38.5 kHz**.
- Both occupy the SAME full ~3 kHz passband. The vehicle correlates the
  received signal against TWO reference templates (up-ref in channel 1,
  down-ref in channel 2). An up-LFM vs down-LFM of equal B,T are
  quasi-orthogonal: cross-correlation is suppressed relative to the
  matched auto-correlation by ~√(BT)..(BT). With B = 3 kHz, T = 5 ms,
  **BT ≈ 15 → ~12–24 dB discrimination**, meeting the ≥20 dB beacon-ID
  target at the upper end. The 2109-sample window is more than long
  enough; longer T only improves separation.

**New chirp specifications (both buoys):**
| Param | Buoy 1 | Buoy 2 |
|---|---|---|
| Type | LFM (linear chirp) | LFM (linear chirp) |
| f_start → f_stop | 38.5 → 41.5 kHz (UP) | 41.5 → 38.5 kHz (DOWN) |
| Center / bandwidth | 40 kHz / 3 kHz | 40 kHz / 3 kHz |
| Duration T | 5.0 ms | 5.0 ms |
| Reference samples @ 421,875 Hz | **2109** (unchanged) | **2109** (unchanged) |
| BT product | 15 | 15 |

Sample count = 5.0 ms × 421,875 Hz = 2109 — **identical to the current
matched-filter window**, so N_TAPS, ADDR_W, BSRAM layout, ACCW, and
CORR_SHIFT are ALL UNCHANGED.

**peak_detector.v detection logic is MANDATORY dual-channel RELATIVE gating (RECONCILED Jun 17 by systems-integrator — supersedes the earlier absolute THRESH_HIGH/THRESH_LOW framing):**
- Take the ABSOLUTE VALUE of both corr_peak inputs first (free-running correlation produces negative values; signed `>` comparisons break otherwise).
- Buoy 1 detected: `abs_ch1 > (abs_ch2 << K_SHIFT)` AND `abs_ch1 > FLOOR` → target_id = 0x01
- Buoy 2 detected: `abs_ch2 > (abs_ch1 << K_SHIFT)` AND `abs_ch2 > FLOOR` → target_id = 0x02
- Neither / both-high / tie / both-below-FLOOR → target_id = 0x00 (never guess a target).
- UART-loadable parameters: **K_SHIFT** (ratio factor, k=2^K_SHIFT; default K_SHIFT=2 → k=4 ≈ 12 dB, matching the measured 12.2 dB sweep-direction isolation) and **FLOOR** (minimum absolute detection level; default conservative-high so nothing triggers before Pi calibration). SNR_SHIFT (8-bit SNR proxy scale) is a third UART-loadable register. Same load mechanism as reference chirp BSRAM writes — no new packet format.
- **Why RELATIVE, not absolute:** the sweep-direction isolation is only 12.2 dB (owner Python sim at exact spec), while the near/far signal spread across 1–10 m in air is ~33 dB. At the ARRIVED_1→SCAN_2 transition the vehicle is 1–2 m from Buoy 1 while Buoy 2 is at 8–10 m; Buoy 1's leakage into ch2 is +15 to +21 dB ABOVE the genuine far Buoy 2. No single fixed THRESH_LOW can sit below that crosstalk yet above the genuine far signal — the absolute-gate valid window is negative-width at this geometry. A relative (ratio) gate is invariant to absolute level and tracks geometry automatically. Single-channel thresholding remains FORBIDDEN.
- **Companion requirement (FC-8):** the relative gate PREVENTS a false Buoy 2 detection (emits 0x00, correct) but cannot itself ACQUIRE Buoy 2 while sitting on Buoy 1 — the FC-8 egress maneuver (acoustic_homing_node, not FPGA) creates the geometry where genuine Buoy 2 detection becomes possible. Gate + egress are complementary, both required.
- Config values are implemented as synthesizable registers with safe power-on RESET defaults for the V1 peak_detector deliverable; the inbound `uart_rx.v` config-write path (which also unblocks MF reference-chirp loading) is a separate Week 5 task.

**Downstream impact (precise):**
- **matched_filter_1.v / matched_filter_2.v:** Verilog UNCHANGED. The
  reference chirp is loaded at runtime over UART into BSRAM
  (ref_wr_en/ref_addr/ref_din). Channel 1 gets the up-sweep reference,
  channel 2 gets the down-sweep reference. Only the DATA loaded by the
  Pi's fpga_uart_node changes — not a single line of RTL. Both modules
  remain (one per template); neither is redundant under code-division.
  Reference must be signed-16 INTEGER scale per FC-1.
- **fir_filter_bank1.v / fir_filter_bank2.v:** Both must now pass the
  SAME 38.5–41.5 kHz band (center 40 kHz, ~3 kHz BW). This is a
  COEFFICIENT change only (edit the coeff_rom case-statement values +
  re-simulate); the sequential-MAC RTL structure is unchanged. The two
  banks become IDENTICAL in coefficients — bank2 may be collapsed to
  reuse bank1's coefficients, or kept as a separate instance for
  clarity. Recommendation: keep both instances, same coefficients, so
  the dual-channel top-level wiring is unchanged. NOTE: the FIR provides
  only coarse pre-selection regardless — the sweep-direction matched
  filters supply the actual beacon discrimination (consistent with the
  FIR headers' own honest selectivity note).
- **peak_detector.v:** STILL outputs corr_peak/snr/peak_lag per FC-5/FC-6.
  No structural change from FC-7 — but it is **BLOCKED from being written
  until the owner confirms these chirp specs**, because its two input
  channels now mean up-buoy (ch1) and down-buoy (ch2) rather than
  low-band/high-band. target_id semantics: ch1 = Buoy 1 (up), ch2 =
  Buoy 2 (down). Wire format and 8-byte packet UNCHANGED.
- **adc_interface / cic_decimator / uart_tx:** UNCHANGED. They never see
  the chirp frequency content.

**FCs affected:** FC-7 supersedes the band definitions in CLAUDE.md only.
FC-1 (integer scale), FC-2 (OTR), FC-3 (421,875 Hz), FC-5 (no ToF), FC-6
(SNR-gradient homing) ALL still hold without amendment. The 2109-sample
window (FC-3-derived) is preserved exactly.

**Net answer to the owner's load-bearing question:** the fix requires
REBUILD of only the FIR coefficient tables (a coefficient edit + re-sim,
not an architecture rebuild) and NEW BSRAM REFERENCE DATA loaded by the
Pi for the matched filters (zero RTL change). No verified matched-filter
RTL is thrown away. Week 4–5 FPGA work at risk is small: two coefficient
recomputations and their testbench re-runs.

**Also resolves BLOCKER B2 (MAX9814) — HARDWARE FIX ONLY, VERILOG
UNCHANGED:** the MAX9814 (20 Hz–20 kHz audio band) cannot pass 40 kHz and
must be replaced with a wideband op-amp front end (e.g. MCP6022 ~10 MHz
GBW, TLV2462) AC-coupled and re-biased to the AD9226 ±1V (VREF=1.0V)
input window. ~$2–8, minor net delta over the already-budgeted $8
MAX9814. The FPGA only ever sees the AD9226 digital output, so
adc_interface, cic_decimator, both FIR banks, and both matched filters
are ALL unaffected. No Verilog changes for B2.

### FC-8 — Egress Maneuver Required After Each ARRIVED State

**Constraint:** After each ARRIVED_N state (ARRIVED_1 and ARRIVED_2), the `acoustic_homing_node` must execute a dead-reckoning egress maneuver away from the just-arrived buoy before beginning SCAN for the next target. This is mandatory, not optional.

**Why:** Even with the FC-7 dual-channel gating (M2), when the vehicle is 1–2 m from Buoy 1 during SCAN_2, Buoy 1's cross-talk into the down-sweep matched filter (ch2) remains +15 to +21 dB above the genuine Buoy 2 signal at 8–10 m — far above any workable THRESH_HIGH setting. Dual-channel gating prevents false ARRIVED_2 detection, but cannot enable genuine Buoy 2 detection while sitting on Buoy 1. The vehicle must physically increase distance from the just-arrived buoy until the near/far signal advantage drops below the dual-channel gate's isolation margin.

**Required egress distance:** ~2–3 m estimated from physics (33 dB dynamic range / 10 dB per decade in air → need ~1 decade of range ratio reduction → egress until Buoy 1 advantage < 8.2 dB worst-case isolation). Exact calibrated value joins CQ-1 in the Calibration Queue for pool test #1.

**Implementation target:** `acoustic_homing_node` (Pi ROS 2 node, not FPGA). After ARRIVED state confirmed (corr_snr > SNR_ARRIVED_THRESHOLD for 3 consecutive readings per CQ-1), publish a reverse/egress Twist command to /cmd_vel for the calibrated egress duration, then transition to SCAN state for next buoy.

**FPGA impact:** NONE. This is a mission state machine change only.

**State machine update required:** ARRIVED_N → EGRESS_N → SCAN_(N+1), replacing the current direct ARRIVED_N → SCAN_(N+1) transition.

---

### FC-9 — uart_rx.v inbound frame is 4 bytes wide, NOT 2; region map is a documented convention, not an enforced one

**Constraint:** The original `uart_rx.v` spec (`[addr_byte][data_byte]`, 8-bit address + 8-bit data) is insufficient and must never be re-implemented that way. dsp-signal-validator (Jul 1, 2026) found it BLOCKED on four counts: an 8-bit address cannot reach the 2109-deep matched-filter reference-chirp BSRAM (needs 12 bits; 4221 addressable targets exist across 2 channels + config); an 8-bit data byte cannot carry a signed-16 reference-chirp sample (FC-1) or `peak_detector.v`'s 32-bit `FLOOR` register; there is no region field to separate config-register addresses from BSRAM addresses; and `matched_filter_1/2.v`'s reference BSRAM has no load-complete gate against the live MAC sweep.

**What was built instead:** `uart_rx.v` now assembles a 4-byte, big-endian frame — `[addr_hi][addr_lo][data_hi][data_lo]` — giving a 16-bit `addr_out` (65,536 locations) and a proper signed `data_out[15:0]` (FC-1 compliant). This is a PHY-layer fix only: `uart_rx.v` delivers raw addr/data pairs reliably and does not interpret them.

**What is still open (deferred, not fixed):** Two items remain for whoever builds the not-yet-started config-register-bank / BSRAM-loader consumer module:
1. **Region decode.** The address map is a *documented convention* in `uart_rx.v`'s header comment, not something `uart_rx.v` enforces: `0x0000–0x0001`=FLOOR (hi16 then lo16, consumer assembles into 32 bits), `0x0002`=K_SHIFT (low 5 bits), `0x0003`=SNR_SHIFT (low 5 bits), `0x1000–0x183C`=channel-1 (up-sweep) reference chirp (2109 words), `0x2000–0x283C`=channel-2 (down-sweep) reference chirp. The consumer module must decode these ranges itself; a bug there silently cross-corrupts thresholds and templates.
2. **Matched-filter load-gate.** Writing new reference-chirp samples into `matched_filter_1/2.v`'s `ref_mem` while the live MAC sweep is reading it (mid-correlation) can invert the FC-6 homing gradient via a torn read. Fixing this requires a `ref_loaded`/`corr_enable`-style gate touching `matched_filter_1.v`/`matched_filter_2.v` RTL — which FC-7 and CLAUDE.md currently document as "RTL UNCHANGED". That claim holds for `uart_rx.v` itself (untouched) but will NOT survive the BSRAM-loader module being built; plan for a small, deliberate MF RTL change at that point, not a silent violation of the "unchanged" note.

**FPGA impact of this entry:** `uart_rx.v` (done, sim-verified) and its `.cst` (pin candidate UNVERIFIED — hw-validation could not run this session; treat with the same discipline as PV-1/2/3 before wiring). No other pipeline module touched.

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

## 4. CRITICAL PATH — Revised 6-Week Plan (as of June 28, 2026)

**All 9 FPGA modules simulation-verified. Week 5 lost — zero tasks completed from
plan. Week 6 starts tomorrow June 29. 43 days remain to August 10 demo.**

### ⚠️ SCHEDULE STATUS (June 28 — Week 5 Day 7, last day of Week 5)

Week 5 actual completions: procurement (thrusters, enclosure, IRLZ44N ordered Jun 26),
definitive component audit complete (docs/component_audit_june28.md).
Week 5 NOT completed: top_level.v, Gowin synthesis, Layer A bench check, hull materials,
MCP6022 order. All carry into Week 6 as Day 1–2 priorities.

**The hard truth (unchanged):** 9 modules verified = 9 isolated simulations. The FPGA
design has never been synthesized, never run on hardware, never wired into a top-level
module. Until Gowin synthesis passes, resource estimates are unverified. This is the
highest-value de-risking action remaining on the FPGA side.

### Revised Weekly Plan (Weeks 6–11)

| Week | Dates | Phase | Primary Task | Exit Criterion | Deps |
|---|---|---|---|---|---|
| 6 🔴 | Jun 29–Jul 5 | Integration + Hardware Start | top_level.v → Gowin synthesis → Layer A bench → ESP32 skeleton → hull start | top_level.v synthesizes with positive slack; Layer A confirms acoustic path reaches scope; hull pontoons cut | All 9 sim-verified modules |
| 7 🔴 | Jul 6–Jul 12 | ROS 2 + Layer B | fpga_uart_node, acoustic_homing_node, dead_reckoning_node, collision_safety_node; Layer B ADC capture | Pi parses FPGA packets; homing node subscribes /acoustic/corr_snr; Layer B: valid ADC samples reach Pi | Synthesis passed; MCP6022 in hand; PV-1/2/3 cleared |
| 8 🔴 | Jul 13–Jul 19 | Full System Integration | mission_state_machine, motor_driver_node, hull completion, dry-land E2E rehearsal, buoy assembly | Dry-land E2E: FPGA→UART→Pi→/cmd_vel→motors; thrust ≥150g/motor; stall-trip confirmed | Layer B working; hull fabricated; thrusters arrived |
| 9 🎯 | Jul 20–Jul 26 | Pool Test #1 | One-buoy acoustic homing, CQ-1 calibration | Vehicle homes to within ~0.5m of Buoy 1 on video; /acoustic/corr_snr vs distance recorded | Full dry-land E2E rehearsal passed |
| 10 🔴 | Jul 27–Aug 2 | Pool Test #2 + Tuning | Fix W9 regressions; two-buoy if W9 was clean | At least one clean buoy-homing run on video; CQ-1 threshold set in acoustic_homing_node | W9 pool test and rosbag capture |
| 11 🏁 | Aug 3–Aug 9 | Polish + Demo Video | Demo video, clean git history, README | Demo video committed to repo; code clean | W10 clean run on video |

### Week 6 Day-by-Day (Jun 29–Jul 5) — critical detail

```
Jun 29 (Mon) — top_level.v: chain all 9 modules (AD9226→CIC→FIR×2→MF×2→peak→framer→UART)
               ORDER MCP6022-I/P ×4 on Amazon Prime (if not yet ordered)
               Verify owned buck converter chip marking — order Pololu D24V50F5 if < 4A rated

Jun 30 (Tue) — Gowin EDA synthesis: run full design, get timing and utilization report
               Fix any timing violations SAME DAY (do not let them carry)
               HOME DEPOT RUN with Dad: PVC pipe, end caps, L-brackets, epoxy, silicone
               Boot Pi with ROS 2 stubs → vcgencmd get_throttled must read 0x0

Jul 1 (Wed)  — Hull fabrication: cut PVC pontoons, test fit cross members
               MCP6022 arrives (2-day Prime from Jun 29 order) → build preamp on breadboard

Jul 2 (Thu)  — LAYER A BENCH CHECK: TCT40-16T → IRLZ44N→MOSFET→5V → air path → TCT40-16R
               Frequency sweep 37–43 kHz in 250 Hz steps; scope RX output; record amplitude
               uart_rx.v: UART inbound path for K_SHIFT/FLOOR config + MF reference chirp load

Jul 3 (Fri)  — ESP32 vehicle firmware skeleton: micro-ROS init, LEDC PWM ENA/ENB (GPIO25/26),
               stall-current monitoring via shunt+ADC, 30cm ESTOP, MPU-6050 I2C

Jul 4–5 (Sat-Sun) — ESP32 buoy firmware: LFM chirp generation (38.5→41.5 kHz up-sweep /
               41.5→38.5 kHz down-sweep), IRLZ44N drive at 40kHz, 3× TCT40-16T per buoy
```

### What to cut if the schedule slips further

1. **Second buoy** — do one-buoy homing; document two-buoy as designed-but-not-demo'd
2. **Egress maneuver (FC-8)** — simplify to fixed-duration reverse before SCAN_2
3. **Telemetry / Arduino shore display**
4. **Collision avoidance display** — keep ESTOP safety logic; skip range display

**Never cut:** Gowin synthesis proof, Layer A/B bench validation, one clean acoustic-homing
run in water on video, coherent git history. These are the portfolio deliverables.

**Absolute minimum viable demo (MVS):** Stationary bench demo on video — Pi receives
FPGA UART packets, publishes /acoustic/corr_snr, logs acoustic response as transducer
is moved toward buoy. Captures full FPGA signal chain even if hull is not pool-ready.
This is the last-resort fallback; the target is still a moving vehicle in water.

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

---

## 7. DECISION LOG

### DL-1 — Acoustic bench testing timing (decided June 17, 2026, Week 4 Day 3)

**Question:** All four analog-chain parts are now physically in hand
(TCT40-16R, MAX9814 preamp delivered today, AD9226 arrived Jun 8, Tang
Nano 20K). Should real hardware bench testing of the signal chain start
now, or wait? The original plan put all hardware/pool testing at Week 9.

**Decision: HYBRID.**
1. **No change to the critical path this week.** `peak_detector.v` →
   full-pipeline integration → Gowin synthesis remains the Week 4–5
   priority exactly as Section 4 states. FPGA simulation focus is NOT
   interrupted for hardware bring-up.
2. **Pull ONE narrow analog-only bench check forward** to the Week 4/5
   boundary (after peak_detector is written, before/around integration):
   a scope-only validation of the **analog sub-chain TCT40-16R → MAX9814**,
   FPGA NOT in the loop. This is a few hours and touches zero Verilog context.
3. **Defer the FPGA-in-the-loop ADC capture** (AD9226 → Tang Nano reading
   valid samples) to **Week 5**, naturally coincident with pipeline
   integration when `adc_interface` first lives in an integrated top.

**Reasoning:** The "test now vs. wait" question actually splits into two
independent de-risking layers that must be scheduled differently:
- **Layer A (analog: transducer → MAX9814 → into AD9226 input range).**
  Failure modes — MAX9814 AGC behavior on a 40 kHz tone, gain/clipping,
  DC bias, signal level vs. the AD9226 ±1V (VREF=1.0V) window — are
  empirical and *cannot be simulated*. They are independent of the matched
  filter. The MAX9814 auto-gain is the single least-predictable element in
  the entire signal path, and it directly gates CQ-1 (the SNR-plateau
  calibration). Catching a gain/level problem now is cheap; discovering it
  at Week 9 with zero buffer left is a crisis. → worth pulling forward.
- **Layer B (FPGA reading valid ADC data).** Requires PV-1/PV-2/PV-3
  strap checks cleared first (or risk FPGA GPIO damage), and only proves
  anything once `adc_interface` + `uart_tx` sit in an integrated top —
  which is itself the Week 5 milestone. Doing this *now* forces a
  context-switch into hardware bring-up mid-critical-path, exactly the
  week-level risk to avoid given the two weeks of carryover already
  compressing Weeks 3–6. → keep it on the Week 5 integration boundary.

Rejected **START FULLY NOW**: would divert focus from `peak_detector.v`,
the single remaining FPGA module before integration, during the most
schedule-constrained stretch of the project.
Rejected **DEFER ENTIRELY TO WEEK 9**: leaves the least-predictable analog
element (MAX9814 AGC) unvalidated until there is no schedule slack to
absorb a surprise.

**Recommended action THIS week (Week 4):** finish `peak_detector.v`
(simulate, X/Z check, companion testbench) → begin full-pipeline
integration. Do NOT wire the FPGA to the ADC yet.

**When bench testing begins:**
- *Analog-only scope check (Layer A):* Week 4/5 boundary, immediately
  after `peak_detector.v` is verified. A few hours, no FPGA.
- *FPGA-in-the-loop ADC capture (Layer B):* Week 5, alongside pipeline
  integration, and only after PV-1/PV-2/PV-3 are cleared.

**Preconditions before bench testing:**
- *For the analog-only check (Layer A):* MAX9814 powered at a known rail;
  a 34–46 kHz tone source to drive TCT40-16R (function generator, or a
  buoy TCT40-16T driven by ESP32 #2 — but ESP32 firmware is not yet
  written, so a function generator is the faster source). Scope the
  MAX9814 output and confirm it stays within the AD9226 ±1V input window
  with headroom and no clipping/AGC pumping artifacts. The AD9226 need NOT
  be powered for this step.
- *For FPGA-in-the-loop (Layer B):* ALL of Section 3 must be cleared first
  — **PV-1** DRVDD = 3.3V (not 5V), **PV-2** DFS strap = AVSS,
  **PV-3** OEB tied LOW. These are mandatory the instant the AD9226 is
  energized and wired to Tang Nano GPIO; getting any one wrong can destroy
  FPGA GPIO or produce silently wrong data.

**DL-1 addendum — Layer A signal source validated (hw-validation, June 17, 2026):**

FPGA-as-tone-generator plan approved for TX side. Tang Nano 27 MHz clock
divider generates clean square waves via integer division: 40 kHz (half-count
337 → 40,059 Hz, ±0.15%), 36 kHz (half-count 375 → exactly 36,000 Hz), 44 kHz
(half-count 307 → 43,974 Hz, −0.06%). FPGA PWM preferred over 555 timer —
more accurate, retunable in Verilog, zero extra parts. Drive circuit:
logic-level N-channel MOSFET (2N7000/BS170 — confirm part number in hobby
pack), 150–220Ω gate series resistor, 100kΩ gate-to-source pulldown, 1N4148
clamp diode from drain to +V rail. Drive TX at **5V, not 11.1V LiPo** — 5V
gives sufficient SPL at 20–30 cm bench range without overdriving the receiver
or creating LiPo risk on a breadboard. TX/RX separation: 20–30 cm, line-of-
sight, transducers facing each other.

**TWO BLOCKERS DISCOVERED — project-architecture level, not just bench logistics:**

**BLOCKER B1 — Transducer bandwidth vs. chirp bands:**
TCT40-16T/R are narrowband resonant piezo transducers, efficient only within
~38.5–41.5 kHz around their 40 kHz resonance. The project's Chirp 1 (34–38 kHz)
and Chirp 2 (42–46 kHz) bands both sit on the resonance skirts. At 36 kHz and
44 kHz, radiated/received acoustic energy is down many dB — a bench test at
these frequencies will see almost no signal even at point-blank range. **For the
Layer A bench test, drive TX at 40 kHz** to confirm the acoustic path is working.
The two-band beacon architecture needs reconciliation with systems-integrator:
options are (a) move chirp bands to straddle 40 kHz (e.g. 38–40/40–42 kHz),
(b) change to wider-band transducers, or (c) change the buoy-ID method. **The
FIR banks, matched-filter reference chirps, and UART packet schema may need
revision depending on the resolution.** Escalate to systems-integrator before
any pool test is scheduled.

**BLOCKER B2 — MAX9814 preamp bandwidth:**
MAX9814 is an audio-band preamp (20 Hz – 20 kHz). Its gain-bandwidth product puts
the −3 dB corner far below 40 kHz — the ultrasonic signal is attenuated into the
noise. It **cannot** be used in the receive chain. Replace with a wideband op-amp
front end (e.g. MCP6022, TLV2462, or a small ultrasonic receiver board) with a
bandpass centered on 40 kHz. This is an unbudgeted purchase (~$2–8). Also note:
the preamp-to-ADC interface needs AC coupling and re-biasing — the MAX9814's
1.25V DC bias / 2 Vpp output does not directly match the AD9226 ±1V (VREF=1.0V)
input range; this applies to any replacement preamp as well.

**Interim Layer A path (no preamp purchase required):** Drive TCT40-16T at 40 kHz /
5V via FPGA+MOSFET. Scope the TCT40-16R receiver output **directly** (no preamp in
the loop) to confirm the acoustic path is transmitting and receiving. This validates
the transducer pair and acoustic coupling independent of the broken preamp choice.
Full signal-chain test (with preamp) waits on the replacement part arriving.

### DL-3 — Schedule compression acknowledgment + MVS pivot (June 25, 2026, Week 5 Day 4)

**Situation:** Six days of zero engineering progress (Jun 19–24). Nothing from
the Week 5 plan (pipeline integration, Gowin synthesis) is complete. Four
categories of parts remain unordered with non-trivial shipping latency: preamp
replacement, thrusters, enclosure, and hull materials. Pool test #1 is 25 days
away (Week 9, Jul 20). The full two-buoy sequential homing demo is at risk of not
completing within the Aug 10 deadline.

**Decision: Declare FPGA module phase DONE. Freeze all module work. Pivot
to integration + synthesis + ordered parts NOW.**

Rationale:
1. Nine modules are individually verified. No further module-level work is needed
   or justified. Any further "polish" on verified modules is scope creep that
   consumes the one resource that cannot be recovered: calendar time.
2. The synthesis pass is the highest-value de-risking action remaining on the FPGA
   side. Resource estimates (multipliers, BSRAM) are still unverified simulation
   numbers. A synthesis failure discovered in Week 7 with no schedule slack is a
   project-level crisis. Discovered this week, it is a solvable engineering problem.
3. The preamp and thrusters gate every downstream milestone. Ordering them today
   vs. next week costs exactly the difference in shipping time — typically 3–7 days
   that cannot be compressed later.

**Minimum viable demo (MVS):** One-buoy acoustic homing on video by Aug 10.
Second buoy and egress maneuver are stretch goals. This still demonstrates
the full signal chain (FPGA matched filter → ROS 2 SNR-gradient homing → 
motor control), which is the portfolio claim.

**Rejected — continue FPGA module refinement:** The modules are done.
Refinement at this stage is a focus-avoidance pattern, not engineering.

**Rejected — wait on parts order until synthesis is confirmed:** Synthesis
takes a day; parts take a week to ship. These are parallel actions, not sequential.

### DL-5 — Preamp: MCP6022-I/P selected over MCP6002-I/P (June 28, 2026, Week 5 Day 7)

**Question:** MCP6002-I/P (GBW=1MHz, Prime-available, ~$7/10-pack) vs MCP6022-I/P (GBW=10MHz,
also Prime-available, ~$7–15/10-pack). Which to order? Is MCP6002's 0.7dB/stage rolloff
at 41.5kHz acceptable for this matched filter application?

**Decision: ORDER MCP6022-I/P. MCP6002 is technically acceptable but MCP6022 is the correct
engineering choice since both are Prime-available at similar delivery timelines.**

Rationale:
1. **MCP6002 analysis** (Microchip DS20001733L — confirmed): GBW=1MHz. At G=10/stage:
   closed-loop BW=100kHz. Rolloff at 41.5kHz: -0.69dB/stage → -1.38dB total (two stages).
   Phase at 41.5kHz: 22.5°/stage → 45° total (two stages). Differential phase across 3kHz
   band: 2.8°. This is technically acceptable for a BT=15 matched filter (correlation peak
   loss < 0.2dB; phase differential < 3° causes negligible discrimination degradation).
   Supply: 1.8–6V; rail-to-rail I/O; Iq=100μA.

2. **MCP6022 analysis** (Microchip DS20001685F — confirmed): GBW=10MHz. At G=10/stage:
   closed-loop BW=1MHz. Rolloff at 41.5kHz: -0.0008dB (negligible). Phase: <0.3° total
   across band. Offset voltage < 0.5mV (10× better than MCP6002). Supply: 2.5–5.5V;
   rail-to-rail I/O; Iq=1.0mA.

3. **Why MCP6022 despite higher Iq:** Both parts are Prime-available with identical
   delivery timelines (Jun 29–30 if ordered today). There is no shipping advantage to
   MCP6002. MCP6022 gives 14× more bandwidth margin, cleaner phase response, and lower
   offset — all free at the same price/delivery. MCP6002 is acceptable as a fallback
   ONLY if MCP6022 goes out of stock.

**Rejected — MCP6002:** Technically acceptable but unnecessary compromise when MCP6022
is equally accessible.
**Rejected — LM358:** GBW=1MHz → at G=10: BW=100kHz; at single stage G=100: BW=10kHz
(below the 40kHz signal). Disqualified.
**Rejected — NE5532P:** Requires ±5V split supply (min ±5V); not rail-to-rail; completely
out of spec on 5V single supply. Disqualified (confirmed from onsemi datasheet Jun 25).

**Action:** ORDER MCP6022-I/P ×4 minimum on Amazon Prime. Build two-stage non-inverting
cascade: Rf=9.1kΩ, Rg=1kΩ per stage → G≈10.1/stage → ×102 total (~40dB).
Virtual ground: 100kΩ+100kΩ divider from 5V → 2.5V. AC couple to AD9226 with 100nF
cap; rebias with 10kΩ from AD9226 VREF (1.0V).

---

### DL-2 — Thruster downgrade 545 → RF-370 (LICHIFIT) + thrust gate (decided June 17, 2026, Week 4 Day 3)

**Question:** The planned 545-class brushed underwater thruster (~$32.50/unit,
~$65/pair) draws ~3.6 A at 11.1 V (interpolated from QX-Motor OEM load table),
which **structurally exceeds the already-purchased L298N** (2 A continuous / 3 A
peak per channel). What thruster fits the L298N, and is it strong enough for the
mission?

**Decision: SWITCH to 2× LICHIFIT RC Jet Boat Underwater Motor (RF-370 class,
Amazon ASIN B07WY4MDYZ, ~$23.99/kit, CW+CCW pair per kit). Buy 2 kits (~$48).
Drive at ~9 V via a PWM duty cap. Gate hull final assembly on a bench thrust check.**

1. **Electrical:** RF-370 stall <1.8 A (RF-370CA datasheet: stall 1.1–1.5 A @ 12 V,
   running ~0.5–0.8 A) → **L298N PASS**. The 545 was never viable on the purchased
   L298N regardless of cost. **Do NOT replace the L298N — it is purchased and the
   RF-370 fits it.**
2. **hw-validation CONDITION (carry into ESP32 motor firmware):** PWM duty ceiling so
   motor voltage stays ~9 V. Reviews report DOA units and burn-outs at 12 V; the
   L298N's ~2 V drop helps but an explicit duty cap is required in the motor driver.
3. **Quantity — buy 2 kits (~$48):** one kit is one full counter-rotating vehicle set
   (CW+CCW props cancel net prop torque → helps heading hold during SCAN/HOMING).
   The second kit is a spare-pair hedge against the documented reliability risk. At
   $24, a spare pair is cheap insurance against a burned motor stalling the
   propulsion track during the tightest build weeks. Still **cheaper than the
   rejected 545 pair (~$65)**. Budget line ($20–24) roughly doubles to ~$48
   (~+$24, ~5–8% of project total — acceptable).

**Thrust-to-weight assessment (systems-integrator):**
- Bottom-up dry mass ~3.95 kg; ~4.5 kg operating (water/sealant/contingency).
  4" Sch 40 PVC ≈ 0.56 kg/m (published Sch 40 pipe weight tables).
- **T/W is the wrong gate for a boat** — the two 4"×70 cm pontoons displace ~11 kg
  of buoyancy, so the hull floats with >2× reserve at 4.5 kg. Thrust fights
  **hydrodynamic drag, not weight.** Estimated drag at the 0.1–0.3 m/s this mission
  needs is only ~25–70 g-force.
- Per-motor thrust: 100 g = marginal (weak rotation/heading authority, drift-prone);
  **150 g = viability floor**; **175–200 g = adequate** (~5:1 over drag, good SCAN
  rotation and gradient-ascent HOMING); 250 g = ideal. RF-370 estimate is
  ~100–250 g (no OEM load table — estimate from motor class), so it **straddles the
  floor** — must be bench-confirmed.
- **FC-6 helps:** SNR-gradient homing tolerates low/slow thrust far better than the
  old range-PID model would have — no station-keeping at a computed range, just keep
  SNR climbing. The downgrade is survivable under the current control law.

**GATE (the load-bearing part of this entry):**
> **Before ANY thruster is epoxied / cable-glanded into the hull (Week 6 thruster
> mounting), bench-verify ≥150 g/motor (200 g target) at the ~9 V capped drive
> using a luggage scale / spring gauge.** If a motor reads <150 g, the RF-370 choice
> must be revisited (gear/prop change, or accept slower homing) BEFORE the
> irreversible hull bond. This gate sits at the Week 5/6 boundary and naturally
> precedes the Week 6 mounting task. Rationale: a $24 part with DOA/burn-out reviews
> and a thrust estimate straddling the viability floor must not propagate an
> unverified physical assumption into a never-revisitable epoxy/silicone joint.

**Rejected — keep the 545 and upgrade the H-bridge:** out of scope; L298N is
purchased and locked. **Rejected — buy only 1 kit:** functionally sufficient, but
leaves zero spare against documented reliability risk during the most
schedule-constrained weeks; the $24 hedge is worth it.

### DL-4 — Component Audit Firmware and Hardware Build Requirements (June 26, 2026, Week 5 Day 5)

**Source:** Component audit Jun 25–26. Five firmware and hardware build requirements
discovered that were not previously documented. All are mandatory before Week 9 pool test.

**Requirement 1 — Motor stall-current protection (MANDATORY, Week 6 ESP32 firmware):**
LICHIFIT RF-370 stall current = 5–8.6A at ~9V. L298N thermal limit is 2A continuous / 3A peak.
At full stall the motor destroys the L298N within seconds if PWM is not cut. The ≤80% duty
cap enforces voltage, NOT current — it does not protect against stall.
`motor_driver_node` (ESP32, Week 6) MUST implement:
- Monitor current per channel (shunt resistor + ESP32 ADC, OR estimated from PWM duty × V_bus)
- If current > 1.5A for > ~100ms on any channel: immediately cut PWM to zero, wait 500ms, resume at 50% duty
- This is a required safety feature. Do not close out Week 6 without it.

**Requirement 2 — ESP32 LEDC hardware PWM for L298N ENA/ENB (MANDATORY):**
ENA and ENB pins MUST be driven by ESP32 LEDC hardware PWM channels, NOT software GPIO toggle.
Software toggle frequency is CPU-load-dependent and can drift above 80% duty under interrupt
pressure (micro-ROS + IMU + ultrasonic all competing). LEDC channels are timer-driven and
maintain duty cycle in hardware regardless of CPU load.
Recommended: ENA → GPIO25 (LEDC timer 0, channel 0), ENB → GPIO26 (LEDC timer 0, channel 1).
Verify against MPU-6050 I2C (GPIO21/22) and UART (GPIO1/3) before breadboard commit.

**Requirement 3 — collision_safety_node ESTOP threshold raised to 30cm:**
JSN-SR04T has a documented blind zone of ~25cm. At 25cm ESTOP threshold the sensor may be
returning invalid/stale data — the obstacle is already inside the dead zone. Threshold raised to
30cm to clear the blind zone with 5cm margin. `collision_safety_node` ESTOP condition updated in
CLAUDE.md ROS 2 node graph and ESP32 #1 peripheral spec.

**Requirement 4 — Preamp gain capped at ×100 / 40dB (NOT ×196):**
At ×196 total gain, the ADC clips at 5.1mV input signal level. Within 1m homing range, received
acoustic SPL increases sharply — 5.1mV clipping is easily reached in the final approach, corrupting
the SNR gradient precisely where FC-6 homing is most critical (ACQUIRING → HOMING → ARRIVED).
Revised spec: two-stage non-inverting amplifier, Rf=9.1kΩ (or standard 10kΩ) / Rg=1kΩ per stage
= ×10/stage = ×100 total (~40 dB). ADC clips at ~10mV — adequate headroom through close-range approach.
See CLAUDE.md Preamp Hardware Contract for full gain spec.

**Requirement 5 — PWM noise isolation (hardware build, mandatory before Layer B):**
L298N motor switching couples high-frequency transients onto the motor power rail and through
shared ground into the analog front-end. Required before any FPGA-in-the-loop testing:
- 100nF ceramic + 100µF electrolytic decoupling on L298N motor supply, placed close to the IC
- Star ground: analog ground (preamp, ADC) and motor ground (L298N, motors) on separate copper
  paths, joined at ONE point only at the LiPo negative terminal
- Ferrite bead (e.g. BLM18PG221SN1) in series on MCP6022/TLV2462 VCC pin to block motor
  switching noise from entering op-amp supply rail
Violating star ground on motor-driven vehicles has historically raised analog noise floors 20–30dB,
masking legitimate acoustic signals at range.

**Downstream impact:** All five requirements affect Week 6–7 firmware/hardware work only. No FPGA
RTL changes. No impact on the FPGA pipeline, synthesis, or Week 5 integration work.

### DL-6 — Go/No-Go assessment after ROS 2 node build-out (July 1, 2026, Week 6 Day 3)

**Context:** As of today, all 10 FPGA modules are RTL-complete and sim-verified (top_level.v
synthesized with positive slack Jun 30), and 6 of 7 planned ROS 2 nodes are code-complete
(motor_driver_node, collision_safety_node, dead_reckoning_node, acoustic_homing_node,
mission_state_machine, telemetry_node — only fpga_uart_node predates today). ESP32 vehicle and
buoy firmware were also discovered to already exist in the repo (built Jun 29), previously
undocumented. None of the ROS 2 graph has been colcon-built or run; none of the ESP32 firmware
has been flashed or bench-tested; hull fabrication (due to start today, Jul 1) and the Layer A
acoustic bench check (due Jul 2) have not yet happened.

**Verdict: GO for the single-buoy MVS fallback, CONDITIONAL GO for the full two-buoy demo.**

The software/RTL side of this project is now substantially ahead of the physical-build side —
every FPGA module and every planned ROS 2 node exists as verified code, but there has been zero
hardware integration to date. That gap is normal for Week 6 of this schedule, but it means the
remaining 40 days must convert code-complete into hardware-verified, not add more code. Pool
test #1 (Jul 20–26) is 19 days out and is a hard date.

**Top 3 risks, in priority order:**

1. **Zero physical integration so far.** RTL and ROS 2 completeness can create a false sense of
   being on-track. The actual gating tasks — hull fab, ESP32 flash + bench test, Layer A acoustic
   check, dry-land E2E — are all still ahead, all on the physical/calendar-bound critical path,
   and none can be compressed by writing more code. If hull fab slips past this week the way
   Week 5 slipped entirely, pool test #1 prep window shrinks below what dry-land rehearsal needs.

2. **Layer A acoustic bench check is the single highest-uncertainty item remaining.** FC-6
   (SNR-gradient homing) and FC-7 (sweep-direction code-division beacon ID, ~12.2 dB isolation)
   are both simulation/analysis results, never measured on the real TCT40-16R/T transducer pair.
   If the real isolation or passband differs meaningfully from the modeled 38.5–41.5 kHz / 12.2 dB
   assumptions, it cascades into the FIR coefficients, K_SHIFT/FLOOR calibration, and the egress
   distance (FC-8) — all downstream of a bench check that hasn't happened yet.

3. **The config-load path is unfinished exactly where it will be needed for calibration.**
   `uart_rx.v` (today's work) is only the PHY layer; the actual config-register-bank / BSRAM-loader
   consumer that applies K_SHIFT/FLOOR/SNR_SHIFT and loads reference chirps does not exist yet
   (see FC-9), and building it will require a small, deliberate touch to `matched_filter_1/2.v`
   (a load-gate) that FC-7/CLAUDE.md currently describe as "RTL unchanged." CQ-1's empirical
   threshold calibration at pool test #1 depends on this path existing and working before then.

**Recommendation:** Do not start any further ROS 2 or FPGA feature work until hull fabrication is
underway and the Layer A bench check has produced a real measurement. The highest-value action for
the next 48 hours is physical, not digital.
