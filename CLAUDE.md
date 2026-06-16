\# ASV Project — CLAUDE.md

\# GPS-Denied Autonomous Acoustic Homing Catamaran USV

\# Owner: Mirthun Mohan — Texas A\&M University Computer Engineering

\# Collaborator: Dad (hull fabrication, waterproofing, soldering)

\# Hard Demo Deadline: August 10, 2026

\# Current Status: Week 4 of 11 — FIR banks verified, matched filters CRITICAL PATH, SNR-gradient architecture (FC-5/FC-6)

\# Last Updated: June 16, 2026



\---



\## PROJECT SUMMARY



A GPS-denied catamaran USV that sequentially homes on two floating

acoustic beacons using FPGA-accelerated matched filter signal processing.

Built as a portfolio project targeting naval defense roles in signals

and embedded systems. Budget: \~$310–380 optimized, $463 all-in.



This is a real hardware project with a fixed deadline. Every code

decision must be practical, buildable, and debuggable by one person

with no lab support. Prefer simple and working over elegant and risky.



\---



\## HARDWARE STACK (FINAL — DO NOT SUGGEST CHANGES)



\### FPGA — Tang Nano 20K (GW2AR-18)

\- Toolchain: Gowin EDA (installed, confirmed working)

\- Clock: 27MHz onboard oscillator

\- Resources: 48 hardware multipliers, 46× 18Kbit BSRAM, 20,736 LUT4s

\- Constraint file format: .cst (Gowin proprietary — NOT XDC or UCF)

\- Target clock period: 37.037ns (27MHz)



\### FPGA Pipeline (fully designed, implementation in progress)

```

AD9226 parallel input (12-bit, 65MSPS)

&#x20; → CIC Decimation: 3.375MHz → \~422kSPS (R=8, N=3, adc_clk=27MHz/8=3.375MHz)

&#x20; → 2× Parallel 32-tap FIR Bandpass Filter Banks

&#x20;     Bank 1: 34–38 kHz (Buoy 1 chirp), \~16 HW multipliers

&#x20;     Bank 2: 42–46 kHz (Buoy 2 chirp), \~16 HW multipliers

&#x20;     Total: 32 of 48 HW multipliers — 33% margin

&#x20;     Coefficients stored in BSRAM, runtime-loadable via UART from Pi

&#x20; → 2× Matched Filter Correlators

&#x20;     Reference chirps in BSRAM (2× 800-sample arrays)

&#x20;     Correlation window: 2ms × 421,875 SPS ≈ 800 samples (FC-3)

&#x20;     Output: corr_peak (magnitude), snr (proximity gradient), peak_lag (diagnostic only, per FC-5)

&#x20; → Peak Detector + SNR Calculator

&#x20;     corr_peak (32-bit) and snr (8-bit) are primary homing signals

&#x20;     peak_lag kept as diagnostic only — NOT converted to range (per FC-5)

&#x20; → Active Target Selector + UART TX

&#x20;     8-byte packet at up to 20Hz:

&#x20;     \[target\_id:1]\[peak\_lag:2]\[corr\_peak:2]\[snr:1]\[checksum:1]\[0xFF:1]

&#x20;     (bytes 2–3 previously labeled range_cm — now peak_lag diagnostic; wire format UNCHANGED)

```



\### FPGA Build Status (as of June 13, 2026)

\- ✅ Gowin EDA installed and confirmed working

\- ✅ Basic combinational logic and clocked always blocks confirmed

\- ✅ UART TX module written and synthesized onto Tang Nano — 8-byte back-to-back packet verified in sim ← DONE Jun 8

\- ✅ Timing constraints (.cst files) — VERIFIED COMPLETE
\-   uart\_tx.cst: written, verified ← VALIDATED Jun 13
\-   adc_interface.cst: VERIFIED (pins D[0..11], otr, adc_clk assigned to LVCMOS33-compatible banks) ← VALIDATED Jun 13

\- ✅ CIC decimation module — written, corrected (R=8, shift=5), and simulated ← VALIDATED Jun 10

\- ✅ FIR filter bank 1 (34–38kHz) — written, 32-tap Hamming windowed-sinc, signed-16 INTEGER scale, and simulated ← VALIDATED Jun 13

\- ✅ FIR filter bank 2 (42–46kHz) — written, 32-tap Hamming windowed-sinc, signed-16 INTEGER scale, and simulated ← VALIDATED Jun 13

