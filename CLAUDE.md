\# ASV Project — CLAUDE.md

\# GPS-Denied Autonomous Acoustic Homing Catamaran USV

\# Owner: Mirthun Mohan — Texas A\&M University Computer Engineering

\# Collaborator: Dad (hull fabrication, waterproofing, soldering)

\# Hard Demo Deadline: August 10, 2026

\# Current Status: Week 6 Day 3 — 6 ROS 2 nodes built, uart_rx.v RTL complete, FPGA 9/10 modules simulating verified; 40 days to demo; hull fabrication + Layer A acoustic bench check next

\# Last Updated: July 1, 2026



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

&#x20;     Bank 1: 34–38 kHz (Buoy 1 chirp), \~1 HW multiplier (sequential MAC engine)

&#x20;     Bank 2: 42–46 kHz (Buoy 2 chirp), \~1 HW multiplier (sequential MAC engine)

&#x20;     Matched filter ×2: \~2 HW multipliers (block correlator, time-shared MAC, 1 per filter)

&#x20;     Total: 4 of 48 HW multipliers — RTL simulation confirmed (Jun 29), synthesis confirmed (Jun 30)
&#x20;     (Gowin synthesis report: DSP/ALU54D blocks 2/24 = 4 of 48 MULT18X18 multipliers, 9% utilization.
&#x20;     Each module has exactly one `prod <= mul_a*mul_b` register; 64 sys clocks/sample ≫
&#x20;      32 MAC cycles for FIR; 134,976 sys clocks/window ≫ 2109 MAC cycles for matched filter.)

&#x20;     Coefficients stored in BSRAM, runtime-loadable via UART from Pi

### BSRAM Resource Allocation (validated Jun 29 — depth-bound, not capacity-bound)
- FIR filter banks: 2 BSRAM blocks (1 per bank, 32-tap × 16-bit = 512 bits << 18K)
- Matched filter ×2: 12 blocks total (4-array architecture):
  - Architecture: reference ROM + window buffer per channel × 2 channels = 4 arrays
  - Depth constraint: 1K×18 mode = 1024 locations/block; 2×1024=2048 < 2109
    → 3 blocks per array (3×1024=3072 ≥ 2109); capacity alone would say 2
  - Reference chirp ROMs: 3 blocks/channel × 2 channels = 6 blocks
  - Window sample buffers: 3 blocks/channel × 2 channels = 6 blocks
- Total BSRAM used: ~14 of 46 blocks (~30%) — validated by systems-integrator Jun 29

&#x20; → 2× Matched Filter Correlators

&#x20;     BSRAM layout (4 arrays total): reference ROM + window buffer per channel
&#x20;     Reference chirps: 2× 2109-sample arrays (3 BSRAM blocks each, depth-bound)
&#x20;     Window buffers:  2× 2109-sample arrays (3 BSRAM blocks each, depth-bound)

&#x20;     Correlation window: 5ms × 421,875 SPS = 2109 samples (FC-3, corrected from stale 800/2ms)

&#x20;     Output: corr_peak (magnitude), snr (proximity gradient), peak_lag (diagnostic only, per FC-5)

&#x20; → Peak Detector + SNR Calculator

&#x20;     corr_peak (32-bit) and snr (8-bit) are primary homing signals

&#x20;     peak_lag kept as diagnostic only — NOT converted to range (per FC-5)

&#x20; → Active Target Selector + UART TX

&#x20;     8-byte packet at up to 20Hz:

&#x20;     \[target\_id:1]\[peak\_lag:2]\[corr\_peak:2]\[snr:1]\[checksum:1]\[0xFF:1]

&#x20;     (bytes 2–3 previously labeled range_cm — now peak_lag diagnostic; wire format UNCHANGED)

