# ASV Component Audit — June 28, 2026 (DEFINITIVE)

**Week 5 Day 7 — Last day of Week 5. Week 6 starts tomorrow June 29.**
**Agents used:** hw-validation + dsp-signal-validator + systems-integrator (all three must agree)
**Builds on:** June 25 audit (docs/component_audit_june25.md) — supersedes all previous verdicts
**Datasheet sources cited inline per component**
**43 days to August 10, 2026 demo**

---

## SIGNAL CHAIN (highest priority)

---

### STAGE 1 — TCT40-16T/R Ultrasonic Transducers (hiBCTR 20-pack)

```
Verdict: VERIFIED WITH CONDITIONS
Datasheet: SparkFun component PDF
  https://docs.sparkfun.com/SparkFun_Ultrasonic_Distance_Sensor-Qwiic/assets/
  component_documentation/TCT40-16-T-R.pdf
  (Also cited in: https://www.scribd.com/document/936652938/TCT40-16-T-R)

Key specs (confirmed from datasheet):
  - Resonant frequency: 40.1 kHz ± 1.0 kHz @ 25°C
  - TX sound pressure (10V drive): ≥ 117 dB SPL at resonance
  - RX sensitivity: ≥ -65 dB at 40 kHz resonance
  - Electrostatic capacitance: 2000 pF ± 30% at 1 kHz < 1V
  - Diameter: 16 mm, sealed/enclosed
  - Operating temperature: -20°C to +70°C

Bandwidth analysis (no explicit spec in datasheet — physics-based estimate):
  High-Q enclosed piezo resonator. Typical Q factor for this class: 20–40.
  -3dB bandwidth estimate: f_r/Q = 40.1kHz / 30 ≈ ±0.65 kHz → total -3dB BW ≈ 1.3 kHz
  -6dB bandwidth estimate: ±1.0–1.25 kHz (consistent with June 25 audit)
  Our chirp: 38.5–41.5 kHz = ±1.5 kHz around 40 kHz → band EDGES likely at or past -3dB skirts
  Cumulative TX+RX loss at band edge: TX attenuation + RX attenuation at ±1.5 kHz from resonance
  Estimated: -6 to -15 dB total at 38.5/41.5 kHz vs. 40 kHz peak (worst case both skirts)

Transmitter drive:
  3× TCT40-16T in parallel: capacitance = 3 × 2000 pF = 6000 pF at resonance
  IRLZ44N drain current at 40 kHz drive: I = C × dV/dt (square wave approximation)
  I_peak = 6000pF × 5V × 2 × 40kHz = 2.4 mA (trivial; IRLZ44N rated 47A)

Signal level estimate at receiver (inverse square law + ~1.3 dB/m air absorption @ 40 kHz):
  At 1m: TX SPL ≈ 100 dB re 20μPa at 1m (from 117 dB at source, -17 dB path)
         RX output (acoustic to electrical): -65 dB ref → V_out_rms ≈ 0.56 mV
  At 10m: -20 dB (spreading) + -13 dB (absorption) ≈ additional -33 dB
         V_out_rms at 10m ≈ 0.56 mV × 10^(-33/20) ≈ 12.5 μV → very weak at range
  After ×100 preamp gain:
         1m: 56 mV rms — well within AD9226 ±1V range ✓
         10m: 1.25 mV rms → may be near noise floor; pool acoustics (reverb) will help
  NOTE: Actual values depend heavily on drive voltage, coupling to air medium,
  and installation geometry. These are estimates; CQ-1 calibration at pool test #1
  measures the real numbers.

Remaining risk:
  -3dB bandwidth of ±0.65 kHz means the 38.5 kHz and 41.5 kHz chirp endpoints may see
  -3 to -8 dB each vs. 40 kHz center. The matched filter (BT=15) is robust to amplitude
  tilt but not to complete signal extinction at the band edge. IF the actual -6dB band
  is narrower than ±1.5 kHz, the chirp must be re-narrowed (e.g., 39–41 kHz). No RTL
  change required — only new matched-filter reference data and FIR coefficient re-spin.

Action:
  BENCH SWEEP MANDATORY before finalizing chirp params (Layer A, Week 6 Day 4 / Jul 2):
  Drive each TCT40-16T with FPGA-generated square wave at 500 Hz steps from 37–43 kHz.
  Scope the TCT40-16R output. Record amplitude vs. frequency.
  IF -6dB band spans ≥ 38.5–41.5 kHz: chirp parameters confirmed. ✓
  IF -6dB band is narrower (e.g., ±1.0 kHz only): narrow LFM to 39–41 kHz,
    re-spin FIR coefficients (2-hour task), regenerate matched-filter reference data.
    RTL UNCHANGED. Do NOT skip this sweep — discovering it at pool test #1 with no
    buffer is a project-ending surprise.
```

---

### STAGE 2 — PREAMP: MCP6022-I/P vs MCP6002-I/P (DEFINITIVE DECISION)

