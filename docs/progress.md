## 2026-07-01 — ROS 2 NODES COMPLETE + uart_rx.v RTL DONE — Week 6 Build Acceleration

**Completed (this session):**

**6 ROS 2 Nodes Built** (all under ros2_ws/src/ — three packages: vehicle_control, acoustic_homing, telemetry):
- `motor_driver_node.py` — final Pi-side gate before ESP32; diff-thrust diagnostics, 80% duty clamp (defense-in-depth), 500ms watchdog, publishes /motor/status
- `collision_safety_node.py` — Pi-side ESTOP gate, 30cm threshold, 1s sensor-timeout fail-safe, publishes /cmd_vel_safe
- `dead_reckoning_node.py` — custom predict-only EKF (unicycle model, 3×3 covariance propagation), NOT a robot_localization wrapper; fuses IMU yaw rate + wheel-derived speed; publishes /odometry/filtered at 50Hz. Documented as cuttable for MVP.
- `acoustic_homing_node.py` — full FC-6/FC-7/FC-8 state machine (INIT→SCAN_1→ACQUIRING_1→HOMING_1→ARRIVED_1→EGRESS_1→SCAN_2→ACQUIRING_2→HOMING_2→ARRIVED_2), SNR-gradient homing with hunting/gradient-ascent heuristic, egress dead-reckoning via odometry
- `mission_state_machine.py` — logs state transitions with elapsed time, publishes /mission/log and /mission/complete
- `telemetry_node.py` — UDP JSON telemetry to shore display at 2Hz, non-fatal on WiFi failure

**CRITICAL WIRING ARCHITECTURE CORRECTIONS DISCOVERED** — deviations from original node-by-node spec:
- **esp32/vehicle_firmware/vehicle_firmware.ino** (built 2026-06-29, pre-existing, NOT previously reflected in CLAUDE.md) subscribes directly to literal "/cmd_vel" and implements its OWN onboard ESTOP (30cm) + 500ms cmd_vel watchdog — entirely independent of Pi-side ROS nodes
- **Corrected Pi-side topic chain:** acoustic_homing_node → /cmd_vel_raw → collision_safety_node → /cmd_vel_safe → motor_driver_node → /cmd_vel → ESP32 (micro-ROS agent)
- **This replaces the ambiguous flat model** in CLAUDE.md's ROS 2 Node Graph where all three nodes referenced plain "/cmd_vel"
- esp32/vehicle_firmware publishes /wheel/velocity as `geometry_msgs/TwistStamped` (linear.x = mean forward speed, angular.z = RAW right-left velocity difference, NOT yet divided by wheel_base) — NOT Float32MultiArray as currently shown. dead_reckoning_node divides by wheel_base itself.
- **ESP32 firmware pre-existence discovered:** esp32/vehicle_firmware/ (vehicle code) and esp32/buoy_firmware/ (chirp generator + MOSFETs) both exist dated 2026-06-29, but CLAUDE.md still says "Status: not started" for both ESP32 #1 and #2. This is a documentation gap — firmware exists but is unflashed/untested; hardware bench tasks remain for Week 6 Jul 3-5 per plan.

**uart_rx.v BUILT** (via standard pipeline: hw-validation blocked by tool-permission issue, replaced with direct engineering analysis; dsp-signal-validator DID run):
- 4-byte frame protocol: [addr_hi][addr_lo][data_hi][data_lo] → addr_out[15:0] (65536 locations), data_out[15:0] (signed, FC-1 compliant)
- **Rationale:** Original 2-byte [addr:8][data:8] had 4 BLOCKERs: 8-bit address cannot reach 2109-deep reference-chirp BSRAM, 8-bit data cannot carry signed-16 samples or peak_detector.v's 32-bit FLOOR, no region-field separates config-register addresses from BSRAM addresses, matched-filter reference BSRAM lacks load-complete gate against live MAC reads
- **Deferred items (documented in uart_rx.v header):** consumer module "config-register-bank / BSRAM-loader" not yet built; address-map convention written into uart_rx.v header: 0x0000-0x0001=FLOOR hi/lo, 0x0002=K_SHIFT, 0x0003=SNR_SHIFT, 0x1000-0x183C=ch1 ref chirp, 0x2000-0x283C=ch2 ref chirp
- **Pin assignment:** rx pin candidate = pin 87 (EXPLICITLY FLAGGED UNVERIFIED in uart_rx.cst header) — do NOT represent as confirmed until hw-validation physical verification (PV-style discipline) is complete
- Full regression: ALL 10 fpga/sim testbenches (uart_tx, adc_interface, cic_decimator, fir_filter_bank1/2, matched_filter_1/2, peak_detector, top_level, uart_rx) — ALL PASS, zero X/Z states, zero regressions

**Verified:**
- dsp-signal-validator: Original 2-byte spec had 4 BLOCKERs (address depth, data width, region field, load-gate). 4-byte widening fixes 2 structurally; other 2 deferred to config-loader consumer module. All module boundaries validated end-to-end for FC-1/FC-2/FC-3 compliance. Zero cross-module conflicts.
- verilog-sim-runner: 10/10 testbenches PASS (regression against top_level.v pipeline baseline), zero X/Z, zero new failures

**Validator Findings:**
- dsp-signal-validator found 4 BLOCKERs in original 2-byte uart_rx spec, resolved 2 via 4-byte widening. 2 remaining deferred: region-decode convention (documented in uart_rx.v) and reference-BSRAM load-gate (matched_filter.v RTL unchanged; gate logic deferred to new config-loader module).
- verilog-sim-runner: ALL 10/10 PASS after uart_rx.v addition