```



\### FPGA Build Status (as of June 30, 2026)

\- ✅ Gowin EDA installed and confirmed working

\- ✅ Basic combinational logic and clocked always blocks confirmed

\- ✅ UART TX module written and synthesized onto Tang Nano — 8-byte back-to-back packet verified in sim ← DONE Jun 8

\- ✅ Timing constraints (.cst files) — VERIFIED COMPLETE
\-   uart\_tx.cst: written, verified ← VALIDATED Jun 13
\-   adc_interface.cst: VERIFIED (pins D[0..11], otr, adc_clk assigned to LVCMOS33-compatible banks) ← VALIDATED Jun 13

\- ✅ CIC decimation module — written, corrected (R=8, shift=5), and simulated ← VALIDATED Jun 10

\- ✅ FIR filter bank 1 (38.5–41.5kHz per FC-7) — 32-tap Hamming windowed-sinc, passband ripple <1dB, stopband confirmed, VALIDATED Jun 18

\- ✅ FIR filter bank 2 (38.5–41.5kHz per FC-7) — identical coefficients to bank1 (code-division beacon ID via sweep direction, not frequency bands), VALIDATED Jun 18

\- ✅ Matched filter correlators ×2 — block correlator, 2109-tap, 48-bit acc, OTR window-OR, 200Hz output, CORR_SHIFT=16, up-sweep/down-sweep channels; RTL unchanged per FC-7 (reference chirp data loaded at runtime) ← VALIDATED Jun 16

\- ✅ AD9226 parallel interface — corrected (MSB-flip, OTR port, signed declaration) and simulated ← VALIDATED Jun 13

\- ✅ Peak detector + packet framer (peak_detector.v, packet_framer.v) — dual-channel relative gating (FC-7), SNR proxy, 8-byte FSM; 12/12 sim checks passed ← VALIDATED Jun 17

\- ✅ Full pipeline integration (top_level.v) — 9-module end-to-end chain, packet format corrected (>>6 saturating corr_peak), simulation ALL PASS ← VALIDATED Jun 29

\- ✅ Gowin EDA P&R (place & route) synthesis — top_level.v successfully synthesized with POSITIVE timing margin (setup +28.619ns, hold +0.322ns at 27MHz/37.037ns period); resource utilization: LUT 827/20,736 (4%), Registers 457/15,750 (3%), DSP 2/24 (9%), I/O 17/66 (26%); 0 errors, 0 warnings ← DONE Jun 30

\- ✅ UART RX module (uart_rx.v) — 4-byte frame protocol [addr_hi][addr_lo][data_hi][data_lo], 2-FF synchronizer for async rx, CLKS_PER_BIT=234 matching uart_tx.v, standard glitch-rejection/framing-error patterns, address-map convention for config/BSRAM load in header comment; RTL + testbench, sim verified; pin assignment (pin 87 candidate) flagged unverified — requires hw-validation physical verification before wiring ← DONE Jul 1



\### ADC — AD9226 12-bit 65MSPS

\- Interface: 12-bit parallel bus D\[11:0], OTR pin, FPGA-driven CLK

\- Ordered AliExpress \~May 31 — arrived June 8, 2026 ✅

\- Signal path: TCT40-16R → fixed-gain wideband preamp (×100/40dB, see Preamp Hardware Contract) → AD9226 → FPGA

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

### Preamp Hardware Contract (MANDATORY — DO NOT USE AGC)
- Replacement preamp MUST be fixed-gain (resistor-set), NOT auto-gain-control (AGC)
- REASON: AGC corrupts the FC-6 SNR-gradient homing assumption. FC-6 depends on
  corr_peak increasing monotonically as the vehicle approaches a buoy. An AGC preamp
  automatically compensates for received signal level, flattening the gradient and
  making homing impossible.
- MAX9814 (original spec) is DISQUALIFIED: it is an audio AGC preamp (20 Hz–20 kHz)
  with two separate disqualifying flaws: (1) bandwidth ends at 20 kHz, cannot pass
  40 kHz signals, and (2) its AGC would corrupt the FC-6 gradient even if bandwidth
  were adequate.
- Approved replacement: wideband fixed-gain op-amp (e.g. MCP6022, TLV2462) in a
  non-inverting gain stage with bandpass centered on 40 kHz, OR a dedicated ultrasonic
  receiver amplifier board with fixed gain setting. ~$2–8, unbudgeted minor delta.
- Output must be AC-coupled and biased to the AD9226 ±1V (VREF=1.0V) input range.
- Gain specification (two-stage non-inverting):
  Rf=9.1kΩ (or standard 10kΩ), Rg=1kΩ per stage → ×10/stage = ×100 total (~40 dB)
  WARNING: ×196 total gain clips ADC at 5.1mV input signal — this occurs within 1m homing
  range where received acoustic power peaks, corrupting the SNR gradient right before ARRIVED.
  Use ×100 (~40 dB): ADC clips at ~10mV, providing adequate headroom through the final approach.

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
  (bytes 2–3 = peak_lag diagnostic; bytes 3–4 = (corr_peak>>6) saturated to 16-bit unsigned, preserving monotonic FC-6 homing gradient; wire format unchanged per FC-5)
- Bytes 3–4 value correction (Jun 29): corr_peak from matched filter (32-bit) is right-shifted by 6 bits and saturated to 16-bit unsigned. This preserves the monotonic increase in correlation peak as the vehicle approaches a buoy (FC-6 SNR-gradient homing assumption). Without saturation at close range (<1m), the 16-bit slice would wrap and invert the gradient, corrupting the homing logic.
- Back-to-back bytes: gap between bytes must not exceed 1 bit period
  (8.68us at 115200 baud) or Pi UART may flag framing error
- Idle line: tx must idle HIGH between packets
- Packet rate: up to 20Hz (50ms between packets) — well within 
  115200 baud capacity

### Hardware Build Notes — PWM Noise Isolation (MANDATORY)
- L298N motor switching generates high-frequency transients on the motor power rail
- Motor power rail decoupling: 100nF ceramic + 100µF electrolytic capacitor placed close to L298N motor supply pins
- Star ground topology REQUIRED: analog ground (preamp, ADC) and motor ground (L298N, motors)
  kept on separate copper paths, joined at ONE point only at the LiPo negative terminal.
  Mixing analog/motor grounds at any intermediate node couples switching transients into preamp/ADC.
- MCP6022/TLV2462 VCC: ferrite bead (e.g. BLM18PG221SN1) in series on preamp VCC pin
  to block motor switching noise from entering op-amp supply rail and modulating gain stage



\### Mission Computer — Raspberry Pi 4 1GB

\- OS: Ubuntu 24.04.4 LTS

\- ROS: ROS 2 Jazzy ros-base (installed, talker/listener verified ✅)

\- SSH: &lt;pi-user&gt;@&lt;pi-hostname&gt;.local (working ✅)

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



\### Pi ROS 2 Build Status (as of July 1, 2026)

\- ✅ ROS 2 Jazzy installed and verified

\- ✅ UART /dev/ttyAMA0 freed for FPGA comms

\- ⏳ fpga\_uart\_node — not started (will parse 8-byte FPGA packets, publish /acoustic/corr_snr and /acoustic/peak_lag)

\- ✅ motor\_driver\_node — built Jul 1, implements 80% PWM duty cap (defense-in-depth), 500ms watchdog, publishes /motor/status

\- ✅ collision\_safety\_node — built Jul 1, 30cm ESTOP gate with 1s sensor timeout fail-safe

\- ✅ dead\_reckoning\_node — built Jul 1, custom predict-only EKF (NOT robot_localization wrapper), unicycle model, fuses IMU yaw + wheel speed, publishes /odometry/filtered at 50Hz. Documented as cuttable for MVP.

\- ✅ acoustic\_homing\_node — built Jul 1, full FC-6/FC-7/FC-8 state machine (INIT→SCAN_1→ACQUIRING_1→HOMING_1→ARRIVED_1→EGRESS_1→SCAN_2→ACQUIRING_2→HOMING_2→ARRIVED_2), SNR-gradient homing (not range PID per FC-6), egress dead-reckoning via /odometry/filtered

\- ✅ mission\_state\_machine node — built Jul 1, logs state transitions with elapsed time, publishes /mission/log and /mission/complete

\- ✅ telemetry\_node — built Jul 1, UDP JSON to shore display at 2Hz, non-fatal on WiFi failure

**Node integration status:** 6 of 7 ROS 2 nodes built. wiring architecture corrected to defense-in-depth gating: acoustic_homing → /cmd_vel_raw → collision_safety → /cmd_vel_safe → motor_driver → /cmd_vel (SINGLE publisher to ESP32). Ready for dry-land E2E rehearsal Week 7 after fpga_uart_node is written.



\### Peripheral MCU — ESP32 #1 (vehicle)

\- Framework: micro-ROS

\- Peripherals: L298N H-bridge (motor control), MPU-6050 IMU (I2C),

&#x20; JSN-SR04T waterproof ultrasonic (collision avoidance, ESTOP at <30cm — raised from 25cm; JSN-SR04T blind zone is 25cm, 25cm threshold risks missing obstacles in sensor dead zone)

\- Publishes: /imu/data, /odom

\- Subscribes: /cmd\_vel (Twist)

\- PWM ceiling: 80% max duty cycle enforced in firmware (L298N ~2V drop → 9V effective at 80% on 11.1V rail; full duty risks over-voltage on thrusters)

\- L298N ENA/ENB: MUST use ESP32 LEDC hardware PWM channels (not GPIO toggle) to maintain clean ≤80% duty cap. Suggested: ENA → GPIO25 (LEDC ch0), ENB → GPIO26 (LEDC ch1) — verify against MPU-6050 I2C pins (GPIO21/22) and UART pins before wiring.

\- Stall-current protection (MANDATORY, Week 6 firmware): if estimated motor current exceeds 1.5A per channel (via shunt+ADC or estimated from PWM duty × V_bus), immediately cut PWM to zero for 500ms then resume at 50% duty. LICHIFIT RF-370 stall = 5–8.6A → destroys L298N at sustained stall. Do NOT rely solely on the duty cap. See DL-4.

\- Status: Firmware exists (built Jun 29 — esp32/vehicle_firmware/vehicle_firmware.ino), unflashed and untested. Hardware bring-up tasks remain (LEDC PWM routing verification, stall-current shunt validation). Ready for bench testing Week 6 Jul 3-5 per plan.



\### ESP32 #2 (buoy controllers)

\- Drives TCT40-16T transducers via MOSFETs

\- Generates LFM chirp waveforms for each buoy

\- Each buoy: 3× TCT40-16T at 120° spacing for 360° coverage

\- Status: Firmware exists (built Jun 29 — esp32/buoy_firmware/buoy_firmware.ino with chirp_generator.h), unflashed and untested. Bench task: verify LFM generation at 38.5–41.5 kHz (up-sweep Buoy 1, down-sweep Buoy 2) via oscilloscope against 421,875 Hz sampling spec. Ready for Week 6 Jul 4-5 per plan.



\### Arduino Uno R4 WiFi (shore display)

\- Receives mission state over WiFi

\- Displays current state + range on LED matrix

\- Status: not started



\### Acoustic System

\- Transducers owned: hiBCTR TCT40-16R/T pack (10TX + 10RX) ✅

\- Vehicle receiver: 1× TCT40-16R on bow mast 25–30cm above waterline

\- Buoy transmitters: 3× TCT40-16T per buoy (6 TX total)

\- Transmission medium: AIR (above waterline, not underwater)

\- Pre-amp: ~~MAX9814 auto-gain~~ **DISQUALIFIED** (20 Hz–20 kHz audio band, AGC corrupts SNR gradient)
  **REPLACEMENT REQUIRED:** fixed-gain wideband op-amp (MCP6022/TLV2462) or ultrasonic receiver board; see Preamp Hardware Contract above

\- Chirp 1: ~~34–38 kHz LFM sweep~~ **38.5–41.5 kHz UP-sweep** → Buoy 1 (FC-7 confirmed)

\- Chirp 2: ~~42–46 kHz LFM sweep~~ **38.5–41.5 kHz DOWN-sweep** → Buoy 2 (FC-7 confirmed)



\### Propulsion

\- 2× LICHIFIT RC Jet Boat Underwater Motor (RF-370 class, ASIN B07WY4MDYZ) — NOT YET ORDERED
&#x20; (replaced 545-class: 545 ~3.6A exceeds L298N 2A/3A rating. Drive at ~9V via PWM duty cap. Buy 2 kits — spare-pair hedge. See DL-2.)
  WARNING (Jun 25 component audit): LICHIFIT 16800-RPM variant stall current = 5–8.6A at ~9V — EXCEEDS L298N 3A peak on prop stall.
  Running current ~0.5–0.8A/motor is fine. MITIGATION REQUIRED: firmware stall-current trip in ESP32 motor_driver (cut PWM if current >2A for >100ms via shunt+ADC). Bench-measure actual stall current at 9V before hull assembly. Do NOT rely solely on the PWM duty cap.

\- Driver: L298N dual H-bridge ✅ delivered Jun 2026

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



ESP32 #1 micro-ROS (vehicle — firmware built Jun 29, unflashed/untested)

&#x20; ├─ publishes /imu/data                   (Imu, 100Hz)

&#x20; ├─ publishes /wheel/velocity             (TwistStamped, 50Hz; linear.x=forward speed, angular.z=raw lr-diff; NOT pre-divided by wheel_base)

&#x20; ├─ subscribes /cmd\_vel                  (Twist) — direct subscription, implements OWN 30cm ESTOP + 500ms watchdog independent of Pi ROS

&#x20; └─ JSN-SR04T collision sensor           (via onboard ESTOP gate, not Pi-mediated)



Pi ROS 2 Node Chain (defense-in-depth gating):

acoustic\_homing\_node
  states: INIT → SCAN\_1 → ACQUIRING\_1 → HOMING\_1 → ARRIVED\_1 → EGRESS\_1 → SCAN\_2 → ACQUIRING\_2 → HOMING\_2 → ARRIVED\_2
  subscribes: /acoustic/corr\_snr, /odometry/filtered
  publishes: /cmd\_vel\_raw (Twist)  ← SNR-gradient homing, NOT range PID per FC-6

collision\_safety\_node
  subscribes: /cmd\_vel\_raw, /collision/range\_cm (from ESP32)
  1s sensor-timeout fail-safe; 30cm threshold ESTOP
  publishes: /cmd\_vel\_safe (Twist)

motor\_driver\_node
  subscribes: /cmd\_vel\_safe
  drives L298N PWM via LEDC GPIO25/26 (≤80% duty cap, defense-in-depth)
  500ms watchdog; diff-thrust diagnostics
  publishes: /motor/status
  publishes: /cmd\_vel (Twist) ← SINGLE final publisher to ESP32

dead\_reckoning\_node (custom EKF, NOT robot_localization wrapper)
  subscribes: /imu/data, /wheel/velocity (TwistStamped)
  fuses IMU yaw rate + wheel speed (divides angular.z by wheel_base internally)
  3×3 covariance propagation (unicycle model)
  publishes: /odometry/filtered (50Hz)
  [Documented as cuttable for MVP — if timing is tight, remove this and feed acoustic_homing_node a constant-velocity dead-reckoning fallback instead of full EKF]

mission\_state\_machine node
  logs state transitions with elapsed time
  publishes: /mission/log, /mission/complete

telemetry\_node
  subscribes: mission state + /acoustic/corr\_snr
  publishes UDP JSON to shore display at 2Hz
  non-fatal on WiFi failure

```