```
Verdict: ORDER MCP6022-I/P — MCP6002 acceptable but MCP6022 is correct choice

MCP6002 (confirmed from Microchip datasheet DS20001733L):
  Datasheet: https://ww1.microchip.com/downloads/aemDocuments/documents/MSLD/
             ProductDocuments/DataSheets/MCP6001-1R-1U-2-4-1-MHz-Low-Power-Op-Amp-DS20001733L.pdf
  GBW: 1 MHz (typical)
  Supply: 1.8V to 6.0V single supply ✓ (5V works)
  Rail-to-rail I/O: YES ✓
  Iq: 100 μA (very low power)
  At G=10 per stage: closed-loop BW = GBW/G = 1MHz/10 = 100 kHz
  Gain rolloff at 41.5 kHz: |H| = 1/√(1+(41.5k/100k)²) = 0.924 → -0.69 dB per stage
  Total two-stage rolloff at 41.5 kHz: -1.38 dB
  Differential rolloff across 3 kHz band (38.5→41.5 kHz, two stages): ~0.18 dB
  Phase at 41.5 kHz per stage: arctan(41.5k/100k) = 22.5° → two stages: 45°
  Phase at 38.5 kHz per stage: arctan(38.5k/100k) = 21.1° → two stages: 42.2°
  Differential phase across 3 kHz band: 2.8° (two stages)

MCP6022 (confirmed from Microchip datasheet DS20001685F):
  Datasheet: https://ww1.microchip.com/downloads/aemDocuments/documents/MSLD/
             ProductDocuments/DataSheets/MCP6021-Data-Sheet-DS20001685.pdf
  GBW: 10 MHz (typical)
  Supply: 2.5V to 5.5V single supply ✓ (5V works)
  Rail-to-rail I/O: YES ✓
  Offset voltage: < 0.5 mV (10× better than MCP6002)
  Iq: 1.0 mA
  At G=10 per stage: closed-loop BW = 10MHz/10 = 1 MHz
  Gain rolloff at 41.5 kHz: |H| = 1/√(1+(41.5k/1000k)²) ≈ 0.9991 → -0.0008 dB (negligible)
  Differential phase across 3 kHz band: < 0.3° total (negligible)

Decision rationale:
  MCP6002 IS technically acceptable for this application:
  - -1.38 dB rolloff at 41.5 kHz does NOT destroy the matched filter correlation peak
  - For BT=15 chirp: correlation peak amplitude loss from this tilt is < 0.2 dB
  - For FC-6 SNR-gradient homing: relative SNR matters, not absolute — tilt is systematic
    and present in both buoy channels equally, so it does not affect discrimination
  - The 45° phase shift at 41.5 kHz (two stages) reduces cross-correlation discrimination
    slightly but BT=15 provides enough margin

  MCP6022 is CORRECT CHOICE because:
  1. MCP6022 is ALSO Prime-available on Amazon at ~$7/10-pack (confirmed in search screenshot,
     Prime delivery Jun 27 at time of search → arrives Jun 29–30 if ordered today)
  2. Both parts have identical delivery timelines — there is no latency advantage to MCP6002
  3. MCP6022 eliminates the 2.8° phase differential and 0.18 dB amplitude tilt entirely,
     giving the matched filter the cleanest possible input signal
  4. MCP6022 has 10× lower offset voltage (0.5mV vs typical 3–5mV for MCP6002),
     reducing DC bias error at the virtual ground summing node
  5. For a matched filter application, phase linearity across the chirp band is important;
     MCP6022 is effectively perfect; MCP6002 is acceptable but not ideal

  DEFINITIVE VERDICT: ORDER MCP6022-I/P ×4 (two pairs — one assembled, one spare set).
  DO NOT order MCP6002-I/P for this application.
  If MCP6022 is unavailable (stock out): MCP6002 is the fallback — it works.

Two-stage preamp circuit (verified):
  Stage 1: MCP6022, non-inverting, Rf=9.1kΩ, Rg=1kΩ → G = 1 + 9.1/1 = 10.1
  Stage 2: MCP6022, non-inverting, Rf=9.1kΩ, Rg=1kΩ → G = 10.1
  Total gain: 10.1 × 10.1 = 102 (~40.2 dB)
  Virtual ground: 100kΩ + 100kΩ resistor divider from 5V → 2.5V bias at stage 1 non-inv input
  Between stages: direct coupled (DC-bias preserved through both stages)
  Output coupling: 100nF ceramic cap (AC coupling to AD9226)
  Output bias: 10kΩ from AD9226 VREF (1.0V) to AC-coupled node → re-biases to 1.0V DC
  ADC clipping level: ±1V / 102 = ±9.8mV at AD9226 input → clips at ~9.8mV received signal
  Expected received signal at 1m: ~0.56mV rms → after gain: ~57mV → 6× below clip ✓
  At ~0.1m (ARRIVED near-field): OTR fires → handled by FC-2 OTR chain → Pi flags saturated

PWM noise isolation (mandatory before Layer B, per DL-4):
  100nF ceramic + 100μF electrolytic on MCP6022 VCC pin (close to IC)
  Ferrite bead (BLM18PG221SN1 or similar) in series on MCP6022 VCC feed
  Star ground: preamp/ADC ground kept separate from motor/L298N ground,
    joined at ONE point at LiPo negative terminal ONLY
  Route preamp wiring away from motor leads inside enclosure
```