\- ⏳ Matched filter correlators — not started (now CRITICAL PATH)

\- ✅ AD9226 parallel interface — corrected (MSB-flip, OTR port, signed declaration) and simulated ← VALIDATED Jun 13

\- ⏳ Full pipeline integration — not started



\### ADC — AD9226 12-bit 65MSPS

\- Interface: 12-bit parallel bus D\[11:0], OTR pin, FPGA-driven CLK

\- Ordered AliExpress \~May 31 — arrived June 8, 2026 ✅

\- Signal path: TCT40-16R → MAX9814 preamp → AD9226 → FPGA

### AD9226 Hardware Contract (from datasheet)
- ENCODE pin: FPGA must drive this as the ADC sampling clock
  The AD9226 samples on the RISING edge of ENCODE
  Max ENCODE frequency: 65MHz
  Recommended for this project: 1–5MHz (well above 40kHz signal, 
  manageable for FPGA routing)
- Data latency: output data D[11:0] is valid 1 pipeline cycle 
  AFTER the ENCODE rising edge that triggered it
  (pipeline latency = 7 ENCODE cycles per AD9226 datasheet Rev B)
- OTR pin: goes HIGH when input signal exceeds full-scale range
  OTR is registered — it corresponds to the same conversion as 
  the current D[11:0] output
- Setup time: D[11:0] must be latched AFTER tDO (data valid delay)
  from ENCODE rising edge — typically 5–10ns at 5MSPS
- VREF: set to 1.0V for ±1V differential input range
- Power supply: AVDD = 5V, DRVDD = 3.3V (separate digital driver rail)
  DRVDD is independently settable — wire DRVDD to 3.3V so D[11:0]/OTR
  are LVCMOS33-compatible with Tang Nano 20K GPIO directly (no level shifting)
- OE pin: must be tied LOW to enable outputs
- DFS strap: CLAUDE.md assumes DFS=AVSS (offset binary output, default).
  Software MSB-flip {~data[11], data[10:0]} is correct for this configuration.
  AD9226 is in hand (arrived Jun 8) — verify DFS pin is unconnected or tied to AVSS,
  not AVDD, before first power-on.

### adc_interface.cst Pin Configuration (verified Jun 13)
- D[0] = pin 73, D[1] = pin 74, D[2] = pin 75, D[3] = pin 85, D[4] = pin 77
- D[5] = pin 27, D[6] = pin 28, D[7] = pin 25, D[8] = pin 26, D[9] = pin 29
- D[10] = pin 30, D[11] = pin 31
- otr = pin 80
- adc_clk = pin 76
- All pins confirmed LVCMOS33-compatible, no bank conflicts, signal integrity verified

### UART Streaming Hardware Contract
- Pi UART reads at 115200 baud on /dev/ttyAMA0
- 8-byte packet format: [target_id][peak_lag_H][peak_lag_L]
  [corr_peak_H][corr_peak_L][snr][checksum][0xFF]
  (bytes 2–3 previously labeled range_cm — now peak_lag diagnostic; wire format unchanged per FC-5)
- Back-to-back bytes: gap between bytes must not exceed 1 bit period
  (8.68us at 115200 baud) or Pi UART may flag framing error
- Idle line: tx must idle HIGH between packets
- Packet rate: up to 20Hz (50ms between packets) — well within 
  115200 baud capacity



\### Mission Computer — Raspberry Pi 4 1GB

\- OS: Ubuntu 24.04.4 LTS

\- ROS: ROS 2 Jazzy ros-base (installed, talker/listener verified ✅)

\- SSH: mirthmoh1379@mirthuns-rp4.local (working ✅)

\- Colcon and rosdep: installed ✅

\- Heatsinks: installed, idle 44.3°C, throttled=0x0 ✅

\- snapd: REMOVED — never reinstall (caused watchdog timeouts)

\- avahi-daemon: enabled and working ✅

\- VS Code Remote SSH: configured and working ✅

\- UART serial console: ✅ DISABLED TODAY — /dev/ttyAMA0 is now free

\- Pi known issues resolved:

&#x20; \* liblz4-1/libzstd1/zlib1g force-downgraded for ROS 2 compatibility

&#x20; \* Debian 13 Trixie was incompatible — Ubuntu 24.04.4 LTS is correct OS

&#x20; \* avahi-daemon accidentally disabled during cleanup — now restored



