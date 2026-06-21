# CONSOLIDATED_CONTEXT.md — ASV Project Master Reference

**Generated:** June 15, 2026 (Week 4 Day 1 of 11)
**Owner:** Mirthun Mohan — Texas A&M University Computer Engineering
**Hard Deadline:** August 10, 2026

This document is the single master reference for the GPS-denied acoustic-homing
catamaran USV project. It consolidates CLAUDE.md, TRAJECTORY.md, progress.md,
and all Verilog source files into one place. For living technical cross-module
contracts, TRAJECTORY.md is the authority. For hardware spec detail and locked
decisions, CLAUDE.md is the authority. This file synthesizes both.

---

## 1. PROJECT HISTORY — Week by Week

### Week 1 (May 25–31) — Foundation
- Project scoped and architecture locked: GPS-denied, air-acoustic homing, two beacons
- Hardware ordered: Pi 4, Tang Nano 20K, AD9226 (AliExpress), LiPo batteries, charger, fuses
- Raspberry Pi 4 1GB set up: Ubuntu 24.04.4 LTS, ROS 2 Jazzy, SSH, heatsinks
- Pi known issues resolved: liblz4/libzstd/zlib1g force-downgraded; Debian Trixie rejected
- avahi-daemon enabled; VS Code Remote SSH working
- Status: PARTIAL — some parts ordered but FPGA work not yet started

### Week 2 (Jun 1–7) — Pi Setup Complete, FPGA Starts
- **Jun 8:** UART TX module (`uart_tx.v`) written and synthesized onto Tang Nano 20K
  - 8-byte back-to-back packet verified in simulation
  - CLKS_PER_BIT=234 → 115,384 baud actual (+0.16% from 115,200 target), acceptable
- **Jun 8:** Pi UART serial console disabled — `/dev/ttyAMA0` now free for FPGA comms
- **Jun 8:** AD9226 ADC arrived (ordered ~May 31 from AliExpress)
- ROS 2 Jazzy talker/listener verified; colcon and rosdep installed
- snapd removed (caused watchdog timeouts — never reinstall)
- Status: PARTIAL — UART done, timing constraints and ADC interface not yet written

### Week 3 (Jun 8–14) — Full FPGA Pipeline Stages 1–5 Completed and Validated

**Jun 9:**
- `adc_interface.v` written — FPGA-generated ENCODE clock (3.375MHz = 27MHz/8), 7-cycle pipeline latency alignment
- `cic_decimator.v` written — R=8, N=3, 28-bit internal datapath
- `uart_tx.v` re-verified for 8-byte back-to-back packet; inter-byte gaps confirmed <<1 bit period
- hw-validation run → **5 blockers found and fixed same session:**
  - `uart_tx.cst`: clk was pin 52 (9K crystal) → corrected to pin 4 (20K crystal)
  - `uart_tx.cst`: rst_n collision with clk pin → moved to pin 88 (S1 button)
  - `uart_tx.cst`: tx was pin 17 (onboard LED) → moved to pin 86 (J5 header GPIO); pin 69 rejected (wired only to BL616 USB-UART bridge, not broken out to headers)
  - `adc_interface.v`: pipeline latency was 3 ENCODE cycles → corrected to 7 (AD9226 datasheet Rev B)
  - `adc_interface.v`: OTR clamp removed — ADC drives 0xFFF/0x000 on over-range; clamp was wrong

**Jun 10:**
- Full pipeline validation run: hw-validation + dsp-signal-validator + systems-integrator + verilog-sim-runner
- **2 additional blockers fixed:**
  - `adc_interface.v`: added MSB-flip `{~adc_data[11], adc_data[10:0]}` for offset-binary→two's-complement conversion. Without this, 0V = -2048 → CIC saturation
  - `cic_decimator.v`: output right-shift corrected from 12 bits to 5 bits (Hogenauer formula: B_max=21, shift=20−15=5). Old shift caused ~128× amplitude loss (~42dB SNR collapse)
  - Added OTR port (`sample_otr`) to `adc_interface.v`
  - Added saturation clamp to CIC dout (prevents full-scale transient wrap)
  - CIC header comment corrected: was R=160, DVDD=5V, latency=3 → corrected to R=8, DRVDD=3.3V, latency=7