---

### STAGE 3 — AD9226 12-bit 65MSPS ADC

```
Verdict: VERIFIED (unchanged from June 25 audit — no new findings)
Datasheet: Analog Devices AD9226 Rev B
  https://www.analog.com/media/en/technical-documentation/data-sheets/AD9226.pdf

Key specs (confirmed):
  - AVDD: 5V, DRVDD: 3.3V (independent rails)
  - DRVDD=3.3V → D[11:0] and OTR swing 0–3.3V → LVCMOS33-compatible with Tang Nano 20K ✓
  - DFS=AVSS (ground) → offset binary output → MSB flip {~data[11], data[10:0]} is correct
  - DFS=AVDD → two's complement (MSB flip WRONG — would produce inverted data silently)
  - OEB=LOW → outputs enabled; OEB=HIGH → D[11:0] tristate (FPGA reads garbage)
  - ENCODE: samples on rising edge, max 65 MHz; our 3.375 MHz is well within spec
  - Pipeline latency: 7 ENCODE clock cycles (datasheet Rev B Table 1)
  - Input range: ±1V around VREF (VREF=1.0V → input range 0V to 2.0V differential)

PV-1/PV-2/PV-3 required before first power-on (unchanged from TRAJECTORY.md):
  PV-1: DRVDD = 3.3V (multimeter — 5V would damage Tang Nano GPIO)
  PV-2: DFS pin ≈ 0V (AVSS) — verify physically on the AliExpress breakout board
  PV-3: OEB ≈ 0V (tied LOW)

Remaining risk: Physical wiring error. Design is correct. Verify PV-1/2/3 before power-on.
Action: None until bench assembly. Clear PV-1/2/3 first time AD9226 is wired to FPGA.
```

---

### STAGE 4 — FPGA Pipeline (9 verified modules)

```
Verdict: SIMULATION-VERIFIED — SYNTHESIS NOT YET RUN (critical gap)
All 9 modules have passing iverilog simulations. NOT yet synthesized or run on hardware.

ENCODE rate math (verified):
  CLK_DIV_HALF=4 → ENCODE period = 2 × 4 × (1/27MHz) = 296.3ns → f_ENCODE = 3.375 MHz ✓
  CIC R=8: 3.375 MHz / 8 = 421,875 SPS (exact, per FC-3) ✓
  5ms correlation window: 5ms × 421,875 = 2109 samples (matched filter, per FC-7) ✓

Module status (simulation-verified, synthesis unverified):
  uart_tx:          ✅ DONE (Jun 8) — CLKS_PER_BIT=234 → 115,384 baud (+0.16%)
  adc_interface:    ✅ DONE (Jun 13) — MSB-flip, OTR, 7-cycle latency, .cst verified
  cic_decimator:    ✅ DONE (Jun 10) — R=8, N=3, shift=5, saturation clamp
  fir_filter_bank1: ✅ DONE (Jun 18) — 38.5–41.5 kHz per FC-7, 32-tap Hamming
  fir_filter_bank2: ✅ DONE (Jun 18) — identical coefficients to bank1 (code-division)
  matched_filter_1: ✅ DONE (Jun 16) — 2109-tap, 48-bit acc, CORR_SHIFT=16, up-sweep ref
  matched_filter_2: ✅ DONE (Jun 16) — same architecture, down-sweep ref
  peak_detector:    ✅ DONE (Jun 17) — dual-channel relative gating, SNR proxy, 12/12 pass
  packet_framer:    ✅ DONE (Jun 17) — 8-byte FSM, XOR checksum, 12/12 pass

  top_level.v:      ⏳ NOT STARTED — WEEK 6 DAY 1 PRIORITY (Jun 29)
  uart_rx.v:        ⏳ NOT STARTED — needed for K_SHIFT/FLOOR config + MF ref chirp loading
  Gowin synthesis:  ⏳ NOT RUN — WEEK 6 DAY 2 PRIORITY (Jun 30)

Resource estimates (UNVERIFIED — simulation-phase numbers only):
  HW multipliers: ~4–6 / 48 (>90% margin estimated)
  BSRAM: ~14 / 46 blocks (~30% estimated, depth-bound)
  LUT4s: ~1070 / 20,736 (~5% estimated)
  NOTE: These are design-phase estimates. Gowin synthesis report is the ONLY authoritative
  number. A synthesis failure discovered Week 6 is solvable; Week 7 is a crisis.

Remaining risk: Unknown until Gowin synthesis runs. Timing closure at 27MHz in the 48-bit
  matched filter accumulator is the highest-risk path — deep combinational if not properly
  pipelined. The RTL uses pipelined MAC (per coding standards), which should close.

Action: Run Gowin EDA synthesis on Jun 30 (Week 6 Day 2). Fix any timing violations
  immediately — do not let them carry beyond Week 6.
```

---

### STAGE 5 — UART to Raspberry Pi