**Architecture Correction (Jul 1):** The original flat "/cmd_vel" model was ambiguous. This revised chain enforces defense-in-depth: the Pi applies two independent gates (collision_safety, motor_driver) before the SINGLE /cmd_vel topic reaches the ESP32, which itself has a third independent onboard watchdog/ESTOP. If any Pi-side gate fails, the ESP32 watchdog still stops the motors after 500ms. If the ESP32 watchdog fails, the Pi-side gates catch it. Three independent safety layers.



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

| Motor PWM ceiling | ≤80% duty cycle hard cap in firmware | L298N ~2V drop; 80% on 11.1V = ~9V effective; protects thrusters |

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

\- ~~MAX9814 pre-amp module (delivered Jun 2026)~~ **DISQUALIFIED** — audio AGC band (20 Hz–20 kHz), cannot pass 40 kHz; AGC corrupts SNR-gradient homing (FC-6)

\- JSN-SR04T waterproof ultrasonic sensor (delivered Jun 2026)

\- L298N dual H-bridge module (delivered Jun 2026)



\### 🚚 In Transit (ordered Jun 26, 2026)

\- LICHIFIT RF-370 underwater thrusters ×2 kits (CW+CCW pair per kit, ASIN B07WY4MDYZ, ~$48) — ORDERED Jun 26
&#x20; \* GATE before hull bonding: bench-verify stall current at 9V (expected 5–8.6A — destroys L298N without firmware stall trip); verify ≥150g/motor thrust; implement ESP32 stall-current trip (>2A → cut PWM) BEFORE any thruster is epoxied in
\- Otdorpatio IP67 enclosure B0DX781Z3W (160×160×90mm external, ~150×150×80mm internal, 4×M16 glands included) — ORDERED Jun 26
&#x20; \* Confirmed from Amazon listing: 160×160×90mm. Fits Pi4+Tang Nano+preamp+wiring (~145×115mm occupied). Need 3–4 additional M16/M12 glands for 7 penetrations.
\- IRLZ44N MOSFET 5-pack (Infineon IRLZ44NPBF, TO-220) — ORDERED Jun 26 — Vgs(th)=1–2V; fully enhanced at 3.3V ESP32 ✓