- `fir_filter_bank1.v` built: 32-tap Hamming windowed-sinc, 34–38kHz, fs=421,875Hz, signed-16 integer output
- `fir_filter_bank2.v` built: 32-tap Hamming windowed-sinc, 42–46kHz, fs=421,875Hz, signed-16 integer output
- All simulations PASS, no X/Z states

**Jun 12–13:**
- `uart_tx.cst` finalized: pin 86 (tx), pin 4 (clk), pin 88 (rst_n)
- `adc_interface.cst` written and fully verified: all 14 pins confirmed against Sipeed schematic rev 1.22 and pin-label diagram. Previous "contiguous block 25–41" assignment was wrong — pins 32–39 go only to the RGB-LCD FPC connector, not headers. Corrected to use J6 header pads (pins 73,74,75,85,77,27,28,25,26,29,30,31) for D[11:0] and J5 pads (80, 76) for OTR and adc_clk
- `adc_interface.v`: `sample_out` changed to `signed` declaration (FIX-N1)
- FIR bank output port comments updated: dout is signed-16 INTEGER scale, NOT Q1.15 (FIX-N2)
- Testbench OTR timing races fixed in tb_cic_decimator.v, tb_fir_filter_bank1.v, tb_fir_filter_bank2.v
- Full re-validation: **ALL 5 MODULES PASS** (uart_tx, adc_interface, cic_decimator, fir_filter_bank1, fir_filter_bank2)
- TRAJECTORY.md written as living technical compass

---

## 2. LOCKED DESIGN DECISIONS

These are permanent. Do not revisit, suggest alternatives, or ask about them.

| Decision | Choice | Reason |
|---|---|---|
| ADC | AD9226 65MSPS | ADS1256 is 30kSPS — violates Nyquist for 40kHz signals |
| ADC clock | FPGA-generated ENCODE at 3.375MHz | Well above signal, manageable FPGA routing, yields clean CIC R=8 |
| Navigation | Custom range-only scalar state machine | nav2 requires a map; acoustic range-only homing doesn't have one |
| Telemetry | WiFi only | Pool distances don't need LoRa range |
| Motors | Brushed DC + L298N | Simpler than brushless; sufficient torque for pool |
| Acoustic path | AIR, above waterline | Avoids hull penetration, waterproofing complexity |
| OS | Ubuntu 24.04.4 LTS | ROS 2 Jazzy compatibility confirmed; Debian Trixie rejected |
| FPGA decimation | CIC R=8 (3.375MHz→421,875SPS) | Fits in BSRAM, preserves 40kHz band, avoids 65MSPS direct processing |
| Bearing method | Range-only scalar (V1) | TDOA dual-receiver is a V2 enhancement, not needed for demo |
| Coefficient format | Signed-16 integer scale (NOT Q1.15) | Q1.15 scaling is applied internally in the FIR MAC; output is integer. Matched filter must match. |
| FIR selectivity | ~2–3dB pre-selection only | 32 taps at 421,875Hz cannot achieve 30dB at 8kHz separation (normalized gap ~0.019, filter resolution ~0.031). Matched filter provides the real band discrimination. |
| snapd | REMOVED permanently | Caused watchdog timeouts on Pi |

---

## 3. CURRENT MODULE STATE

### Signal flow (only valid build order):
```
AD9226 → adc_interface → cic_decimator → fir_bank1/fir_bank2 (parallel)
       → matched_filter×2 → peak_detector/TOF → uart_tx → Pi
```

### Module-by-module status

#### `uart_tx.v` — ✅ DONE & VERIFIED (Jun 8 / Jun 13)
- **Function:** 8N1 UART transmitter, 115,200 baud, 8-byte back-to-back packets
- **Key params:** `CLKS_PER_BIT=234`, 27MHz clock → 115,384 baud (+0.16% error)
- **Ports:** `clk`, `rst_n`, `tx_start`, `tx_data[7:0]`, `tx` (serial out, idles HIGH), `tx_busy`
- **Packet format:** `[target_id:1][peak_lag_H][peak_lag_L][corr_peak_H][corr_peak_L][snr][checksum][0xFF]` — bytes 2–3 carry `peak_lag` (diagnostic sample index, per FC-5); **packet structure is unchanged from original design**, only Pi-side interpretation of bytes 2–3 changes (NOT range_cm)
- **Constraint:** `uart_tx.cst` — clk=pin4, tx=pin86, rst_n=pin88
- **Verified:** 8-byte back-to-back packet, inter-byte gap <<1 bit period, no X/Z