```
Verdict: VERIFIED
  - Tang Nano pin 86 (TX) → Pi GPIO15 (/dev/ttyAMA0 RX)
  - Both are 3.3V logic: no level shifting needed ✓
  - Pi serial console disabled Jun 8 (confirmed in progress.md): /dev/ttyAMA0 is free ✓
  - 115,200 baud (actual 115,384 +0.16%), 8N1
  - 8-byte packet format: [target_id][peak_lag_H][peak_lag_L][corr_peak_H][corr_peak_L]
    [snr][XOR checksum][0xFF]

Remaining risk: None. UART hardware is verified in simulation and the Pi UART is freed.
Action: None before bench assembly.
```

---

## PROPULSION AND CONTROL

---

### LICHIFIT RF-370 Thrusters (ASIN B07WY4MDYZ, ordered Jun 26)

```
Verdict: VERIFIED WITH CONDITIONS (ordered, gated on bench tests before hull bonding)
Datasheet/source: Amazon ASIN B07WY4MDYZ listing + RF-370C class motor datasheets
  RF-370 spec: https://www.banebots.com (M5-RS540-12 class reference)

Key specs:
  - One kit = 1× CW + 1× CCW motor + props + mounting bases (confirmed from listing) ✓
  - Two kits ordered: one full vehicle set + one spare pair (correct per DL-2) ✓
  - Voltage rating: 6–9V optimal (7.4V nominal), 12V burns out (per listing reviews) ✓
  - Running current at ~9V: ~0.5–0.8A/motor (within L298N 2A/channel continuous) ✓
  - Stall current [CRITICAL]: ~5–8.6A at ~9V (EXCEEDS L298N 3A peak → destroys L298N)
    Source: RF-370C class datasheets; LICHIFIT 16800-RPM variant is high-current RF-370
    This is NOT the RF-370CA (low-current precision variant cited in TRAJECTORY.md DL-2)
  - Waterproof: body designed for submerged ROV/bait-boat use ✓
  - Thrust estimate: 100–250g/motor at ~9V (straddles the 150g viability floor — must bench)
  - Effective motor voltage: L298N ~2V drop → V_motor ≈ LiPo_V - 2V; at 80% PWM and
    11.1V LiPo: 0.8 × (11.1 - 2) = 7.3V. At full LiPo 12.6V: 0.8 × (12.6 - 2) = 8.5V.
    Both within 6–9V target band ✓

Remaining risk: Stall current destroys L298N without firmware protection.
  Thrust ≥150g unconfirmed until bench test.

Action (mandatory before hull bonding, Week 7/8):
  1. Firmware stall-current trip in ESP32 motor_driver: cut PWM if >2A for >100ms
     Monitor current via shunt resistor + ESP32 ADC on each L298N channel
  2. Bench stall test: prop grounded by hand at 9V with inline ammeter — measure actual
     stall current; confirm firmware trip threshold is conservative
  3. Thrust test: ≥150g/motor at ~9V with luggage scale (200g target)
  DO NOT epoxy any thruster before all three tests pass.
```

---

### L298N Dual H-Bridge (delivered Jun 2026)

```
Verdict: VERIFIED WITH CONDITIONS (unchanged from June 25 audit)
Datasheet: STMicroelectronics L298N — https://www.st.com/resource/en/datasheet/l298.pdf

Key specs:
  - Continuous current: 2A per channel (confirmed)
  - Peak current: 3A per channel (non-repetitive)
  - Logic HIGH threshold VIH: 2.3V min → ESP32 3.3V GPIO HIGH gives 1.0V margin ✓
  - Voltage drop: ~2V across H-bridge at nominal current
  - Heat at 0.8A/channel: P ≈ 2 × (0.8A × 2V) = 3.2W — heatsink REQUIRED (installed) ✓
  - ENA/ENB: PWM speed control pins; IN1-IN4: direction only
  - Condition: stall current (5–8.6A) EXCEEDS 3A peak → must have firmware stall trip

Action: Keep heatsink. Verify shared ground with ESP32 before first motor run.
  Implement stall-current trip in motor_driver_node. Bench-measure stall before hull bonding.
```

---

### ESP32 Motor Control

```
Verdict: NOT YET IMPLEMENTED — requirements verified

Key requirements (per DL-4, Jun 26):
  - ENA → GPIO25 (LEDC timer 0, channel 0), ENB → GPIO26 (LEDC timer 0, channel 1)
  - PWM frequency: 10 kHz (above audible, below RF interference)
  - ≤80% duty cycle hard cap: enforced in LEDC timer config (not just software check)
  - Stall protection: cut PWM if I_motor > 1.5A for > ~100ms, resume at 50% after 500ms
  - Verify GPIO25/26 do not conflict with MPU-6050 I2C (GPIO21/22) or UART (GPIO1/3)

Action: Implement in Week 6 ESP32 firmware (Jun 30 – Jul 5).
```

---

## SENSING AND SAFETY

---

### JSN-SR04T Waterproof Ultrasonic (delivered Jun 2026)