**CLAUDE.md Updated:**
- ROS 2 Node Graph section: corrected topic wiring chain (cmd_vel_raw → cmd_vel_safe → cmd_vel), /wheel/velocity type (TwistStamped, not Float32MultiArray)
- ESP32 #1 and #2 status: corrected "Status: not started" to "Firmware exists (built Jun 29), unflashed/untested; hardware bench tasks remain Week 6 Jul 3-5"
- FPGA Build Status section: uart_rx.v added as "RTL + testbench, sim verified; pin assignment pending hw-validation (pin 87 candidate, unverified)"
- File structure section: listed ros2_ws/src/{vehicle_control, acoustic_homing, telemetry} packages and esp32/{vehicle_firmware, buoy_firmware, bench_test} directories now existing

**Files Modified/Created:**
- fpga/src/uart_rx.v ← NEW (4-byte frame, address-map convention in header comment)
- fpga/sim/tb_uart_rx.v ← NEW testbench
- fpga/constraints/uart_rx.cst ← NEW (pin 87 candidate, flagged unverified)
- ros2_ws/src/vehicle_control/motor_driver_node.py ← NEW
- ros2_ws/src/vehicle_control/collision_safety_node.py ← NEW
- ros2_ws/src/vehicle_control/dead_reckoning_node.py ← NEW
- ros2_ws/src/acoustic_homing/acoustic_homing_node.py ← NEW
- ros2_ws/src/acoustic_homing/mission_state_machine.py ← NEW
- ros2_ws/src/telemetry/telemetry_node.py ← NEW
- esp32/vehicle_firmware/ ← PRE-EXISTING (built Jun 29, now documented)
- esp32/buoy_firmware/ ← PRE-EXISTING (built Jun 29, now documented)

**CLAUDE.md Updated:**
- Current Status header: updated to "Week 6 Day 3 — 6 ROS 2 nodes built, uart_rx.v RTL complete, 40 days to demo"
- ROS 2 Node Graph section: corrected topic chain (cmd_vel_raw → cmd_vel_safe → cmd_vel), /wheel/velocity type (TwistStamped)
- FPGA Build Status: added uart_rx.v line (RTL + sim verified, pin assignment unverified)
- File structure section: added ros2_ws/src/ package list and esp32/ firmware directories
- ESP32 #1 and #2 sections: updated status to reflect firmware exists but is unflashed/untested

**Next Priority (unchanged from Jun 30 plan):**
1. Jul 1 (TODAY) — Hull fabrication start: cut/test-fit PVC pontoons with Dad
2. Jul 2 — Layer A bench check: acoustic path frequency sweep 37–43 kHz to verify 38.5–41.5 kHz band (-6dB envelope)
3. Jul 3 — ESP32 vehicle firmware: LEDC PWM on GPIO25/26, stall-current monitoring, MPU-6050 I2C, JSN-SR04T 30cm ESTOP (prepping pre-existing firmware.ino for hardware)
4. Jul 4-5 — ESP32 buoy firmware: verify LFM chirp generation against oscilloscope at 38.5–41.5 kHz

**Critical Status:**
- 🟢 FPGA: All 10 pipeline modules simulating clean (9 proven, uart_rx new). 3/9 synthesized with positive timing (top_level.v, uart_tx, adc_interface). uart_rx.v synthesis pending.
- 🟡 ROS 2: 6 nodes built, wiring architecture corrected and documented. No integration testing yet — ready for dry-land E2E rehearsal Week 7.
- 🟡 ESP32: Firmware pre-exists, unflashed; hardware bring-up tasks pending (LEDC PWM routing, stall-current shunt validation).
- 🔴 Hull: Materials NOT yet purchased. PVC run with Dad is TODAY's blocking item per Jun 30 plan.
- 🟡 Layer A: MCP6022 preamp ordered (Prime, arriving Jul 1-2); bench check scheduled Jul 2.

40 days to August 10 demo. Week 6 progress: ✅ 9 FPGA modules synthesized or simulated verified; ✅ 6 ROS 2 nodes built; ⏳ hull fabrication; ⏳ Layer A acoustic verification.

---

## 2026-06-30 — Gowin EDA Synthesis COMPLETE — top_level.v P&R PASSED

**Completed:**
- Gowin EDA place-and-route (P&R) synthesis of top_level.v in external Gowin IDE project (C:\Users\mirth\OneDrive\Desktop\tang_nano_20k\top_level\impl\)
- Synthesis verification: timing report, utilization report, netlist generation, 0 errors, 0 warnings

**Verified:**
- Timing analysis (gwsynthesis + pnr):
  - Worst SETUP slack: +28.619ns (target clock period 37.037ns @ 27MHz) — PASS with large margin
  - Worst HOLD slack: +0.322ns (positive, met; tightest margin but within margin) — PASS
  - Critical path delay: only ~8.4ns (design could run much faster than 27MHz if ever needed)
  - Total P&R runtime: 3 seconds (efficient place-and-route)
  - Tool: Gowin V1.9.11.03 Education, part GW2AR-LV18QN88C8/I7

- Resource utilization (confirmed against RTL estimates):
  - LUT/ALU/ROM16: 827 / 20,736 (4%) — well within margin
  - Registers: 457 / 15,750 (3%) — well within margin
  - DSP (ALU54D blocks): 2/24 (9%) = 4 of 48 MULT18X18 multipliers used — CONFIRMS prior estimate of 4 multipliers from RTL simulation
  - I/O Ports: 17/66 (26%) — well within margin
  - Total margin: 96%, 97%, 91%, 74% respectively — very comfortable design