#### `adc_interface.v` — ✅ DONE & VERIFIED (Jun 9 / Jun 13)
- **Function:** AD9226 parallel capture; generates ENCODE clock; converts offset-binary to two's-complement; 7-cycle pipeline latency alignment; propagates OTR flag
- **Key params:** `CLK_DIV_HALF=4` → 3.375MHz ENCODE from 27MHz system clock
- **Ports:** `clk`, `rst_n`, `adc_data[11:0]`, `otr` → `adc_clk`, `sample_out signed[11:0]`, `sample_otr`, `sample_valid`
- **Critical:** MSB-flip `{~adc_data[11], adc_data[10:0]}` converts offset binary (DFS=AVSS) to two's-complement. Only correct if DFS strapped to AVSS (→ PV-2)
- **Constraint:** `adc_interface.cst` — D[0..11]=pins 73,74,75,85,77,27,28,25,26,29,30,31; otr=pin80; adc_clk=pin76; all LVCMOS33; DRIVE=8 on adc_clk
- **Verified:** MSB-flip conversions (0x800→0x000, 0xFFF→0x7FF, 0x000→0x800), OTR alignment, no X/Z

#### `cic_decimator.v` — ✅ DONE & VERIFIED (Jun 9 / Jun 13)
- **Function:** 3-stage CIC, R=8 decimation (3.375MHz → 421,875SPS), N=3 integrators+combs, 28-bit datapath
- **Key math:** B_max=12+3×log2(8)=21 bits; shift=5 (lands MSB at bit 15); DC gain=R^N=512; saturation clamp on output
- **Ports:** `clk`, `rst_n`, `din signed[11:0]`, `din_valid`, `otr_in` → `dout signed[15:0]`, `dout_valid`, `otr_out`
- **OTR:** OR-latches across entire R-sample window; one over-range sample taints the whole output
- **Verified:** DC gain 4096 confirmed, R=8 decimation verified, OTR propagation PASS, no X/Z

#### `fir_filter_bank1.v` — ✅ DONE & VERIFIED (Jun 10 / Jun 13)
- **Function:** 32-tap Hamming windowed-sinc bandpass, 34–38kHz (Buoy 1), fs=421,875Hz, sequential 1-MAC-per-clock
- **Coefficients (Q1.15 applied internally):** `-21,4,41,90,135,144,87,-45,-221,-381,-451,-380,-166,134,422,598,598,422,134,-166,-380,-451,-381,-221,-45,87,144,135,90,41,4,-21`
- **Output:** Signed-16 INTEGER scale (NOT Q1.15 — >>>15 already applied internally)
- **Ports:** `clk`, `rst_n`, `din signed[15:0]`, `din_valid`, `otr_in` → `dout signed[15:0]`, `dout_valid`, `otr_out`
- **Resources:** ~1 HW multiplier (time-shared), ~120 LUTs, 0 BSRAM
- **Latency:** ~35 system clocks per sample
- **Verified:** Passband 36kHz preserved (peak 4729), relative selectivity vs adjacent band, OTR PASS, no X/Z

#### `fir_filter_bank2.v` — ✅ DONE & VERIFIED (Jun 10 / Jun 13)
- **Function:** 32-tap Hamming windowed-sinc bandpass, 42–46kHz (Buoy 2), fs=421,875Hz, sequential 1-MAC-per-clock
- **Coefficients (Q1.15 applied internally):** `-36,-54,-59,-33,42,150,233,219,70,-177,-411,-500,-365,-39,337,587,587,337,-39,-365,-500,-411,-177,70,219,233,150,42,-33,-59,-54,-36`
- **Output:** Signed-16 INTEGER scale (same as bank1)
- **Ports:** identical structure to fir_filter_bank1
- **Resources:** ~1 HW multiplier (time-shared), ~120 LUTs, 0 BSRAM
- **Verified:** Passband 44kHz preserved (peak 4766), relative selectivity, OTR PASS, no X/Z