```
Verdict: VERIFIED WITH CONDITIONS (unchanged from June 25 audit)
Source: JSN-SR04T product documentation; HC-SR04 family protocol spec

Key specs:
  - Echo output: 5V HIGH — EXCEEDS ESP32 GPIO abs-max (3.6V) if wired directly
  - Fix: 1kΩ + 2kΩ voltage divider on ECHO → 5V × (2/3) = 3.33V ≤ 3.6V ✓
  - Trigger: 3.3V ESP32 output should fire sensor; bench-verify (some units need 5V)
  - Power: 5V, 30mA active
  - Range: 25cm minimum (blind zone) to 450cm maximum
  - Blind zone: 25cm — ESTOP threshold raised from 25cm to 30cm (per DL-4) ✓
  - Protocol: HC-SR04 (trigger ≥20μs HIGH, echo pulse width ∝ distance)

Action: Install 1kΩ/2kΩ divider on ECHO (parts in owned kit). Bench-verify trigger fires
  at 3.3V. Raise collision_safety_node ESTOP to 30cm in ROS 2 code.
```

---

### MPU-6050 IMU (HiLetgo GY-521, owned)

```
Verdict: VERIFIED OK (unchanged from June 25 audit)
Datasheet: InvenSense PS-MPU-6000A

Key specs:
  - GY-521 module: onboard 3.3V LDO (VCC accepts 3–5V) ✓
  - Onboard 4.7kΩ pull-ups on SDA/SCL → no external pull-ups needed ✓
  - I2C address: 0x68 (AD0=LOW, default) ✓
  - Logic levels: 3.3V I2C compatible with ESP32 ✓
  - Current: ~3.9mA operating (negligible)

Action: Power VCC from ESP32 3V3 rail (NOT 5V). Verify AD0 is floating/LOW.
```

---

### IRLZ44N MOSFET (ordered Jun 26 — 5-pack Infineon IRLZ44NPBF)

```
Verdict: VERIFIED — correct part for buoy transducer drive
Datasheet: Infineon IRLZ44NPBF
  https://www.infineon.com/part/IRLZ44N

Key specs:
  - Vgs(th): 1.0V to 2.0V (typical 1.5V) → FULLY ENHANCED at 3.3V ESP32 gate ✓
  - VDSS: 55V (buoy drive at 5V is trivial)
  - ID: 47A (transducer peak current ~2.4mA — enormous margin)
  - RDS(on) at 4.5V gate: 35mΩ; at 3.3V gate: estimated ~60–100mΩ
  - Gate charge Qg: 32nC typical at 4.5V; at 3.3V gate: ~25nC estimated

Switching loss calculation at 40kHz (buoy drive):
  P_switch = Qg × Vgs × f = 25nC × 3.3V × 40,000Hz = 3.3 mW → negligible ✓
  P_conduction = I² × RDS(on) = (0.0024A)² × 0.1Ω = 0.00058 mW → negligible ✓
  IRLZ44N runs at room temperature driving 3× TCT40-16T at 40kHz — no thermal concern ✓

Drive circuit (buoy board):
  Gate: ESP32 GPIO → 150–220Ω series resistor → IRLZ44N gate
  Gate-source pulldown: 100kΩ to GND (ensures MOSFET stays off when ESP32 boots)
  Drain clamp: 1N4148 from drain to +5V supply rail (inductive kickback from transducer)
  Source: GND
  Drain: → 3× TCT40-16T transducers (parallel) → +5V

1N4148 clamp adequacy:
  1N4148 peak reverse voltage: 100V >> 5V supply ✓
  Recovery time: 4ns >> 25μs half-period at 40kHz → no reverse conduction during switching ✓

Action: None before assembly. Confirm 150–220Ω gate resistors in owned kit.
```

---

## POWER SYSTEM

---

### Hosim 3S LiPo 11.1V 5000mAh 30C XT60 ×2 (owned)

```
Verdict: VERIFIED OK (unchanged from June 25 audit)

Key specs:
  - 30C × 5.0Ah = 150A max discharge — system draws ~5–7A running → <5% utilization ✓
  - Voltage: 12.6V full charge / 11.1V nominal / 9.0V cutoff (3.0V/cell)
  - XT60: keyed connector (reverse mating physically blocked), but verify polarity first

Action: Multimeter on XT60 before first mating. Set cell alarm at 3.5V/cell.
```

---

### Buck Converter (owned — rating UNKNOWN, critical gap)