\### Pi ROS 2 Build Status (as of June 8, 2026)

\- ✅ ROS 2 Jazzy installed and verified

\- ✅ UART /dev/ttyAMA0 freed for FPGA comms

\- ⏳ fpga\_uart\_node — not started

\- ⏳ acoustic\_homing\_node — not started

\- ⏳ mission\_state\_machine node — not started

\- ⏳ dead\_reckoning\_node (robot\_localization EKF) — not started

\- ⏳ collision\_safety\_node — not started

\- ⏳ motor\_driver\_node — not started

\- ⏳ telemetry\_node — not started



\### Peripheral MCU — ESP32 #1 (vehicle)

\- Framework: micro-ROS

\- Peripherals: L298N H-bridge (motor control), MPU-6050 IMU (I2C),

&#x20; JSN-SR04T waterproof ultrasonic (collision avoidance, triggers <25cm)

\- Publishes: /imu/data, /odom

\- Subscribes: /cmd\_vel (Twist)

\- Status: not started



\### ESP32 #2 (buoy controllers)

\- Drives TCT40-16T transducers via MOSFETs

\- Generates LFM chirp waveforms for each buoy

\- Each buoy: 3× TCT40-16T at 120° spacing for 360° coverage

\- Status: not started



\### Arduino Uno R4 WiFi (shore display)

\- Receives mission state over WiFi

\- Displays current state + range on LED matrix

\- Status: not started



\### Acoustic System

\- Transducers owned: hiBCTR TCT40-16R/T pack (10TX + 10RX) ✅

\- Vehicle receiver: 1× TCT40-16R on bow mast 25–30cm above waterline

\- Buoy transmitters: 3× TCT40-16T per buoy (6 TX total)

\- Transmission medium: AIR (above waterline, not underwater)

\- Pre-amp: MAX9814 auto-gain between TCT40-16R and AD9226

\- Chirp 1: 34–38 kHz LFM sweep → Buoy 1

\- Chirp 2: 42–46 kHz LFM sweep → Buoy 2



\### Propulsion

\- 2× brushed DC underwater thrusters 12V — NOT YET ORDERED

\- Driver: L298N dual H-bridge — NOT YET ORDERED

\- Power: Hosim 3S 5000mAh LiPo 11.1V 30C XT60 ×2 ✅ arrived

\- Charger: B6 AC 80W balance charger ✅ arrived

\- Safety: Inline blade fuse 20A ✅ arrived



\### Hull

\- Type: PVC catamaran

\- Pontoons: 2× 4" Schedule 40 PVC, 70cm each, 40cm beam

\- Cross members: 1" PVC pipe with aluminum L-brackets

\- Sealant: JB Weld MarineWeld + marine silicone

\- Electronics bay: IP65 waterproof enclosure — NOT YET ORDERED

\- Mast: 1" PVC rod, 25–30cm above waterline, RX transducer on top

\- Status: Materials NOT yet purchased — Home Depot run pending



\---



\## SOFTWARE ARCHITECTURE



\### ROS 2 Node Graph

```

FPGA (Tang Nano 20K)

&#x20; └─ UART 115200 baud /dev/ttyAMA0 ──► fpga\_uart\_node (Pi, Python)

&#x20;      parses 8-byte packets, publishes:

&#x20;        /acoustic/corr\_snr  (Float32, 20Hz)  ← primary homing signal (FC-6)

&#x20;        /acoustic/peak\_lag  (Float32, 20Hz)  ← diagnostic only, not meters



ESP32 micro-ROS

&#x20; ├─ publishes /imu/data       (Imu, 100Hz)

&#x20; ├─ publishes /wheel/velocity (50Hz, estimated from PWM duty)

&#x20; └─ subscribes /cmd\_vel       (Twist)



JSN-SR04T via ESP32

&#x20; └─ publishes /collision/range\_cm (10Hz)



robot\_localization EKF node

&#x20; fuses /imu/data + /wheel/velocity

&#x20; └─ publishes /odometry/filtered



acoustic\_homing\_node

&#x20; states: SCANNING → ACQUIRING → HOMING → ARRIVED → PAUSING

&#x20; subscribes: /acoustic/corr\_snr, /odometry/filtered

&#x20; publishes: /cmd\_vel (Twist)



mission\_state\_machine node

&#x20; INIT → SCAN\_1 → HOMING\_1 → ARRIVED\_1 → SCAN\_2 → HOMING\_2 → ARRIVED\_2



collision\_safety\_node

&#x20; /collision/range\_cm < 25cm → hard ESTOP override on /cmd\_vel



motor\_driver\_node

&#x20; subscribes /cmd\_vel → drives L298N PWM



telemetry\_node

&#x20; publishes mission state + range over WiFi to shore display

```