#### `matched_filter.v` ×2 — ⏳ NOT STARTED (CRITICAL PATH)
- **Function:** Sliding 800-sample BSRAM correlation against LFM reference chirp; outputs peak position and correlation magnitude
- **Requirements from forward constraints:**
  - FC-1: Reference chirp stored in INTEGER scale (not Q1.15)
  - FC-2: Must carry `otr_in`/`otr_out` ports end-to-end
  - FC-3: TOF math uses 421,875Hz exactly
  - 800-sample correlation window (2ms × 421,875SPS ≈ 843 samples; round to 800)
  - Pipeline all MAC chains — no combinational MAC
  - BSRAM for reference chirp arrays
- **Input:** FIR bank dout (signed-16 integer), dout_valid, otr_out
- **Output:** `corr_peak` (32-bit peak magnitude — primary homing signal), `snr` (8-bit peak-to-noise ratio — proximity proxy), `peak_lag` (16-bit sample index — **diagnostic only**, do NOT convert to range_cm per FC-5), `otr_out` propagated

#### `peak_detector.v` — ⏳ NOT STARTED
- **Function:** Finds peak in matched filter correlation output; outputs `corr_peak`/`snr` as primary navigation signals; `peak_lag` kept as diagnostic only
- **Primary outputs:** `corr_peak` (32-bit magnitude — the homing gradient), `snr` (8-bit peak-to-noise — proximity proxy; monotonic with proximity: closer buoy → higher SNR), `peak_lag` (16-bit sample index at peak — diagnostic hook for V2 TDOA upgrade, **do NOT convert to meters**)
- **Requirements:** FC-2 (OTR propagates through); FC-3 (421,875Hz for any lag-to-time diagnostic only); FC-5 (no absolute ToF — do not compute or output range_m); FC-6 (SNR is the primary homing signal)
- **Critical:** Absolute one-way ToF is impossible — buoy and vehicle share no time reference. `peak_lag` is a relative correlation phase offset within the capture window, NOT a distance. See FC-5.

#### Full pipeline integration — ⏳ NOT STARTED
- Blocked on matched filter and peak detector
- Must delete `fir_test_top.v` before synthesis (FC-4/FC-5)
- Both .cst files are in place — synthesis-ready once pipeline logic is complete

---

## 4. PIPELINE ARCHITECTURE — The 6 Validation Agents

The project uses a 6-agent pipeline for validating and building FPGA modules:

### Stage 1A: `hw-validation`
- Validates electrical interfaces, voltage compatibility, timing, pin assignments
- Checks datasheets for: voltage levels, signal swing, loading, timing specs
- Produces: list of hardware blockers and warnings
- Runs BEFORE code is committed to hardware

### Stage 1B: `dsp-signal-validator`
- Validates mathematical/algorithmic correctness of DSP modules
- Checks: number formats, bit widths, overflow/underflow, signal chain correctness
- Does NOT check electrical interfaces or code style
- Produces: list of DSP blockers, warnings, and notes

### Stage 1C: `systems-integrator`
- Runs AFTER both hw-validation AND dsp-signal-validator
- Reconciles the two validator outputs, checks for conflicts
- Cross-checks against full system mission (range, latency, resource budget)
- Produces: consolidated fix list with prioritized BLOCKERs, WARNINGs, NOTEs, and FORWARD CONSTRAINTs

### Stage 2: `fpga-verilog-engineer`
- Receives the consolidated fix list from systems-integrator (NOT raw validator outputs)
- Implements all fixes to Verilog modules and testbenches
- Writes new modules on request (with testbenches)
- Simulates with iverilog before declaring done
- Reports READY FOR verilog-sim-runner when implementation is complete

### Stage 3: `verilog-sim-runner`
- Runs AFTER fpga-verilog-engineer reports ready
- Executes all iverilog simulations
- Checks for X/Z states
- Produces: PASS/FAIL report per module, reports ALL PASS or lists failures

### Stage 4: `docs-updater`
- Runs AFTER verilog-sim-runner reports ALL PASS
- Updates CLAUDE.md build status (⏳ → ✅)
- Logs progress entries in docs/progress.md
- Corrects hardware specs when validators find datasheet conflicts
- Updates resource utilization and latency tables