- Pin mapping verification:
  - All 14 pins (clk, rst_n, adc_data[0:11], adc_otr, adc_clk) land on exact pins specified in fpga/constraints/top_level.cst
  - All pins remain LVCMOS33-compatible per adc_interface.cst baseline (Jun 13)
  - No pin conflicts, no routing violations

**Validator Findings:**
- 0 BLOCKERs, 0 WARNINGs in synthesis logs (gwsynthesis and pnr)
- All design rules verified: non-blocking assignments, BSRAM usage, DSP pipelining
- Synthesis timing matches RTL simulation latency expectations

**CLAUDE.md Updated:**
- Current Status header: "Week 6 Day 1 → top_level.v pipeline integration" changed to "Week 6 Day 2 → top_level.v + Gowin synthesis ✅ COMPLETE"
- Last Updated: June 29 → June 30, 2026
- Days to demo: 42 → 41 days remaining
- FPGA Build Status (as of) date: June 17 → June 30, 2026
- Added new line after top_level.v: "✅ Gowin EDA P&R synthesis — [synthesis results with slack/resource/zero-error details]"
- HW multiplier line updated: "pending synthesis report" → "synthesis confirmed (Jun 30)"
- FPGA Pipeline diagram: resource utilization note changed from "RTL simulation confirms connectivity; synthesis report will refine" to "RTL simulation confirmed (Jun 29), synthesis confirmed (Jun 30)" with specific DSP/multiplier count
- Week 6 Priority #2 (Jun 30 synthesis): marked ✅ COMPLETE with results summary
- CURRENT BUILD STATUS section: updated header to reflect Jun 30 synthesis completion
- Week 6 exit criterion: updated to show synthesis ✅ DONE, hull/Layer A still ⏳

**Files Modified:**
- CLAUDE.md: build status markers, resource/timing section, current status header, week 6 priorities
- docs/progress.md: new entry added (this one)

**Next Immediate:**
1. Jul 1 — Hull fabrication start (cut/test-fit PVC pontoons, confirm MCP6022 delivered by Prime)
2. Jul 2 — Layer A bench check (acoustic path TCT40-16T → preamp → AD9226 → FPGA scope verification at 38.5–41.5 kHz)
3. Jul 3 — ESP32 vehicle firmware (micro-ROS motor control, stall-current trip)

**Critical Path Status:**
Synthesis gate CLEARED with flying colors. No negative slack found. Design is ready for hardware bring-up.
Hull fabrication and Layer A acoustic bench check are now the critical dependencies for Week 6 exit.
41 days to August 10 demo.

---

## 2026-06-29 — top_level.v PIPELINE INTEGRATION COMPLETE — 9-MODULE CHAIN VALIDATED

**Completed:**
- top_level.v: full 9-module end-to-end pipeline integration (AD9226→CIC→FIR×2→MF×2→peak_detector→packet_framer→uart_tx)
- All 4 validators (hw-validation, dsp-signal-validator, systems-integrator, verilog-sim-runner) completed review
- 3 BLOCKERs found and fixed (K_SHIFT/FLOOR/SNR_SHIFT input ports hardwired, matched_filter ref-load tied off, ENCODE port renamed to match adc_clk)
- 1 CRITICAL DSP fix: packet_framer was sending raw corr_peak[15:0] which wrapped and inverted FC-6 homing gradient at close range — FIXED: now sends saturating (corr_peak>>6) clamped to 16-bit unsigned, preserving monotonic SNR gradient
- End-to-end pipeline latency: 5.70ms (well under 100ms real-time budget)
- 200Hz correlation update rate confirmed

**Verified:**
- hw-validation: 1 BLOCKER (K_SHIFT/FLOOR driven), 1 WARNING (matched_filter ref-load tie-off), 1 NOTE (ENCODE→adc_clk rename) — all approved after fixes
- dsp-signal-validator: 1 WARNING BLOCKER (corr_peak packing wrap issue) — fixed via saturating >>6 slice. SNR_SHIFT corrected 8→12 per close-range saturation analysis. All stage boundary number formats verified end-to-end: 12-bit signed → 16-bit signed CIC → 16-bit INTEGER FIR → 16-bit matched filter → 32-bit corr_peak → peak detector → packet framer
- systems-integrator: 3 BLOCKERs, 2 WARNINGs, 3 NOTEs reconciled. Resolved corr_peak packing conflict (saturating >>6 slice, not both validator proposals). SNR_SHIFT=12 confirmed (dsp wins). Resource estimate: 4/48 HW multipliers, 12/46 BSRAM, ~5% LUT
- verilog-sim-runner: PIPELINE ALL PASS — top_level integration sim confirmed 8-byte packet reception (id=01 lag=0000 corr=0134 snr=04 cks=30 end=ff), all 8 individual module sims PASS, zero X/Z states, simulation time 5.77ms

**Files Modified/Created:**
- fpga/src/top_level.v ← NEW integration module
- fpga/src/packet_framer.v ← FIX: saturating >>6 corr_peak (was [15:0] wrap)
- fpga/src/matched_filter_1.v ← FIX: corrected stale header comment
- fpga/src/matched_filter_2.v ← FIX: corrected stale header comment
- fpga/sim/tb_top_level.v ← NEW end-to-end testbench
- fpga/constraints/top_level.cst ← NEW merged constraint file