\### 🔴 Not Yet Ordered — Action Required

\- **MCP6022-I/P ×4** — ORDER NOW (Prime delivery Jun 29–30)
&#x20; \* DEFINITIVE CHOICE per DL-5 (Jun 28): MCP6022 (GBW=10MHz, DS20001685F) over MCP6002 (GBW=1MHz)
&#x20; \* Two-stage cascade: Rf=9.1kΩ / Rg=1kΩ per stage → ×102 total (~40dB); virtual ground 100kΩ+100kΩ to 2.5V; AC couple 100nF to AD9226; rebias 10kΩ from VREF (1.0V)
&#x20; \* MCP6002 is acceptable fallback ONLY if MCP6022 is out of stock; do NOT order MCP6002 proactively
&#x20; \* NE5532P (owned): permanently disqualified — needs ±5V split supply, not rail-to-rail on 5V single

\- **Additional M16/M12 cable glands** (4-pack, ~$5–8) — ORDER WITH MCP6022 — enclosure ships with only 4; need 7 penetrations total

\- **Pololu D24V50F5 5V/5A buck converter** (~$12) — ORDER IF owned buck < 4A rated or vcgencmd shows throttling
&#x20; \* Check owned converter chip marking Week 6 Day 1; run vcgencmd get_throttled under full ROS 2 load; if non-zero → ORDER IMMEDIATELY