**Pipeline invocation order:** hw-validation + dsp-signal-validator (parallel) → systems-integrator → fpga-verilog-engineer → verilog-sim-runner → docs-updater

---

## 5. WEEK-BY-WEEK PLAN TO AUGUST 10

### Week 4 (Jun 15–21) — Matched Filter Correlators [CURRENT]
**Priority: Build matched_filter.v ×2 + testbenches**
- [ ] `matched_filter.v`: 800-sample sliding correlator, BSRAM reference chirp, integer scale (FC-1), OTR ports (FC-2), pipeline MAC
- [ ] `tb_matched_filter.v`: simulate both channels, verify peak detection, no X/Z
- [ ] Run full pipeline: hw-validation → dsp-signal-validator → systems-integrator → fpga-verilog-engineer → verilog-sim-runner
- [ ] Place pending Amazon orders: brushed DC thrusters ×2, L298N, MAX9814, JSN-SR04T, IP65 enclosure
- [ ] Coordinate Home Depot run with Dad: PVC pipe, end caps, L-brackets, epoxy, silicone

### Week 5 (Jun 22–28) — Peak Detector + TOF + Integration [MILESTONE]
- [ ] `peak_detector.v` + TOF calculator: 421,875Hz sample rate (FC-3), multipath-aware threshold (FC-4)
- [ ] Delete `fir_test_top.v` from fpga/src/ (FC-5)
- [ ] Full pipeline integration: chain AD9226 → CIC → FIR banks → matched filters → TOF → uart_tx
- [ ] End-to-end latency verification
- [ ] Gowin EDA synthesis on full design: verify positive timing slack at 27MHz
- [ ] Resource utilization check: confirm fits within 48 HW multipliers, 46 BSRAM

### Week 6 (Jun 29–Jul 5) — ESP32 micro-ROS + Buoy Firmware
- [ ] ESP32 #1 (vehicle): micro-ROS, L298N H-bridge, MPU-6050 IMU (I2C), JSN-SR04T
  - Publishes: /imu/data (100Hz), /odom (50Hz)
  - Subscribes: /cmd_vel (Twist)
- [ ] ESP32 #2 (buoys): LFM chirp generation via MOSFETs
  - Buoy 1: 34–38kHz LFM sweep, 3× TCT40-16T at 120° spacing
  - Buoy 2: 42–46kHz LFM sweep, 3× TCT40-16T at 120° spacing
- [ ] Hardware bring-up: wire AD9226 to FPGA — clear PV-1/PV-2/PV-3 first (see Section 6)

### Week 7 (Jul 6–12) — ROS 2 Nodes + PID Homing
- [ ] `fpga_uart_node` (Pi, Python): reads /dev/ttyAMA0 at 115,200 baud, parses 8-byte packets
  - Publishes: /acoustic/range_m (Float32, 20Hz), /acoustic/snr (Float32, 20Hz)
- [ ] `acoustic_homing_node`: SCANNING→ACQUIRING→HOMING→ARRIVED→PAUSING state machine
  - Subscribes: /acoustic/range_m, /acoustic/snr, /odometry/filtered
  - Publishes: /cmd_vel (Twist)
- [ ] `dead_reckoning_node`: robot_localization EKF, fuses /imu/data + /wheel/velocity
- [ ] `collision_safety_node`: /collision/range_cm < 25cm → ESTOP override on /cmd_vel
- [ ] PID tuning loop on acoustic range error → differential thrust

### Week 8 (Jul 13–19) — Mission State Machine + Shore Display
- [ ] `mission_state_machine` node: INIT→SCAN_1→HOMING_1→ARRIVED_1→SCAN_2→HOMING_2→ARRIVED_2
- [ ] `motor_driver_node`: /cmd_vel → L298N PWM
- [ ] `telemetry_node`: mission state + range over WiFi to Arduino Uno R4 WiFi
- [ ] Arduino Uno R4 WiFi: receives mission state over WiFi, displays on LED matrix
- [ ] Hull assembly with Dad: PVC pontoons, cross members, mast, electronics bay

