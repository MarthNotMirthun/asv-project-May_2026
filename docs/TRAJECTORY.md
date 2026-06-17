# TRAJECTORY.md — ASV Technical Compass

**Last Updated:** June 17, 2026 (Week 4 Day 3 of 11)

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
| `matched_filter_1` (Buoy 1) | ✅ DONE & verified | 2109-sample block correlator, 48-bit acc, CORR_SHIFT=16, OTR window-OR, 200Hz out; sim >3000× chirp/noise ratio ← VALIDATED Jun 16 |
| `matched_filter_2` (Buoy 2) | ✅ DONE & verified | Same architecture; cross-band rejection verified ← VALIDATED Jun 16 |
| `peak_detector` | ⏳ NOT STARTED | **NOW THE SINGLE REMAINING FPGA MODULE** before integration — see Section 4 |
| Full pipeline integration | ⏳ NOT STARTED | Blocked only on peak_detector |

**Status as of June 16:** All seven authored modules (ADC → CIC → 2×FIR →
2×matched_filter) are verified. The dual matched filters passed
hw-validation (APPROVED WITH CONDITIONS), dsp-signal-validator (3 BLOCKERs
caught and resolved), systems-integrator, and verilog-sim-runner (ALL
PASS, >3000× chirp/noise rejection, cross-band rejection confirmed) on
June 16. **`peak_detector.v` is now the only remaining FPGA module
between current state and full-pipeline integration.** FC-5 and FC-6 are
confirmed and resolved — SNR-gradient homing, not absolute ToF range.
`peak_detector.v` outputs `corr_peak`/`snr` as primary; `peak_lag` kept
as diagnostic only. **Proceed to peak_detector implementation
immediately.**

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

## 4. CRITICAL PATH — `peak_detector.v` (single remaining FPGA module)

The matched filter correlators ×2 are **DONE and verified (Jun 16)**. The
critical path has advanced to `peak_detector.v` — the last module before
full-pipeline integration and synthesis. It is far simpler than the
matched filter; the hardest DSP block is now behind us.

Requirements (inherits all forward constraints above):
- Consumes `corr_peak` (matched filter, CORR_SHIFT=16 scale) and `otr_out`
  from both matched filter channels
- Outputs: `corr_peak` (32-bit, same scale), `snr` (8-bit = corr_peak /
  noise_floor in the same scale), `peak_lag` (11-bit diagnostic passthrough)
- **NO range_cm, NO ToF conversion** (per **FC-5**) — `snr` is the primary
  homing gradient; `peak_lag` is V2-TDOA hook only
- `otr_in` / `otr_out` carried through (per **FC-2**)
- Watch BSRAM: if noise-floor averaging or threshold-history buffers are
  added, they consume blocks on top of the current 14/46 — keep them in
  LUT/registers if small (see Q2 below). Budget for ≤2 added blocks.
- Pipeline all MAC chains; companion testbench in `fpga/sim/`; iverilog,
  check X/Z

### After peak_detector
1. Full pipeline integration: chain ADC → CIC → FIR ×2 → MF ×2 →
   peak_detector → uart_tx; verify end-to-end latency within 50 ms budget
2. Synthesis in Gowin EDA: confirm positive timing slack at 27 MHz, and
   **re-confirm actual LUT/BSRAM/DSP from the synthesis report** vs the
   estimates in CLAUDE.md (the BSRAM correction shows estimates can be off)

### Schedule reality
Two weeks of carryover from Weeks 1–2 still exist. Weeks 3–6 are reserved
as FPGA-focused; ROS 2 work stays deferred until the FPGA pipeline is
done. With the matched filter complete, the schedule risk has dropped
materially — but the carryover means peak_detector + integration +
synthesis must finish inside Week 5 to hold the Week 5 milestone.

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