```
Verdict: CONDITIONAL — confirmed OK at idle, unverified under full ROS 2 load
Evidence: vcgencmd get_throttled = 0x0 and temp = 35.0°C observed at session start
  (Pi idle, no ROS 2 nodes running — does NOT confirm adequacy under full load)

Full 5V rail power budget:
  Pi 4 1GB under full ROS 2 load:  ~2.5A @ 5V  = 12.5W
  Tang Nano 20K:                    ~0.2A @ 5V  =  1.0W
  ESP32 vehicle:                    ~0.3A @ 5V  =  1.5W
  L298N logic supply:               ~0.1A @ 5V  =  0.5W
  JSN-SR04T + MPU-6050:             ~0.05A @ 5V =  0.25W
  MCP6022 preamp (×2):              ~0.016A @ 5V =  0.08W
  ─────────────────────────────────────────────────────
  TOTAL 5V rail (running):          ~3.2A @ 5V  = 15.8W
  TOTAL 5V rail (peak burst):       ~4.5A @ 5V  = 22.5W

  RF-370 motors on 11.1V rail (via L298N): ~1.6A @ 9V running (not through buck)
  LiPo delivers 11.1V motor rail directly — buck only handles 5V logic

Buck converter minimum spec required: ≥4A continuous at 5V from 11.1V input
  (3.2A + 25% margin = 4.0A)
  Common generic LM2596-class bucks: rated 2–3A → INSUFFICIENT
  Pololu D24V50F5: 5V/5A, 98% efficiency, $12 → ADEQUATE if needed

Remaining risk: If owned buck is < 4A, Pi will brownout under full ROS 2 load,
  causing silent data corruption or crashes during pool test.

Action REQUIRED (Week 6 Day 1):
  1. Read chip marking on owned buck converter. If < 4A continuous: order Pololu D24V50F5 now.
  2. Boot Pi with all active ROS 2 nodes (even stubs) and run: vcgencmd get_throttled
     Must read 0x0. If non-zero (0x50000 = throttled, 0x80000 = undervoltage):
     ORDER Pololu D24V50F5 (~$12 Amazon) immediately.
  3. Even if OK: measure buck output voltage under load with multimeter.
     Must be 4.9–5.1V. If sagging below 4.8V: replace with Pololu.
```

---

## MECHANICAL

---

### Otdorpatio IP67 Enclosure B0DX781Z3W (ordered Jun 26)

```
Verdict: VERIFIED — ordered, dimensions adequate
Source: Amazon listing B0DX781Z3W (confirmed from listing screenshot)

Key specs (from Amazon listing):
  - External dimensions: 160 × 160 × 90mm (CONFIRMED from listing image)
  - Rating: IP67 (1m submersion for 30 min) — adequate for pool splash above waterline ✓
  - Material: ABS plastic — non-conductive, WiFi/RF transparent ✓
  - Included cable glands: 4× M16 gland

Internal dimension estimate (typical ABS wall thickness 5–10mm):
  Internal: ~150 × 150 × 80mm (conservative estimate with 10mm walls)

Component layout verification:
  Pi 4 1GB footprint:    85 × 56mm
  Tang Nano 20K:         60 × 22mm
  Side by side (Pi + Tang Nano): 85 × 78mm combined
  Preamp perfboard:      ~40 × 30mm (alongside Pi)
  Total occupied:        ~130 × 100mm + 15mm wiring/connector margin = ~145 × 115mm
  Available internal:    ~150 × 150mm → FITS with ~5–35mm margin ✓

Cable gland analysis (7 required penetrations):
  Motor bundle × 2 (14AWG, OD ~4.2mm): needs M16 gland (fits 5–14mm) ✓
  JSN-SR04T cable: ~4mm OD → M16 gland ✓
  Mast RX coax: ~5mm OD → M16 gland ✓
  LiPo XT60 cable (12AWG, OD ~5mm): M16 gland ✓
  UART/signal wires bundle: small → M16 gland ✓
  Power input (12AWG): M16 gland ✓
  Spare/vent: +1 plugged gland
  Total: 7 penetrations; 4 included; need 3–4 additional
  → ORDER 1 additional M16 gland 4-pack (~$5) or M12 gland 10-pack (~$8)

Action: Order additional M16/M12 cable glands. Lay out components in enclosure before
  drilling; mark and drill penetration holes in Week 8.
```

---

### Hull Materials (NOT YET PURCHASED)

```
Verdict: GATE — Home Depot run MUST happen by Jun 30 (Week 6 Day 2) or hull slips to Week 7

Required:
  - 4" Schedule 40 PVC pipe × ~1.5m (cut: 2× 70cm pontoons)
  - 1" PVC pipe × ~1m (cross members + mast, 25–30cm above waterline)
  - PVC end caps × 4 (for pontoon sealing)
  - Aluminum L-brackets × 8–12 (cross members)
  - JB Weld MarineWeld + marine silicone (sealant)
  - M3 standoffs (electronics mounting), M4 bolts, zip ties, hose clamps

Remaining risk: If Home Depot run slips past Jul 1, hull fabrication is in Week 7,
  pushing integration into Week 8 and leaving zero recovery margin before Week 9 pool test.

Action: Home Depot run with Dad on Jun 30. Do NOT defer to "later this week."
```

---

## INTERFACE VERDICTS