### Week 9 (Jul 20–26) — Pool Test #1 [MILESTONE]
- [ ] Full system integration on hull
- [ ] Pool test: buoy homing sequence end-to-end
- [ ] Record rosbag2 for post-analysis
- [ ] Document failures for Week 10 iteration

### Week 10 (Jul 27–Aug 2) — Pool Test #2 + Tuning
- [ ] Address Week 9 failures
- [ ] PID tuning, acoustic threshold tuning, multipath mitigation
- [ ] Second pool test

### Week 11 (Aug 3–9) — Polish + Demo Video
- [ ] Demo video production
- [ ] Documentation cleanup
- [ ] Final pool run for camera

**August 10:** Hard deadline — demo must be complete

---

## 6. FORWARD CONSTRAINTS (from TRAJECTORY.md — mandatory)

Every future agent touching the FPGA pipeline must read and respect all of these.

### FC-1 — Coefficient & sample format is signed-16 INTEGER, NOT Q1.15
FIR coefficients are Q1.15 internally, but the `>>>15` shift is applied inside the MAC,
so FIR dout is a **plain signed-16 integer sample** (gain ~0.20, not full-scale). Every
module downstream of the FIR banks — especially matched_filter — must use the same
integer scale for its reference chirp. Do not reintroduce Q1.15 scaling at any stage boundary.

### FC-2 — OTR (over-range) must propagate end-to-end
Every pipeline stage from `adc_interface` onward must carry `otr_in`/`otr_out` ports.
The over-range flag travels the full chain to `uart_tx` so the Pi can flag saturated
readings in the packet. A new module without OTR ports is incomplete by definition.
Current propagation: adc_interface→cic_decimator→fir_bank1/2 ✅. Still needed: matched_filter, peak_detector, uart_tx (packet byte).

### FC-3 — Sample rate is exactly 421,875 samples/sec
Use `27,000,000 / 8 / 8 = 421,875 Hz` — not "422 kSPS" or "400 kSPS".
This sample rate governs the correlation window size and any lag-to-time diagnostic conversion.
**FC-5 supersedes the `÷ 2` range formula** that previously appeared here — do not use `(peak_lag / 421875) × 343 / 2` to produce range_cm; absolute ToF is physically impossible for this system.

### FC-4 — fir_test_top.v must be deleted before integration
`fir_test_top.v` is a timing-wrapper artifact from FIR isolation testing. It must NOT
appear in the Gowin synthesis file list. Delete it before building the full pipeline.

### FC-5 — Ranging Method Correction: NO absolute ToF; `peak_detector.v` outputs corr_peak + snr, not range_cm
**Supersedes the `÷ 2` range formula previously in FC-3.**

Buoys transmit LFM chirps continuously and autonomously. The vehicle has no shared time reference with any buoy (GPS-denied, no radio time-sync, no wired link). `T_transmit` is therefore unknown — **absolute one-way ToF is impossible**. The `÷ 2` round-trip model has no physical meaning either (the vehicle does not transmit; the buoy does not echo).

What the matched filter peak actually is: the correlation lag gives the **sample offset within the 800-sample capture window** at which the received chirp best aligns with the stored reference, plus the **peak magnitude (correlation energy → SNR)**. The lag drifts and wraps because clocks are unsynchronized; it cannot be anchored to a true `T_transmit`.

**`peak_detector.v` must output:**
- `corr_peak` (32-bit peak magnitude) — **primary navigation signal**
- `snr` (8-bit peak-to-noise ratio) — **proximity proxy; monotonic with proximity** (closer buoy → higher received SPL → higher correlation energy)
- `peak_lag` (16-bit sample index) — **diagnostic only**; kept as hook for V2 TDOA dual-receiver upgrade; **do NOT convert to meters**; do NOT gate any V1 state transition on it
- `target_id` and OTR still propagate (per FC-2)

**FPGA pipeline impact: NONE structural.** Build the matched filter and peak detector exactly as planned. Only the labeling and Pi-side interpretation of the output changes.

### FC-6 — `acoustic_homing_node` uses SNR-gradient homing, not range-PID
The state machine shape (SCAN→ACQUIRE→HOME→ARRIVE) is unchanged, but the homing signal changes:

- **SCANNING:** rotate 360°, log `snr(θ)` per heading; lock onto `θ*` that maximizes SNR for the active `target_id` band
- **ACQUIRING:** confirm SNR exceeds the lock threshold for N consecutive readings at `θ*`; multipath pool-wall reflections sit ~20–30% below direct-path peak — set threshold above that floor
- **HOMING:** drive forward on `θ*`; run **gradient ascent on SNR** (not PID-on-range); differential thrust corrects heading to keep SNR climbing; EKF dead-reckoning still smooths between pings
- **ARRIVED trigger MUST change:** `range < 0.4 m for 3 readings` is not computable without absolute range. Replace with **SNR plateau / saturation trigger**: SNR exceeds a high "very-close" threshold (and/or OTR asserts from high SPL) for 3 consecutive readings. Calibrate empirically at pool test #1 (see CQ-1 in TRAJECTORY.md).

**ROS 2 topic rename:** `/acoustic/range_m` → **`/acoustic/corr_snr`** (Float32, 20 Hz). The `range_cm` bytes in the UART packet may be republished as `/acoustic/peak_lag` (diagnostic only — do NOT label as meters). The **8-byte UART packet structure is unchanged**; only Pi-side interpretation of bytes 2–3 changes.

---

## 7. PHYSICAL VERIFICATION QUEUE (before first hardware power-on)

Complete ALL three checks with a multimeter before applying power to the wired AD9226.
Getting any one wrong risks FPGA GPIO damage or silently wrong data.

| # | Check | Required reading | Why it matters |
|---|---|---|---|
| PV-1 | AD9226 DRVDD rail | **3.3V** (NOT 5V) | Sets D[11:0]/OTR output swing. 5V exceeds Tang Nano 20K LVCMOS33 GPIO → risk of damage |
| PV-2 | DFS pin strap | tied to **AVSS** (ground), NOT AVDD | Determines offset-binary vs two's-complement output. Software MSB-flip `{~data[11], data[10:0]}` is ONLY correct for DFS=AVSS |
| PV-3 | OEB pin | tied **LOW** | If HIGH, D[11:0] outputs are tristated — FPGA reads floating/garbage |

---

## 8. RESOURCE BUDGET

**Tang Nano 20K (GW2AR-18) resources:**
- HW Multipliers: 48 total
  - FIR bank1: ~1 (time-shared)
  - FIR bank2: ~1 (time-shared)
  - Matched filter ×2: TBD (each correlator needs 1 pipelined 16×16 multiplier, time-shared)
  - Estimated total: ~4–6 of 48 (large margin)
- BSRAM: 46 × 18Kbit = 828Kbit total
  - CIC: 0 BSRAM used
  - FIR banks: 0 BSRAM (coefficients are compile-time constants in case-statement ROM)
  - Matched filter reference chirps: 2 × 800 samples × 16 bits = 25,600 bits → 2 BSRAM blocks
  - Correlation window buffers: 2 × 800 samples × 16 bits = 25,600 bits → 2 BSRAM blocks
  - Estimated total: ~4 of 46 BSRAM blocks
- LUT4s: 20,736 total — FIR banks ~240 LUTs combined; large margin

**Verified as of Jun 13:** 2/48 HW multipliers, 0/46 BSRAM (FIR + CIC + ADC + UART only)

---

## 9. HARDWARE STACK QUICK REFERENCE

### FPGA — Tang Nano 20K (GW2AR-18)
- Clock: 27MHz onboard oscillator (pin 4)
- Toolchain: Gowin EDA (.cst constraints, NOT .xdc or .ucf)
- GPIO: LVCMOS33 on all header pins (J5/J6)
- Key pins: clk=4, rst_n=88(S1), tx=86(J5), D[0..11]=J6 pads, otr=80, adc_clk=76

### ADC — AD9226 12-bit 65MSPS
- Driven at 3.375MHz ENCODE (27MHz/8 from FPGA)
- Data latency: 7 ENCODE cycles (datasheet Rev B)
- AVDD=5V, DRVDD=3.3V (verified via PV-1), OEB=LOW (PV-3), DFS=AVSS (PV-2)
- Output: offset binary → FPGA converts via MSB-flip

### Signal chain: TCT40-16R → MAX9814 preamp → AD9226 → FPGA (via J6 header)