\### State Machine Logic

\- SCAN: rotate 360°, monitor FIR bank correlation SNR

&#x20; Lock threshold exceeded → transition to ACQUIRING then HOMING

\- HOMING: gradient ascent on /acoustic/corr\_snr → differential thrust; SNR rising = closing (FC-6)

&#x20; EKF dead reckoning between acoustic pings

\- ARRIVED: corr\_snr exceeds SNR\_ARRIVED\_THRESHOLD for 3 consecutive readings (threshold = CQ-1, empirical)

\- nav2 is EXPLICITLY WRONG — do not suggest it ever



\### QoS Policy

\- Sensor streams (/imu, /range, /collision): BEST\_EFFORT, small depth

\- Commands (/cmd\_vel, state transitions): RELIABLE, larger depth



\---



\## DESIGN DECISIONS (LOCKED — DO NOT REVISIT)



| Decision | Choice | Reason |

|---|---|---|

| ADC | AD9226 65MSPS | ADS1256 30kSPS violates Nyquist for 40kHz |

| Navigation | Custom state machine | nav2 needs map; range-only doesn't have one |

| Telemetry | WiFi only | Pool distances don't need LoRa range |

| Motors | Brushed DC + L298N | Simpler than brushless, sufficient for pool |

| Transmission | Air acoustic above waterline | Avoids hull penetration complexity |

| OS | Ubuntu 24.04.4 LTS | ROS 2 Jazzy compatibility confirmed |

| FPGA decimation | CIC filter 65MSPS→400kSPS | Fits in BSRAM, preserves 40kHz band |

| Bearing method | Range-only scalar (V1) | TDOA dual-receiver is V2 enhancement |



\---



\## PARTS STATUS



\### ✅ Arrived / Owned

\- Raspberry Pi 4 1GB (fully configured — see Pi status above)

\- Tang Nano 20K FPGA (Gowin EDA working, UART module done)

\- AD9226 12-bit 65MSPS ADC (arrived June 8, 2026)

\- ESP32 ×2 (owned)

\- Arduino Uno R4 WiFi (owned)

\- hiBCTR TCT40-16R/T transducer pack (10TX + 10RX)

\- Hosim 3S 5000mAh LiPo ×2

\- B6 AC 80W balance charger + XT60 cable

\- HiLetgo GY-521 MPU-6050

\- Cecicebb XT60 connectors + 14AWG silicone wire

\- Inline blade fuse holder + 20A fuses

\- Pi heatsink kit (installed)

\- MOSFETs, buck converters, breadboards, jumper wires,

&#x20; resistors, capacitors, soldering iron, multimeter, drill



\### 🚚 In Transit



\### 🔴 Not Yet Ordered — Action Required

\- Brushed DC thrusters ×2 (545 12V underwater) — ORDER NOW

\- L298N dual H-bridge module — ORDER NOW

\- MAX9814 pre-amp module — ORDER NOW

\- JSN-SR04T waterproof ultrasonic sensor — ORDER NOW

\- IP65 waterproof enclosure + M12 cable glands — ORDER NOW

\- PVC pipe, end caps, L-brackets, epoxy, silicone — HOME DEPOT RUN



\---



\## CURRENT BUILD STATUS (Week 4 of 11, June 16 2026)



\### ✅ COMPLETED

\- Pi: Ubuntu 24.04.4 + ROS 2 Jazzy + SSH + heatsinks + all fixes

\- Pi: UART serial console disabled — /dev/ttyAMA0 free ← DONE Jun 8

\- FPGA: Gowin EDA installed, basic logic confirmed

\- FPGA: UART TX module written and synthesized ← DONE Jun 8

\- FPGA: AD9226 interface (adc_interface.v) — MSB-flip corrected, OTR port added, signed declaration added, simulated ← VALIDATED Jun 13

\- FPGA: CIC decimation (cic_decimator.v) — shift=5 corrected, saturation clamp added, simulated ← VALIDATED Jun 13