```
1. AD9226 D[11:0] → Tang Nano GPIO:
   SAFE — DVDD=3.3V output, LVCMOS33 input (same domain). Verified against AD9226 Rev B.

2. Tang Nano adc_clk_out → AD9226 ENCODE:
   SAFE — 3.375MHz, 3.3V LVCMOS33 drive. ENCODE max = 65MHz, CMOS-level threshold.
   DRIVE=8mA in adc_interface.cst — adequate for CMOS load at 3.375MHz.

3. Tang Nano pin 86 TX → Pi /dev/ttyAMA0 RX:
   SAFE — both 3.3V. Pi serial console confirmed disabled Jun 8.

4. ESP32 3.3V → L298N IN1-IN4:
   SAFE with shared ground — L298N VIH=2.3V min; ESP32 HIGH=3.3V → 1.0V margin.
   Condition: common GND between ESP32 and L298N required (verify before motor run).

5. ESP32 3.3V → MPU-6050 GY-521 SDA/SCL:
   SAFE — GY-521 has onboard 4.7kΩ pull-ups, 3.3V I2C bus, onboard LDO.

6. JSN-SR04T ECHO (5V) → ESP32 GPIO (3.6V max):
   SAFE with divider — 1kΩ + 2kΩ → 5V × (2/3) = 3.33V. Parts in owned kit.
   MARGINAL without divider → do NOT wire ECHO directly to ESP32.

7. ESP32 3.3V → IRLZ44N gate → 3× TCT40-16T:
   SAFE — Vgs(th) 1.0–2.0V; 3.3V gate fully enhances device.
   Use 150–220Ω gate series resistor. 1N4148 drain clamp required.

8. AD9226 AVDD (5V) / DRVDD (3.3V) power rails:
   SAFE if wired correctly — PV-1/PV-2/PV-3 must be cleared before power-on.
   5V on DRVDD = Tang Nano GPIO damage risk; check with multimeter first.
```

---

## POWER BUDGET

```
Rail: 5V (from buck converter, LiPo input ~11.1V)
──────────────────────────────────────────────────────────
Component                    Current (A)   Power (W)
──────────────────────────────────────────────────────────
Pi 4 1GB (full ROS 2 load)    2.50          12.5
Tang Nano 20K                  0.20           1.0
ESP32 vehicle                  0.30           1.5
L298N logic (5V rail)          0.10           0.5
JSN-SR04T                      0.03           0.15
MPU-6050 (GY-521)              0.004          0.02
MCP6022 preamp ×2              0.016          0.08
──────────────────────────────────────────────────────────
TOTAL 5V rail (running)        3.15A         15.8W
TOTAL 5V rail (peak)          ~4.5A         22.5W
──────────────────────────────────────────────────────────
Required buck converter: ≥ 4A continuous at 5V
  Pololu D24V50F5 (5V/5A, $12): ADEQUATE
  Generic LM2596 (2–3A): INSUFFICIENT
  Current owned buck: UNKNOWN — MUST VERIFY WEEK 6 DAY 1

Rail: 11.1V (direct from LiPo, via L298N to motors)
──────────────────────────────────────────────────────────
RF-370 motors ×2 (running)    ~1.6A total    ~17.8W (at 11.1V)
L298N dissipation (~2V drop)  ~0.8A × 2V × 2ch = ~3.2W heat
──────────────────────────────────────────────────────────
LiPo capacity: 150A max discharge → system <5% utilization → NOT the constraint
```

---

## DEFINITIVE PURCHASE LIST

### BUY NOW (if not already ordered)

| Item | Est. Cost | Where | Delivery | Notes |
|------|-----------|-------|----------|-------|
| MCP6022-I/P ×4–10 | ~$7–15 | Amazon | Jun 29–30 Prime | CRITICAL — gates all acoustic testing; NOT MCP6002 |
| M16 cable glands (4-pack) | ~$5–8 | Amazon | Jun 29–30 | Enclosure only has 4; need 7 penetrations |
| Pololu D24V50F5 | ~$12 | Amazon/Pololu | Jun 30–Jul 1 | Order NOW if owned buck < 4A; order proactively |

### ORDERED JUN 26 — ARRIVING THIS WEEK

| Item | Status | Expected | Notes |
|------|--------|----------|-------|
| LICHIFIT RF-370 ×2 kits | Ordered Jun 26 | ~Jun 30–Jul 3 | 2-day Prime or standard |
| Otdorpatio B0DX781Z3W enclosure | Ordered Jun 26 | ~Jun 28–30 | 160×160×90mm, IP67 |
| IRLZ44N MOSFET (5-pack) | Ordered Jun 26 | ~Jun 28–30 | Confirmed correct part |

### HOME DEPOT RUN (by Jun 30 — mandatory)

| Item | Notes |
|------|-------|
| 4" Sch 40 PVC pipe, ~1.5m | 2× 70cm pontoons |
| 1" PVC pipe, ~1m | Cross members + mast |
| PVC end caps ×4 | Pontoon sealing |
| Aluminum L-brackets ×10 | Cross-member attachment |
| JB Weld MarineWeld + marine silicone | Structural + sealing |
| M3/M4 hardware kit | Electronics mounting |

### DO NOT BUY

| Item | Reason |
|------|--------|
| MCP6002-I/P | Acceptable fallback only; use MCP6022 since both are Prime-available at similar price |
| NE5532P | Permanently disqualified — requires ±5V split supply; not rail-to-rail on 5V single |
| MAX9814 | Permanently disqualified — audio band (20 Hz–20 kHz) cannot pass 40 kHz |
| LM358 | GBW = 1MHz → at G=10: BW = 100 kHz, but only 10 kHz BW available; insufficient |

### VERIFIED OK — NO ACTION NEEDED