### Pi — Raspberry Pi 4 1GB
- Ubuntu 24.04.4 LTS, ROS 2 Jazzy
- SSH: `<pi-user>@<pi-hostname>.local`
- UART: `/dev/ttyAMA0` at 115,200 baud (freed Jun 8)
- ROS_DOMAIN_ID: set consistently across Pi and laptop

### Parts NOT yet ordered (must order ASAP)
1. Brushed DC thrusters ×2 (545 12V underwater)
2. L298N dual H-bridge module
3. MAX9814 pre-amp module
4. JSN-SR04T waterproof ultrasonic sensor
5. IP65 waterproof enclosure + M12 cable glands
6. PVC pipe, end caps, L-brackets, epoxy, silicone (Home Depot run with Dad)

---

## 10. CODING STANDARDS (enforced — never deviate)

### Verilog
- Non-blocking assignments (`<=`) in ALL clocked always blocks
- Every module MUST have a companion testbench in `fpga/sim/`
- Simulate before declaring done: `iverilog -o fpga/sim/out fpga/sim/tb_X.v fpga/src/X.v && vvp fpga/sim/out`
- Check for X/Z states — uninitialized signals are bugs
- Constraint files: `.cst` format ONLY (Gowin) — never .xdc or .ucf
- Target clock: 27MHz, period 37.037ns
- Signed-16 integer scale for FIR output and matched filter (NOT Q1.15 — see FC-1)
- Pipeline ALL multiply-accumulate chains — never combinational MAC
- Use BSRAM for large arrays (reference chirps, correlation windows) — not distributed LUTs
- Synthesizable ROM pattern: use `function`-based case-statement ROM (Gowin ignores `initial` blocks)

### Python / ROS 2
- ROS 2 Jazzy node structure with explicit QoS profiles
- BEST_EFFORT for sensor streams (/imu, /range, /collision)
- RELIABLE for commands (/cmd_vel, state transitions)
- Set ROS_DOMAIN_ID consistently across all nodes
- Record rosbag2 during all testing sessions

---

## 11. FILE STRUCTURE

```
asv-project/
├── CLAUDE.md                          ← Hardware contracts, locked decisions, build status
├── fpga/
│   ├── src/
│   │   ├── uart_tx.v                  ✅ DONE
│   │   ├── adc_interface.v            ✅ DONE
│   │   ├── cic_decimator.v            ✅ DONE
│   │   ├── fir_filter_bank1.v         ✅ DONE
│   │   └── fir_filter_bank2.v         ✅ DONE
│   ├── sim/
│   │   ├── tb_uart_tx.v               ✅ DONE
│   │   ├── tb_adc_interface.v         ✅ DONE
│   │   ├── tb_cic_decimator.v         ✅ DONE
│   │   ├── tb_fir_filter_bank1.v      ✅ DONE
│   │   └── tb_fir_filter_bank2.v      ✅ DONE
│   └── constraints/
│       ├── uart_tx.cst                ✅ DONE (pin 4/86/88)
│       └── adc_interface.cst          ✅ DONE (14 pins, all LVCMOS33)
├── ros2_ws/src/                       ⏳ Not started
├── esp32/                             ⏳ Not started
├── hub/
│   ├── asv_hub_v2.html               ← Current working version
│   └── asv_hub_v3.html               ← Build target
└── docs/
    ├── progress.md                    ← Daily progress log
    ├── TRAJECTORY.md                  ← Cross-module technical contracts (FC-#, PV-#)
    ├── CONSOLIDATED_CONTEXT.md        ← This file
    └── week_N_audit.md                ← Weekly audit reports
```

---

## 12. CRITICAL PATH WARNING

**The matched filter correlators are now the single most time-sensitive deliverable.**

- Two weeks of schedule carryover already exist
- Weeks 3–6 are reserved as FPGA-focused — ROS 2 work deferred until FPGA pipeline is done
- The matched filter is the hardest DSP block in the project
- If it slips into Week 5, everything downstream (integration, synthesis, pool tests) compresses
- Week 4 must start the matched filter immediately — no other FPGA work takes priority

**Do not start ROS 2 nodes, ESP32 firmware, or hull work until the matched filter is verified.**