\- PVC pipe 4" Sch 40 (~1.5m), 1" PVC (~1m), end caps ×4, L-brackets ×10, JB Weld MarineWeld, marine silicone — HOME DEPOT RUN by Jun 30 (Week 6 Day 2)



\---



\## CURRENT BUILD STATUS (Week 6 Day 2, Jun 30, 2026 — Synthesis MET Timing)



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

\- Pipeline validation: hw-validation, dsp-signal-validator, systems-integrator, verilog-sim-runner — ALL PASS Jun 29
\- FPGA synthesis: top_level.v placed & routed successfully, timing MET (setup +28.6ns, hold +0.3ns), resource usage within margin ← DONE Jun 30



\### ⏳ WEEK 6 PRIORITIES (Jun 29–Jul 5)

1\. ✅ **Jun 29 — top_level.v**: chain all 9 verified modules end-to-end; simulate for X/Z states ← VALIDATED Jun 29
&#x20;  ACTION: ORDER MCP6022-I/P ×4 on Amazon Prime TODAY (gates Layer A bench check Jul 2)
&#x20;  ACTION: Check owned buck converter chip marking; order Pololu D24V50F5 if < 4A rated

2\. ✅ **Jun 30 — Gowin EDA synthesis** (CRITICAL PATH): run full design, get timing report and utilization; fix any negative slack SAME DAY ← COMPLETE Jun 30
&#x20;  RESULTS: Setup +28.619ns margin, Hold +0.322ns margin (both positive, timing MET); 4% LUTs, 3% Registers, 9% DSP used; 0 errors
&#x20;  NEXT: HOME DEPOT RUN with Dad: 4" Sch 40 PVC, 1" PVC, end caps, L-brackets, JB Weld, marine silicone (deferred to Jul 1)