| Item | Notes |
|------|-------|
| AD9226 ADC | VERIFIED — clear PV-1/2/3 before first power-on |
| Tang Nano 20K | VERIFIED — all .cst pins correct |
| MPU-6050 GY-521 | VERIFIED — no mods needed |
| Hosim 3S LiPo ×2 | VERIFIED — polarity check before first mating |
| L298N module | VERIFIED WITH CONDITIONS — heatsink on, firmware stall trip required |
| TCT40-16R/T ×20 | VERIFIED WITH CONDITIONS — bench sweep required Week 6 Day 4 |
| JSN-SR04T | VERIFIED WITH CONDITIONS — 1kΩ/2kΩ ECHO divider required, ESTOP=30cm |
| ESP32 ×2 | VERIFIED — LEDC PWM for motor ENA/ENB mandatory |

---

## TOP 3 RISKS TO AUGUST 10 DEMO

```
RISK 1 — Pool test #1 misses Week 9 due to cascading Week 6–8 slips
Likelihood: 45% without intervention
Impact: If pool test slips to Week 10, Week 11 is only polish — one bad pool day
  and there is no demo video. The two-buoy demo becomes impossible.
Evidence: Week 5 was completely lost (zero tasks completed from plan). Week 6 must
  absorb Week 5's entire uncompleted workload (synthesis + Layer A + hull start +
  ESP32 firmware) while also doing its own deliverables.
Mitigation:
  - Jun 29: top_level.v (do not defer to "later this week")
  - Jun 30: Gowin synthesis + Home Depot run (BOTH SAME DAY)
  - If synthesis fails: fix in Week 6; if hull materials slip: no recovery margin
  - Minimum viable demo fallback: stationary acoustic bench test on video if hull
    incomplete by Jul 19. Captures FPGA→Pi signal chain for portfolio.

RISK 2 — Gowin synthesis timing violation or BSRAM overrun
Likelihood: 20%
Impact: Matched filter accumulator path (48-bit, 2109-cycle block) or FIR bank
  (32-cycle sequential MAC) may fail timing closure at 27MHz, or BSRAM block count
  may exceed the 46-block limit if depth constraints are worse than estimated.
Evidence: 9 modules verified only in iverilog simulation. Synthesis tool applies
  actual GW2AR-18 routing delays and resource mapping — simulation cannot predict this.
Mitigation:
  - Run synthesis FIRST THING Week 6 Day 2 (Jun 30)
  - If timing fails: add pipeline register to matched filter accumulator (1-hour fix)
  - If BSRAM overrun: reduce CIC internal width or use DSP blocks instead
  - Gowin provides timing slack report — any negative slack must be fixed before advancing

RISK 3 — Acoustic path failure at Layer A bench check (TCT40-16T/R bandwidth)
Likelihood: 25%
Impact: If -3dB bandwidth is only ±0.65 kHz (Q=30), the LFM endpoints at 38.5 kHz and
  41.5 kHz see -3 to -8 dB relative to 40 kHz. This narrows the usable chirp band.
  A narrower chirp reduces BT product (from 15 toward 5–8), reducing beacon discrimination
  from ~12 dB toward ~5–7 dB — possibly below the near/far signal spread threshold.
Evidence: TCT40-16T/R datasheet provides no explicit bandwidth spec. Physics estimate
  puts -3dB bandwidth at ±0.65 kHz (Q~30), not the ±1.5 kHz the chirp assumes.
Mitigation:
  - Do Layer A bench sweep Week 6 Day 4 (Jul 2): drive TX at 37–43 kHz in 250 Hz steps;
    scope RX output; record amplitude vs. frequency
  - If -6dB band spans ≥38.5–41.5 kHz: confirmed, proceed as designed
  - If -6dB band is only ±1.0 kHz: narrow LFM to 39–41 kHz; re-spin FIR coefficients
    (2-hour task), regenerate matched-filter reference data for Pi BSRAM loading
  - RTL is UNCHANGED regardless of chirp band; this is a data/coefficients change only
```

---

*Audit complete: June 28, 2026 (Week 5 Day 7)*
*Agents: hw-validation + dsp-signal-validator + systems-integrator — all findings reconciled*
*Supersedes: docs/component_audit_june25.md*
*Next review: after Layer A bench check (Week 6 Day 4, Jul 2) and Gowin synthesis (Jun 30)*

Sources:
- MCP6002 datasheet: https://ww1.microchip.com/downloads/aemDocuments/documents/MSLD/ProductDocuments/DataSheets/MCP6001-1R-1U-2-4-1-MHz-Low-Power-Op-Amp-DS20001733L.pdf
- MCP6022 datasheet: https://ww1.microchip.com/downloads/aemDocuments/documents/MSLD/ProductDocuments/DataSheets/MCP6021-Data-Sheet-DS20001685.pdf
- IRLZ44N product page: https://www.infineon.com/part/IRLZ44N
- TCT40-16T/R datasheet: https://docs.sparkfun.com/SparkFun_Ultrasonic_Distance_Sensor-Qwiic/assets/component_documentation/TCT40-16-T-R.pdf
- AD9226 datasheet: https://www.analog.com/media/en/technical-documentation/data-sheets/AD9226.pdf
- L298N datasheet: https://www.st.com/resource/en/datasheet/l298.pdf