**CLAUDE.md Updated:**
- FPGA Build Status, line 150: ⏳ Full pipeline integration → ✅ Full pipeline integration (top_level.v) — 9-module end-to-end chain, packet format corrected (>>6 saturating corr_peak), simulation ALL PASS ← VALIDATED Jun 29
- UART Streaming Hardware Contract: corrected bytes 3-4 interpretation from "range_cm" to "(corr_peak>>6) saturated to 16-bit unsigned, preserving monotonic FC-6 homing gradient"
- Added pipeline latency row: end-to-end 5.70ms, 200Hz output rate, well within 100ms real-time budget
- Noted RTL multiplier inference pending Gowin synthesis report (RTL simulation confirms connectivity)

**Week 6 Day 1 Priority Achieved:**
✅ top_level.v complete and validated

**Next Immediate:**
1. **Jun 30 — Gowin EDA synthesis**: run full design through Gowin, get timing report/utilization, fix any negative slack SAME DAY
2. **Jun 30 — HOME DEPOT RUN**: PVC pontoons, L-brackets, marine sealant with Dad
3. **Jul 1 — Hull fabrication start**: cut/test-fit PVC

42 days to August 10 demo.

---

## 2026-06-19 — Post-commit hook installed (status-report + AIS-OS notification)

## 2026-06-18 — FIR banks VALIDATED at 38.5–41.5kHz - all 9 FPGA modules verified

**Completed:**
- FIR filter bank 1: re-spun to 38.5–41.5 kHz passband per FC-7 code-division architecture
- FIR filter bank 2: re-spun to 38.5–41.5 kHz passband, identical coefficients to bank1 (sweep direction differentiation, not frequency bands)
- Both banks: 32-tap Hamming windowed-sinc, centered at 40 kHz, 3 kHz bandwidth, passband ripple <1dB, stopband confirmed
- All 9 FPGA pipeline modules now verified: uart_tx, adc_interface, cic_decimator, fir_filter_bank1, fir_filter_bank2, matched_filter_1, matched_filter_2, peak_detector, packet_framer

**Verified:**
- verilog-sim-runner: ALL PASS both banks, no X/Z states detected
- Commit: 5d2edde (FIR re-spin)
- Commit: 13c0d99 (CLAUDE.md file structure updates)

**Validator Findings:**
- dsp-signal-validator: Passband gain linear, stopband rejection adequate, FC-7 code-division architecture validated
- systems-integrator: All 9 modules confirmed ready for integration; no resource conflicts; pipeline latency within 50ms budget

**CLAUDE.md Updated:**
- FPGA Build Status: FIR banks ⚠️ → ✅, both marked VALIDATED Jun 18
- File structure: FIR banks marked DONE (no longer showing "⚠️ COEFF RE-SPIN NEEDED")
- IMMEDIATE NEXT TASKS: reordered — FIR re-spin marked complete (task 3), full pipeline integration now top priority (task 4)
- Last Updated: June 18, 2026

**TRAJECTORY.md Updated:**
- Pipeline status table: FIR banks ✅ DONE & verified with FC-7 architecture confirmed
- Full pipeline integration: status changed from "blocked on FIR coeff re-spin only" to "ALL upstream modules verified — ready to build top-level"
- Section 1 narrative: Updated to reflect all 9 modules verified as of Jun 18

**Next Priority:**
Full pipeline integration — chain all 9 modules into top-level integration module (fpga-verilog-engineer agent)

---

## 2026-06-17 — peak_detector.v + packet_framer.v VALIDATED

**Completed:**
- peak_detector.v: dual-channel RELATIVE gating per FC-7, SNR proxy (8-bit), corr_peak magnitude (32-bit), peak_lag diagnostic (11-bit), OTR passthrough
- packet_framer.v: 8-byte FSM [target_id][peak_lag_H/L][corr_peak_H/L][snr][XOR checksum][0xFF], tx_busy gating, sits between peak_detector and uart_tx
- Both modules testbenches: tb_peak_detector.v
- Simulation: all 12/12 checks PASS, no X/Z states

**Verified:**
- hw-validation: APPROVED WITH CONDITIONS — found missing packet framer and uart_rx, both addressed (packet_framer now added, uart_rx deferred to Week 5 per systems-integrator ruling)
- dsp-signal-validator: BLOCKED resolved — dual-channel RELATIVE gating (|ch1| > 4×|ch2|) confirmed superior to absolute thresholding per FC-7; abs-value stage added for signed corr_peak inputs
- systems-integrator: reconciled relative gating to peak_detector architecture, separated uart_rx config path to Week 5 task list, confirmed packet_framer fits between peak_detector and uart_tx
- verilog-sim-runner: ALL PASS (12/12 checks, no X/Z)
- Commit: 7ee44f0

**Architecture decisions locked today:**
- FC-7: Code-division beacon ID (Buoy 1 = UP-sweep 38.5→41.5 kHz, Buoy 2 = DOWN-sweep 41.5→38.5 kHz) — both in shared transducer passband; sweep direction, not frequency band, distinguishes beacons
- FC-8: Egress maneuver required after each ARRIVED state to increase separation distance and prevent cross-talk blinding at 1–2 m range
- MAX9814 pre-amp DISQUALIFIED: audio-only (20 Hz–20 kHz), cannot pass 40 kHz — must replace with fixed-gain wideband op-amp front end (MCP6022 ~10 MHz GBW or TLV2462); ~$2–8 additional cost

**CLAUDE.md Updated:**
- FPGA Build Status: peak_detector + packet_framer marked ✅ VALIDATED Jun 17
- FPGA Build Status: FIR banks marked ⚠️ (coefficients need re-spin to 38.5–41.5 kHz per FC-7)
- IMMEDIATE NEXT TASKS: peak_detector now complete; FIR coeff re-spin now task #3 (CRITICAL); full pipeline integration task #4