\- FPGA: FIR filter banks ×2 (34–38kHz, 42–46kHz) — 32-tap Hamming windowed-sinc, signed-16 INTEGER scale, simulated ← VALIDATED Jun 13

\- FPGA: uart_tx.cst timing constraints — written and verified ← DONE Jun 13

\- FPGA: adc_interface.cst timing constraints — pin configuration verified (all 14 pins LVCMOS33-compatible) ← DONE Jun 13

\- Parts: AD9226 arrived Jun 8, most Week 1 Amazon items arrived

\- Architecture: Full project spec and pipeline design locked

\- Pipeline validation: hw-validation, dsp-signal-validator, systems-integrator, verilog-sim-runner — ALL PASS Jun 13



\### ⏳ IMMEDIATE NEXT TASKS (Week 4 priority order, updated Jun 16)

1\. Matched filter correlators ×2 — NOW CRITICAL PATH

&#x20;  (800-sample BSRAM cross-correlation, 2109-sample 5ms LFM reference per channel, signed-16 integer per FC-1, OTR per FC-2)

2\. Peak detector — outputs corr\_peak (32-bit) + snr (8-bit) + peak\_lag (diagnostic); NO range\_cm, NO ToF conversion (FC-5)

&#x20;  (snr is the primary homing gradient; peak\_lag kept for V2 TDOA upgrade hook only)

3\. Full pipeline integration: chain AD9226 → CIC → FIR banks → matched filters → peak detector → UART

&#x20;  (verify end-to-end latency; delete fir\_test\_top.v per FC-4)

4\. Synthesis verification: run full design through Gowin EDA, verify positive timing slack at 27MHz

&#x20;  (both .cst files now in place, ready for layout)

5\. Place pending Amazon orders (thrusters, L298N, enclosure, MAX9814, JSN-SR04T)

6\. Coordinate Home Depot run with Dad (PVC, epoxy, brackets, silicone)



\### 🔴 CRITICAL PATH WARNING

FPGA matched filter is the hardest and most time-sensitive component.

Weeks 3–6 must be FPGA-focused. Two weeks of carryover already exist.

The .cst timing constraints file must be written immediately —

it unlocks all downstream FPGA synthesis work.



\---



\## WEEKLY TIMELINE

# Project Start Date: May 25, 2026 (Monday — Week 1 Day 1)
# Week Structure: Monday to Sunday strictly
# Week Mapping (use this exactly, do not recalculate):
#   W1:  May 25–May 31
#   W2:  Jun 01–Jun 07
#   W3:  Jun 08–Jun 14
#   W4:  Jun 15–Jun 21  ← CURRENT WEEK
#   W5:  Jun 22–Jun 28
#   W6:  Jun 29–Jul 05
#   W7:  Jul 06–Jul 12
#   W8:  Jul 13–Jul 19
#   W9:  Jul 20–Jul 26
#   W10: Jul 27–Aug 02
#   W11: Aug 03–Aug 09
# Today June 16 2026 = Week 4 Day 2
# Deadline August 10 2026 falls the day after W11 ends — hard cutoff



| Week | Dates | Phase | Status |

|---|---|---|---|

| 1  | May 25–May 31 | Foundation + ordering        | 🔴 Partial |
| 2  | Jun 01–Jun 07 | AD9226 interface + hull start | 🔴 Partial |
| 3  | Jun 08–Jun 14 | Timing constraints + FIR banks verified | ✅ Done |
| 4  | Jun 15–Jun 21 | Matched filters + peak detector | 🟡 Current |
| 5  | Jun 22–Jun 28 | Pipeline integration + synthesis | 🎯 Milestone |
| 6  | Jun 29–Jul 05 | ESP32 micro-ROS + buoy firmware | ⚪ |
| 7  | Jul 06–Jul 12 | ROS 2 nodes + PID homing     | ⚪ |
| 8  | Jul 13–Jul 19 | Mission state machine + display | ⚪ |
| 9  | Jul 20–Jul 26 | Pool test #1                 | 🎯 Milestone |
| 10 | Jul 27–Aug 02 | Pool test #2 + tuning        | ⚪ |
| 11 | Aug 03–Aug 09 | Polish + demo video          | 🏁 Deadline |



\---



\## CODING STANDARDS



\### Verilog (FPGA)

\- Non-blocking assignments (<=) in ALL clocked always blocks

\- Every module must have a companion testbench in /fpga/sim/

\- Simulate before declaring done:

&#x20; iverilog -o fpga/sim/out fpga/sim/tb\_X.v fpga/src/X.v \&\& vvp fpga/sim/out

\- Check for X/Z states — uninitialized signals

\- Constraint files: .cst format ONLY (Gowin) — never .xdc or .ucf

\- Target clock: 27MHz, period 37.037ns

\- Fixed-point: signed-16 integer scale for filter coefficients (NOT Q1.15 — see TRAJECTORY.md FC-1)

\- Pipeline ALL multiply-accumulate chains — never combinational MAC

\- Use BSRAM for large coefficient arrays, not distributed LUTs



\### Python / ROS 2

\- ROS 2 Jazzy node structure with explicit QoS profiles

\- BEST\_EFFORT for sensor streams, RELIABLE for commands

\- Always set ROS\_DOMAIN\_ID consistently across Pi and laptop

\- rosbag2 record -a during all testing sessions

\- UART node reads /dev/ttyAMA0 at 115200 baud



\### HTML / JS (ASV Hub app)

\- Single HTML file, all CSS and JS inline

\- No ES modules, no import maps — iPhone Safari compatible

\- localStorage only, no backend, no API calls

\- PWA manifest + service worker for offline use

\- Target: hub/asv\_hub\_v3.html built from hub/asv\_hub\_v2.html



\---



\## FILE STRUCTURE



asv-project/

├── CLAUDE.md

├── fpga/

│   ├── src/               ← Verilog modules

│   │   └── uart\_tx.v      ← DONE — UART TX module

│   ├── sim/               ← Icarus testbenches

│   └── constraints/       ← .cst files (Gowin format)

├── ros2\_ws/

│   └── src/               ← ROS 2 packages (not started)

├── esp32/                 ← ESP32 micro-ROS firmware (not started)

├── hub/

│   ├── asv\_hub\_v2.html    ← current working version

│   └── asv\_hub\_v3.html    ← build target

└── docs/

&#x20;   ├── progress.md        ← daily progress notes for briefing agent

&#x20;   └── week\_N\_audit.md    ← weekly audit reports



\---



\## AGENT INSTRUCTIONS



\### daily-briefing agent

Read CLAUDE.md and docs/progress.md. Generate structured daily briefing:

current week/day, GREEN/YELLOW/RED status, today's tasks by priority

with time estimates (CRITICAL / TODAY / IF TIME), one learning concept

for today, parts arriving this week, days to August 10 deadline.

Save to docs/daily\_briefing.txt.



\### hub-builder agent (model: claude-sonnet-4-6)

Read CLAUDE.md. Read hub/asv\_hub\_v2.html as base.

Build hub/asv\_hub\_v3.html — single HTML file, all CSS/JS inline,

localStorage only, no API calls, iPhone Safari compatible, PWA-ready.

Spin up local server port 8080, verify all tabs, fix issues before done.



\### fpga-sim agent (model: claude-opus-4-7)

Read CLAUDE.md. Write modules to fpga/src/, testbenches to fpga/sim/,

constraints to fpga/constraints/.

ALWAYS simulate with iverilog before declaring done.

Check for X/Z states. Gowin .cst format only. Non-blocking assignments.

Target 27MHz. Signed-16 integer scale (NOT Q1.15 — see TRAJECTORY.md FC-1). Pipeline all MAC chains.

Next tasks: write uart\_tx.cst and adc\_interface.cst, synthesize each in Gowin EDA,

verify positive timing slack at 27MHz in the timing report. No counter dummy module needed.



\### weekly-audit agent (model: claude-sonnet-4-6)

Read CLAUDE.md and all files in docs/. Report GREEN/YELLOW/RED on

Technical, Cost ($100 budget), Career alignment.

What is done vs planned, top 3 risks, next 48hr recommended actions.

Save to docs/week\_N\_audit.md with correct week number.



\---



\## LOCKED DECISIONS — NEVER REVISIT OR SUGGEST ALTERNATIVES

\- Never suggest nav2 (needs map; range-only homing doesn't have one)

\- Never suggest ADS1256 (30kSPS violates Nyquist for 40kHz signals)

\- Never suggest LoRa (WiFi sufficient for pool-scale distances)

\- Never suggest brushless motors (brushed DC + L298N is locked)

\- Never suggest underwater acoustic transmission (air path is locked)

\- Always check parts status before suggesting wiring or assembly tasks

\- If a part is not yet ordered, flag it rather than assuming available