3\. **Jul 1 — Hull fabrication start**: cut and test-fit PVC pontoons; MCP6022 arrives (Prime)

4\. **Jul 2 — Layer A bench check**: TCT40-16T→MOSFET→5V→air path→TCT40-16R scope; frequency sweep 37–43 kHz in 250 Hz steps; confirm -6dB band spans 38.5–41.5 kHz (narrow chirp if not)
&#x20;  uart_rx.v: UART inbound path for K_SHIFT/FLOOR config + matched-filter reference chirp BSRAM load

5\. **Jul 3 — ESP32 vehicle firmware**: micro-ROS init, LEDC PWM on GPIO25/26 (ENA/ENB), stall-current monitoring, MPU-6050 I2C, JSN-SR04T 30cm ESTOP

6\. **Jul 4-5 — ESP32 buoy firmware**: LFM chirp generation (38.5→41.5 kHz up-sweep / 41.5→38.5 kHz down-sweep), IRLZ44N drive at 40 kHz, 3× TCT40-16T per buoy

Week 6 progress: ✅ top_level.v synthesized with positive timing slack (Jun 30); ⏳ hull pontoons fabrication (target Jul 1–2); ⏳ Layer A acoustic path bench check (target Jul 2)
Exit criterion: all three gates cleared by Jul 5