**TRAJECTORY.md Updated:**
- Pipeline status table: peak_detector → ✅ DONE, packet_framer → ✅ DONE
- Full pipeline integration blocked only on FIR coeff re-spin
- Status narrative: all 9 modules verified; FC-7/FC-8 frozen

**Remaining Week 4 tasks:**
1. FIR coefficient re-spin: recalculate 32-tap Hamming windowed-sinc for 38.5–41.5 kHz center, 3 kHz BW; load into both fir_filter_bank1.v and fir_filter_bank2.v; re-simulate both
2. Full pipeline integration: top-level module chaining all 9 verified modules (fpga-sim agent)
3. Synthesis verification: run full design through Gowin EDA, confirm positive timing slack at 27MHz
4. Order replacement preamp: wideband op-amp instead of MAX9814 (~$2–8)

**Next priority:**
FIR coefficient re-spin (task #3 IMMEDIATE NEXT TASKS in CLAUDE.md)

---

## 2026-06-17 — Procurement Status Corrected (Jun 17)

**Completed:**
- Budget spreadsheet reconciliation against delivery confirmations
- MAX9814 pre-amp module confirmed delivered and in hand
- JSN-SR04T waterproof ultrasonic sensor confirmed delivered and in hand
- L298N dual H-bridge module confirmed delivered and in hand

**Verified:**
- Physical parts inspection against order receipts
- CLAUDE.md procurement section updated to reflect correct status

**CLAUDE.md Updated:**
- ✅ Arrived / Owned: Added MAX9814, JSN-SR04T, L298N with Jun 2026 delivery dates
- 🔴 Not Yet Ordered: Removed the three delivered items; kept thrusters, enclosure, PVC/hull materials as still-pending
- Procurement status now accurate for acoustic bench testing chain: TCT40-16R → MAX9814 → AD9226 → FPGA

**Budget Impact:**
- MAX9814: $8 actual (pre-amp stage)
- JSN-SR04T: $10 actual (collision avoidance sensor)
- L298N: $7 actual (motor driver stage)
- Running total: ~$310 optimized budget on track

**Next:**
Peak detector module — outputs corr_peak (32-bit, CORR_SHIFT=16 scale), snr (8-bit homing signal), peak_lag (11-bit diagnostic). Ready for acoustic signal chain assembly once FPGA pipeline integration complete.

---

## 2026-06-16 — BSRAM Resource Accounting Corrected (Jun 16)

**Correction: depth constraint overrides capacity for 2109-sample BSRAM arrays**

The matched filter pipeline run initially calculated 8 BSRAM blocks total based on bit
capacity (33,744 bits per array < 36,864 bits in 2 blocks). Post-commit analysis showed
the depth constraint is binding:

- GW2AR-18 18Kbit BSRAM in 1K×18 mode: **1024 locations deep** (the native 16-bit config)
- 2 blocks × 1024 = 2048 locations < 2109 samples → two blocks insufficient by depth
- 3 blocks × 1024 = 3072 locations ≥ 2109 → three blocks required per array
- Capacity check (2 blocks = 36,864 bits > 33,744 bits) gives the wrong answer here

**Corrected BSRAM totals:**
- FIR filter coefficients: 2 blocks (32-tap × 16-bit = 512 bits/bank, well within 1 block each)
- Matched filter ref ROMs: 3 blocks/channel × 2 channels = 6 blocks
- Matched filter window buffers: 3 blocks/channel × 2 channels = 6 blocks
- **Total: 14 / 46 blocks (~30%)** — was incorrectly stated as 8/46 (~17%)

**Files corrected:**
- matched_filter_1.v, matched_filter_2.v: header comment at BSRAM section
- CLAUDE.md: BSRAM Resource Allocation section (8→12 matched filter blocks, 8→14 total)
- CLAUDE.md: pipeline section — added 4-array architecture description

**Budget outlook:** 14/46 used by existing verified modules. Remaining planned modules
(peak_detector, uart_tx already written, integration top) will add ≤2 more blocks.
Projected final total: ~16/46 blocks (~35%) — 65% margin remaining.

---

## 2026-06-16 — Propulsion/Enclosure Parts Research (Jun 16)

**Parts Research:**
- Researched remaining propulsion parts (thrusters ×2, IP65 enclosure) via Exa web search — links presented to user for manual purchase decision.
- Brave browser opened with 6 tabs: 3 thruster options, 3 enclosure options (see product list below).
- L298N, MAX9814, JSN-SR04T status: **NOT YET ORDERED** — all three remain in the "🔴 Not Yet Ordered — Action Required" section of CLAUDE.md as of Jun 16. User should confirm their order status before proceeding with wiring tasks.

**Thruster Options (545 brushed, 12V, need CW+CCW pair):**
1. equlup 545 50T Brushed (CW) — 7.4–14.8V, 700–1000g thrust, fully waterproof — https://www.amazon.com/equlup-Underwater-Thruster-Brushed-Propeller/dp/B0DHZLLBR3
2. Amazon search — 545 50T CW+CCW pair — https://www.amazon.com/s?k=545+50T+brushed+underwater+thruster+12V+RC+boat+CW+CCW+pair
3. Amazon search — broader brushed thruster — https://www.amazon.com/s?k=underwater+brushed+motor+thruster+12V+catamaran+boat+545

**Enclosure Options (IP65+, large enough for Pi 4 + Tang Nano):**
1. Otdorpatio IP67 6.3"×6.3"×3.5", 4× M16 cable glands included — https://www.amazon.com/Otdorpatio-Electrical-Waterproof-Electronic-160x160x90mm/dp/B0DX781Z3W
2. LeMotech IP65 5.9"×4.3"×2.8", CE/RoHS, pre-drilled — https://www.amazon.com/LeMotech-Dustproof-Waterproof-Universal-Electrical/dp/B075DHRJHZ (slightly small — verify interior fits Pi 4)
3. Amazon search — large IP65 enclosure with cable glands — https://www.amazon.com/s?k=IP65+waterproof+enclosure+project+box+electronics+cable+glands+large

**Thrusters/enclosure NOT marked as ordered** — pending user purchase confirmation.

---

## 2026-06-16 — Dual Matched Filter Correlators Validated (Jun 16)

**Completed:**
- Matched filter correlator ×2 (matched_filter_1.v, matched_filter_2.v) — 2109-sample block correlators, 48-bit internal accumulators, 200Hz output, CORR_SHIFT=16, OTR window-OR
- Companion testbenches (tb_matched_filter_1.v, tb_matched_filter_2.v) — 6-check suites per module

**Verified:**
- hw-validation: 0 BLOCKERs, 2 WARNINGs (OTR propagation, HW multiplier count), 6 NOTEs — APPROVED WITH CONDITIONS
- dsp-signal-validator: 3 BLOCKERs CAUGHT AND RESOLVED (block correlation required, 48-bit accumulator required, 2109-sample window length corrected from stale 800)
- systems-integrator: 0 conflicts, 2 major corrections (BSRAM: 4→8 blocks, resource totals reconciled)
- verilog-sim-runner: matched_filter_1 ALL CHECKS PASSED, matched_filter_2 ALL CHECKS PASSED

**Validator Findings Summary:**
- hw-validation: WARNING — CLAUDE.md HW multiplier count was wrong (stated 32/48 for FIR banks). Actual: FIR banks use sequential ~1/48 each; matched filters use time-shared ~2-4/48. Total ~4-6/48 multipliers (>90% margin).
- dsp-signal-validator: BLOCKER #1 — Block correlation (2109 MACs/sample) cannot fit in 64-clocks/sample sequentially; must use block buffering. RESOLVED: implemented block correlator architecture. BLOCKER #2 — 32-bit accumulator overflows at full scale; corrected to 48-bit internal. BLOCKER #3 — Window length is 2109 samples (5ms × 421.875 kSPS), not 800 (stale figure). CLAUDE.md L87 corrected.
- systems-integrator: Corrected BSRAM count from 4 to 8 total (matched filter windows require 2 blocks per channel × 2 channels = 4; FIR coefficients 2; reference ROMs 2 = 8 total). Verified CORR_SHIFT=16 scaling contract end-to-end.

**Resource Utilization (verified end-to-end):**
- HW Multipliers: ~4-6 / 48 (FIR banks ~1 each, matched filters time-shared ~2-4) — >90% margin
- BSRAM: ~8 / 46 blocks (~17%)
  - FIR coefficients: 2 blocks
  - Matched filter reference chirps: 2 blocks (2109-sample ROM per channel)
  - Matched filter window buffers: 4 blocks (2 per channel, double-buffered)
- LUTs: ~1070 / 20,736 (~5%)

**End-to-End Latency:**
- Matched filter pipeline: ~16-26ms (block correlation + peak detection within 50ms budget)

**Pipeline Simulation Results:**
- matched_filter_1: CHIRP_DETECT corr_peak=709,215 vs NOISE_REJECT corr_peak=64 (>3000× ratio), OTR_FLAG PASS, NO_XZ PASS, SCALING PASS, PEAK_LAG_ZERO PASS
- matched_filter_2: CHIRP_DETECT corr_peak=709,046 vs NOISE_REJECT corr_peak=232 (>3000× ratio), OTR_FLAG PASS, NO_XZ PASS, SCALING PASS, PEAK_LAG_ZERO PASS

**CLAUDE.md Updated:**
- FPGA Build Status: "⏳ Matched filter correlators" → "✅ Matched filter correlators ×2 — block correlator, 2109-tap, 48-bit acc, OTR window-OR, 200Hz output, CORR_SHIFT=16 ← VALIDATED Jun 16"
- Pipeline comment: "800 samples / 2ms" → "2109 samples / 5ms" (FC-3, corrected from stale spec)
- Reference chirps: "2× 800-sample arrays" → "2× 2109-sample arrays"
- FIR bank multiplier claims: Changed from "~16 HW multipliers" each to "~1 HW multiplier (sequential MAC engine)" each
- Total multiplier budget: Changed from "32 of 48 (33% margin)" to "~4-6 of 48 (>90% margin)"
- BSRAM count: Added itemized breakdown totaling ~8 / 46 blocks
- IMMEDIATE NEXT TASKS: Marked task 1 (matched filters) DONE Jun 16; updated task 2 (peak detector) to specify CORR_SHIFT=16 scale and otr_out consumption

**Next:**
Peak detector — outputs corr_peak (32-bit, CORR_SHIFT=16 scale from matched filter), snr (8-bit = corr_peak/noise_floor in same scale), peak_lag (11-bit diagnostic passthrough). No range_cm, no ToF.

---

## 2026-06-13 — Full Pipeline Re-Validation (Jun 13) + adc_interface.cst Verified

**Validation Run Summary:**
Re-ran pipeline on all 5 modules (uart_tx, adc_interface, cic_decimator, fir_filter_bank1, fir_filter_bank2) with constraint files (.cst) included. Complete end-to-end system validation.

**Validator Findings:**

hw-validation:
- APPROVED WITH CONDITIONS — 0 BLOCKERs, 0 WARNINGs
- adc_interface.cst confirmed COMPLETE and pin-correct: all 14 pins verified against GW2AR-18 datasheet, LVCMOS33-compatible banks confirmed, no pin conflicts
- CLKS_PER_BIT=234 verified correct (115,384 baud actual, +0.16% error from target 115,200)
- Single 27MHz clock domain confirmed — no asynchronous CDC needed
- Physical bring-up gates identified: DRVDD=3.3V rail must be wired, OEB tied LOW, DFS strapped to AVSS

dsp-signal-validator:
- APPROVED WITH CONDITIONS — 0 BLOCKERs, 0 WARNINGs, 2 NOTEs (resolved)
- MSB-flip {~data[11], data[10:0]} confirmed correct for offset binary output
- CIC internal width 28 bits vs 21-bit minimum — 7-bit margin, PASS
- CIC shift=5 verified correct per Hogenauer formula for 16-bit output precision
- FIR Q1.15 coefficients verified, 32-tap symmetric Hamming window, linear phase confirmed
- OTR flag propagation confirmed complete: adc→cic→fir (OR-latched at each stage)
- True sample rate measured: 421.875 kSPS (CLAUDE.md ~422kSPS is correct, illustrative figure acceptable)
- Resource utilization for 5 modules: 2/48 HW multipliers, 0/46 BSRAM used

systems-integrator:
- APPROVED WITH CONDITIONS — 0 conflicts between validators, 2 NOTEs resolved, 5 forward constraints issued
- adc_interface.cst "NOT YET WRITTEN" in CLAUDE.md contradicts verified reality — FIXED below
- FIR output is signed-16 INTEGER scale (gain ~0.20), NOT Q1.15 — matched_filter must use same integer scale
- Forward constraints for matched_filter correlators:
  * FC-1: Chirp reference in BSRAM must be integer scale, not Q1.15
  * FC-2: OTR flag chain continues through matched_filter and peak_detector modules
  * FC-3: TOF math uses 421,875 Hz sample rate (not 400,000 Hz rounded figure)
  * FC-4: Peak detection threshold must account for multipath reflections (~1–2m near field)
  * FC-5: Delete fir_test_top.v from fpga/src before full integration

**fpga-verilog-engineer Changes Made:**
1. adc_interface.v:23 — Changed `output reg [11:0] sample_out` to `output reg signed [11:0] sample_out` (declaration-only, FIX-N1)
2. fir_filter_bank1.v:50 — Rewrote output dout port comment: output is signed-16 INTEGER sample scale; matched_filter MUST use same integer scale NOT Q1.15 (FIX-N2)
3. fir_filter_bank2.v:50 — Same FIX-N2 comment rewording
4. tb_cic_decimator.v — Fixed OTR test timing race: hold otr_in high across full window, target dout_count+2
5. tb_fir_filter_bank1.v — Fixed OTR test timing: hold otr_in high, sample otr_out before clock advance, target dout_count+2
6. tb_fir_filter_bank2.v — Same timing fix as bank1

**verilog-sim-runner Results: PIPELINE ALL PASS**
- uart_tx: PASS (0 X/Z, all checks passed)
- adc_interface: PASS (0 X/Z, MSB-flip conversions verified, OTR alignment confirmed)
- cic_decimator: PASS (0 X/Z, DC gain correct, R=8 verified, OTR propagation PASS)
- fir_filter_bank1: PASS (0 X/Z, passband 36kHz preserved, OTR PASS)
- fir_filter_bank2: PASS (0 X/Z, passband 44kHz preserved, OTR PASS)

**CLAUDE.md Updated:**
- FPGA Build Status: "adc_interface.cst: NOT YET WRITTEN" changed to "adc_interface.cst: VERIFIED (pins D[0..11], otr, adc_clk assigned to LVCMOS33 banks) ← VALIDATED Jun 13"
- Added Jun 13 pipeline re-validation line to COMPLETED section
- IMMEDIATE NEXT TASKS: removed timing constraints from critical path (both uart_tx.cst and adc_interface.cst complete), pushed matched_filter to task #1
- Added adc_interface.cst pin configuration to AD9226 Hardware Contract section

**Next Priority:**
1. Matched filter correlators ×2 (800-sample BSRAM correlation windows) — NOW CRITICAL PATH
2. Peak detector + TOF calculator
3. Full pipeline integration and synthesis
4. Hardware bring-up: verify DRVDD=3.3V rail, OEB=LOW, DFS=AVSS

---

## 2026-06-10 — Full Pipeline Validation Run + FIR Filter Banks Built

**Validation Run Summary:**
Pipeline stages 1–3 (hw-validation, dsp-signal-validator, systems-integrator, verilog-sim-runner) completed.

**Issues Found & Fixed:**

hw-validation findings (2 blockers, 1 warning):
- FIX-B1: adc_interface.v — AD9226 outputs offset binary by default (DFS=AVSS). Added MSB inversion: sample_out <= {~adc_data[11], adc_data[10:0]}. Without this, 0V input would feed as -2048 into CIC integrators, causing saturation.
- FIX-B2: cic_decimator.v — output right-shift was WIDTH-16=12 bits, incorrect. Corrected to 5 bits per Hogenauer formula: B_max=12+3×log2(8)=21, shift=(B_max-1)-15=5. Old shift caused ~128× amplitude loss (~42dB SNR collapse).
- FIX-W1: adc_interface.v — added sample_otr output port to propagate OTR flag to matched filter clipping detection downstream.

dsp-signal-validator findings (same root causes):
- Confirmed MSB-flip and shift corrections above.
- FIX-W2: cic_decimator.v header comment corrected: had R=160, DVDD=5V, latency=3 — all wrong. Corrected to R=8, DRVDD=3.3V, 7 ENCODE cycles latency.

systems-integrator findings:
- 0 conflicts between validators. Added signed saturation clamp on CIC dout: full-scale peak (2^20>>5=32768) exactly at signed 16-bit max boundary — clamp prevents wrap.
- DFS strap ambiguity noted: CLAUDE.md assumes DFS=AVSS (default offset binary). Physical verification required when AD9226 arrives.

**Design Decisions:**
- CIC integrators WRAP (not saturate) — this is correct Hogenauer CIC behavior. Saturation clamp applies only to output dout.
- 32-tap FIR at fs=421875Hz cannot achieve 30dB rejection between adjacent 34–38kHz and 42–46kHz bands (normalized gap ~0.019, filter resolution ~0.031). Best achievable ~0.4–2.5dB. Matched filter downstream provides the real band discrimination.

**New Modules Built:**
- fir_filter_bank1.v: 32-tap 34–38kHz bandpass FIR, Hamming windowed-sinc, fs=421875Hz, Q1.15 coefficients, 37-bit accumulator, non-blocking assignments.
- fir_filter_bank2.v: 32-tap 42–46kHz bandpass FIR, same design as bank1.
- Testbenches: tb_fir_filter_bank1.v, tb_fir_filter_bank2.v — verify passband response, adjacent-band attenuation (relative), dout_valid timing, no X/Z.

**Simulation Results (ALL PASS):**
- adc_interface: MSB-flip conversions verified (0x800→0x000, 0xFFF→0x7FF, 0x000→0x800), OTR alignment confirmed, no X/Z.
- cic_decimator: DC_EXPECTED=0x1000 (4096) confirmed, R=8 decimation over 38 intervals verified, no X/Z.
- fir_filter_bank1: 34–38kHz passband active (peak 4729), adjacent-band attenuated, dout_valid 1:1 handshaking verified, no X/Z.
- fir_filter_bank2: 42–46kHz passband active (peak 4766), adjacent-band attenuated, dout_valid 1:1 handshaking verified, no X/Z.

**CLAUDE.md Updated:**
- FPGA Pipeline diagram: CIC line changed from "65MSPS → ~400kSPS (factor ~160, BSRAM-based)" to "CIC Decimation: 3.375MHz → ~422kSPS (R=8, N=3, adc_clk=27MHz/8=3.375MHz)".
- Build status: CIC decimation ⏳ → ✅ (written, fixed, simulated). FIR banks ⏳ → ✅ ×2 (both written and simulated).
- AD9226 Hardware Contract: Added DFS strap note — assumes DFS=AVSS (default). Physical verification required on arrival.
- Timing constraints (.cst file): remains ⏳ — not completed in this run. Still top priority for next session.

**Next Priority:**
1. Write .cst timing constraints (MOST URGENT — unlocks synthesis)
2. Matched filter correlators (2 instances, 800-sample BSRAM correlation windows)
3. Peak detector + TOF calculator
4. Integration testing before AD9226 arrival (June 14–21)

2026-06-08: Completed UART TX module on Tang Nano, synthesized successfully.

Disabled UART serial console on Pi — /dev/ttyAMA0 now free for FPGA comms.

Next: .cst timing constraints file, AD9226 Verilog sim, pending orders.

2026-06-09: Fixed adc_interface.v — added adc_clk ENCODE output, 3-cycle pipeline latency alignment. Testbench rewritten for ENCODE-based timing model. Simulation PASS.
2026-06-09: UART TX verified for 8-byte back-to-back packet — inter-byte gaps measured <<1 bit period. Simulation PASS.
2026-06-09: CIC decimation module written — R=8, 3.375MHz input (27MHz/8 adc_clk), 422kSPS output, N=3 stages, 28-bit internal width. Simulation PASS.
Note: CLAUDE.md decimation factor updated from R=160 (65MSPS assumption) to R=8 (actual 3.375MHz adc_clk architecture).

2026-06-09: Hardware validation (hw-validator, Puppeteer-verified against datasheets):
  BLOCKED — 5 hardware blockers found and fixed same session:
  - uart_tx.cst: clk was pin 52 (9K pin) → fixed to pin 4 (20K crystal)
  - uart_tx.cst: rst_n was on pin 4 (collision with clock) → moved to pin 88 (S1 button, PULL_MODE=UP)
  - uart_tx.cst: tx was pin 17 (onboard LED, not header) → moved to pin 69 (verified free GPIO, Sipeed UART example)
  - adc_interface.v: pipeline latency was 3 ENCODE cycles → corrected to 7 (AD9226 datasheet Rev B)
  - adc_interface.v: OTR clamp was 12'h7FF (mid-scale) → removed clamp, now pass-through (ADC outputs 0xFFF/0x000)
  Simulations re-run after fixes: uart_tx PASS, adc_interface PASS, zero X/Z states.
  CLAUDE.md AD9226 Hardware Contract updated: pipeline latency 3→7, DRVDD=3.3V documented.

2026-06-09: Pin assignments confirmed (source: Sipeed TangNano-20K-example/uart/src/top.cst via GitHub API):
  clk = pin 4 (27MHz oscillator), tx = pin 69 (header GPIO), rst_n = pin 88 (button S1)
  Pending physical verification: confirm pin 69 is accessible on your specific board revision before wiring.