\### 🔴 CRITICAL PATH WARNING (updated Jun 28)

Week 5 was completely lost — zero tasks completed. 43 days remain.
Pool test #1 is FIXED at Week 9 (Jul 20). This cannot slip.
top_level.v + Gowin synthesis are the highest-value FPGA actions remaining.
Synthesis converts 9 isolated simulations into a proven hardware design.
A synthesis failure found Week 6 is solvable; found Week 7 or later is a crisis.



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
# Today June 28 2026 = Week 5 Day 7 (last day of Week 5) / Week 6 starts tomorrow Jun 29
# Deadline August 10 2026 falls the day after W11 ends — hard cutoff — 43 days remaining



| Week | Dates | Phase | Status |

|---|---|---|---|

| 1  | May 25–May 31 | Foundation + ordering                                    | 🔴 Partial |
| 2  | Jun 01–Jun 07 | AD9226 interface + hull start                            | 🔴 Partial |
| 3  | Jun 08–Jun 14 | Timing constraints + FIR banks verified                  | ✅ Done |
| 4  | Jun 15–Jun 21 | Matched filters + peak detector — ALL 9 modules verified | ✅ Done |
| 5  | Jun 22–Jun 28 | Pipeline integration + synthesis (LOST — zero tasks done) | 🔴 Lost |
| 6  | Jun 29–Jul 05 | top_level.v + Gowin synthesis + Layer A + ESP32 + hull start | 🟡 Current |
| 7  | Jul 06–Jul 12 | ROS 2 nodes + Layer B ADC capture                        | ⚪ |
| 8  | Jul 13–Jul 19 | Full system integration + dry-land E2E rehearsal         | ⚪ |
| 9  | Jul 20–Jul 26 | Pool test #1 (HARD DATE — cannot slip)                   | 🎯 Milestone |
| 10 | Jul 27–Aug 02 | Pool test #2 + tuning + two-buoy attempt                 | ⚪ |
| 11 | Aug 03–Aug 09 | Polish + demo video only (no new features)               | 🏁 Deadline |



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

│   │   ├── uart\_tx.v          ← DONE — single-byte UART serializer (PHY layer)

│   │   ├── uart\_rx.v          ← DONE (Jul 1) — 4-byte config/BSRAM loader inbound path, pin assignment unverified

│   │   ├── adc\_interface.v    ← DONE — AD9226 parallel capture

│   │   ├── cic\_decimator.v    ← DONE — R=8 N=3 CIC

│   │   ├── fir\_filter\_bank1.v ← DONE — 38.5–41.5kHz per FC-7

│   │   ├── fir\_filter\_bank2.v ← DONE — 38.5–41.5kHz per FC-7 (identical coeff)

│   │   ├── matched\_filter\_1.v ← DONE — RTL unchanged, up-sweep ref loaded at runtime

│   │   ├── matched\_filter\_2.v ← DONE — RTL unchanged, down-sweep ref loaded at runtime

│   │   ├── peak\_detector.v    ← DONE — dual-channel relative gating (FC-7), SNR proxy

│   │   ├── packet\_framer.v    ← DONE — 8-byte FSM ([target\_id][peak\_lag\_H/L][corr\_peak\_H/L][snr][XOR][0xFF]) feeding uart\_tx byte-by-byte

│   │   └── top\_level.v        ← DONE (Jun 29) — 9-module integration, synthesized with +28.6ns setup slack

│   ├── sim/               ← Icarus testbenches (10/10 PASS)

│   └── constraints/       ← .cst files (Gowin format)

├── ros2\_ws/

│   └── src/

│   │   ├── vehicle\_control/

│   │   │   ├── motor\_driver\_node.py      ← DONE (Jul 1) — 80% duty cap, watchdog, diff-thrust diagnostics

│   │   │   └── collision\_safety\_node.py  ← DONE (Jul 1) — 30cm ESTOP gate, timeout fail-safe

│   │   ├── acoustic\_homing/

│   │   │   ├── acoustic\_homing\_node.py   ← DONE (Jul 1) — FC-6/FC-7/FC-8 state machine, SNR-gradient homing, egress

│   │   │   └── mission\_state\_machine.py  ← DONE (Jul 1) — state logging, elapsed time tracking

│   │   └── telemetry/

│   │   │   ├── telemetry\_node.py         ← DONE (Jul 1) — UDP JSON to shore display, 2Hz, WiFi non-fatal

│   │   │   └── dead\_reckoning/

│   │   │       └── dead\_reckoning\_node.py ← DONE (Jul 1) — custom EKF, unicycle model, cuttable for MVP

├── esp32/

│   ├── vehicle\_firmware/

│   │   └── vehicle\_firmware.ino ← Built Jun 29, unflashed/untested — LEDC PWM (GPIO25/26), stall-current trip, MPU-6050, JSN-SR04T ESTOP

│   ├── buoy\_firmware/

│   │   ├── buoy\_firmware.ino   ← Built Jun 29, unflashed/untested — chirp generator, MOSFET drive

│   │   └── chirp\_generator.h   ← LFM generation (38.5→41.5 kHz up-sweep, 41.5→38.5 kHz down-sweep)

│   └── bench\_test/

│       └── chirp\_rx\_bench/    ← Pre-existing bench test sketch

├── hub/

│   ├── asv\_hub\_v2.html    ← current working version

│   └── asv\_hub\_v3.html    ← build target

└── docs/

&#x20;   ├── progress.md        ← daily progress notes for briefing agent

│   ├── TRAJECTORY.md      ← forward constraints (FC-#), pipeline status, physical verification queue

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

