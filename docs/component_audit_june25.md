# ASV Component Audit — June 25, 2026
**Audit scope:** All 16 components + cross-system checks  
**Agents used:** hw-validation (×3 groups), dsp-signal-validator, systems-integrator  
**Datasheet sources:** Analog Devices AD9226 Rev B, onsemi NE5532, ST L298N, InvenSense MPU-6000A, Sipeed Tang Nano 20K wiki + schematic rev 1.22, Amazon listings, WebSearch  
**Project deadline:** August 10, 2026 (46 days from today)

---

## PURCHASED COMPONENTS

---

### COMPONENT 1: AD9226 12-bit 65MSPS ADC

```
STATUS: VERIFIED OK
SPEC CHECKED (AD9226 datasheet Rev B, Analog Devices):
  a) DRVDD rail: Independent of AVDD. DRVDD=3.3V → Voh=2.95V (IOH 0.5mA), Vol=0.4V →
     D[11:0] and OTR are fully LVCMOS33-compatible with Tang Nano 20K. AVDD=5V separate. ✅
  b) DFS=AVSS (ground) → offset-binary output. MSB-flip {~data[11], data[10:0]} in
     adc_interface.v is the correct decode to two's complement signed. ✅
  c) OEB=LOW → output drivers enabled. OEB=HIGH → D[11:0] tristate (FPGA reads garbage).
     OEB must be tied LOW. ✅
  d) Pipeline latency: 7 ENCODE clock cycles. CLAUDE.md and TRAJECTORY.md are correct. ✅
  e) ENCODE pin: samples on rising edge, max 65MHz, 1–5MHz is well within spec. ✅
  f) TRAJECTORY.md PV-1/PV-2/PV-3 checklist confirmed by datasheet. ✅
VERDICT: AD9226 hardware contract in CLAUDE.md is datasheet-accurate. Correct part for its
  role. The one risk is a wiring mistake on the physical board — not a design defect.
ACTION REQUIRED: BENCH VERIFY BEFORE FIRST POWER-ON:
  PV-1: Multimeter on DRVDD = 3.3V (NOT 5V). 5V on DRVDD = Tang Nano GPIO damage.
  PV-2: DFS pin ≈ 0V (tied to AVSS, not AVDD). Wrong = offset-binary decode breaks.
  PV-3: OEB pin ≈ 0V (tied LOW). Wrong = tristated bus, FPGA reads floating.
```

---

### COMPONENT 2: TCT40-16R/T hiBCTR Ultrasonic Transducers

```
STATUS: VERIFIED WITH CONDITIONS
SPEC CHECKED (generic 40kHz enclosed piezo class; TCT40-16 specific datasheet not located):
  a) Resonant frequency: 40kHz ± 1.0kHz nominal — consistent with FC-7 center. ✅
  b) -3dB bandwidth (CRITICAL): High-Q resonant piezo. Typical -6dB bandwidth for 16mm
     40kHz enclosed piezo is ~1.5–2.5kHz TOTAL (±0.75–1.25kHz). The -3dB bandwidth is
     NARROWER. Our chirp spans 38.5–41.5kHz = ±1.5kHz — the band endpoints may sit at or
     beyond the -3dB skirts. Off-resonance loss is cumulative across TX and RX: expect
     -6 to -12dB attenuation at 38.5kHz and 41.5kHz vs the 40kHz peak.
  c) Sensitivity: TX ~110–120dB SPL/V at resonance; RX ~-65dB at resonance, both falling
     steeply off-resonance (this is a resonant element, not wideband).
  d) Max drive: ~20Vpp (10Vrms) — fine for MOSFET drive at 5V.
  NOTE: FC-7 (TRAJECTORY.md) already documented this bandwidth constraint from a prior
  hw-validation bench check (DL-1 addendum, Jun 17). This audit confirms the physics are
  consistent. The transducers are ALREADY OWNED — this is not a purchase blocker.
VERDICT: Transducers will work but may attenuate the 38.5/41.5kHz chirp endpoints by
  -6 to -12dB. Whether the usable -6dB band fully spans 38.5–41.5kHz must be confirmed by
  bench sweep — it is a gate before finalizing chirp parameters, not a purchase gate.
ACTION REQUIRED: BENCH SWEEP BEFORE CHIRP FINALIZATION (gates pool test #1):
  Drive one TCT40-16T at each frequency from 36–44kHz via function generator + MOSFET.
  Scope the TCT40-16R output through the full TX+RX air path. Record amplitude vs frequency.
  IF -6dB band spans 38.5–41.5kHz: chirp parameters confirmed, proceed as designed.
  IF -6dB band is narrower (e.g. only ±1kHz): narrow the LFM chirp to 39–41kHz and
    regenerate matched-filter reference data for both channels. No RTL change, only data.
```

---

### COMPONENT 3 / 9: NE5532P Op-Amp Kit (VIBICCK B0FNDB9MWV)

```
STATUS: FAILED
SPEC CHECKED (onsemi NE5532-D datasheet, recommended operating conditions):
  a) Supply voltage: MIN ±5V per rail = 10V TOTAL minimum. All electrical characteristics
     specified at ±15V. Single 5V supply (VCC+=5V, VCC-=GND = 5V total) is HALF the
     minimum → operation is OUT OF SPEC and uncharacterized.
  b) Output swing: NE5532 is NOT rail-to-rail. Output cannot approach within ~1.5–2V of
     either supply rail. On 5V total with 2.5V virtual ground, usable swing collapses to
     ±0.5–1V at best — insufficient for the AD9226 ±1V input requirement.
  c) Input common-mode range: specified at ±15V supply; not guaranteed for rail-proximate
     inputs at 5V total.
  d) GBW = 10MHz — adequate for ×10/stage at 40kHz IF supply worked. Supply is the killer.
VERDICT: DO NOT USE NE5532P on a single 5V supply. It is below its minimum rated supply,
  not rail-to-rail, and cannot reliably deliver ±1V into the AD9226. Already in the parts
  kit but disqualified for this role.

RECOMMENDED REPLACEMENT:
  PRIMARY — MCP6022 ×2 (~$1.50 ea, $3.00 total):
    GBW: 10MHz | Supply: single 2.5–5.5V | Rail-to-rail I/O | ~$1.50 each
    At ×10/stage: closed-loop BW = 1MHz per stage >> 40kHz. ✅
    Two-stage ×10/×10 = ×100 total (see CHECK 15 — gain must be ×100, not ×196).
  ALTERNATE — TLV2462 ×2 (~$2.00 ea, $4.00 total):
    GBW: 6.4MHz | Supply: single 2.7–6V | Rail-to-rail | ~$2.00 each
    At ×10/stage: closed-loop BW = 640kHz per stage >> 40kHz. ✅ Buy as backup.
  REJECTED — LM358:
    GBW only 1MHz → at ×10/stage closed-loop BW = 100kHz (marginally OK), but at
    ×100 single-stage = 10kHz (BELOW 40kHz signal → attenuates the band). Disqualified.
ACTION REQUIRED: DO NOT BUY NE5532P for this role. Order MCP6022 ×2 immediately.
  The NE5532P kit in hand can be used for other low-frequency applications.
```

---

### COMPONENT 4: Tang Nano 20K FPGA (GW2AR-18)

```
STATUS: VERIFIED OK
SPEC CHECKED (Sipeed wiki, Tang_Nano_20K_3921_Schematics.pdf rev 1.22, pinout diagram):
  a) ADC bus pins: D[0]=73, D[1]=74, D[2]=75, D[3]=85, D[4]=77, D[5]=27, D[6]=28,
     D[7]=25, D[8]=26, D[9]=29, D[10]=30, D[11]=31, otr=80, adc_clk=76 — ALL confirmed
     as broken-out J5/J6 header pads, ALL in LVCMOS33-compatible banks. ✅
  b) uart_tx = pin 86 (J5 header, Bank1, LVCMOS33). ✅
  c) 27MHz oscillator = pin 4 (NOT pin 52 — pin 52 is the Tang Nano 9K clock; do not
     confuse boards). ✅
  d) pin 17 = onboard LED2 — confirmed in adc_interface.cst comment. Never route TX there. ✅
  e) pins 32–39: NOT header GPIO — routed to internal 40-pin RGB-LCD FPC connector only.
     The shipped .cst correctly avoids these. ✅
  f) GPIO drive current: LVCMOS33 IOBs programmable 4/8/12/16/24mA. adc_clk uses DRIVE=8
     — adequate for CMOS load at 1–5MHz. ✅
  SEPARATELY VERIFIED: Both .cst files (uart_tx.cst, adc_interface.cst) read from disk and
  confirmed correct. The audit's assumed values (clk=52, uart=17) were wrong; the SHIPPED
  files use clk=4 and uart=86. No blocker.
VERDICT: All ADC bus pins and UART TX pin verified as LVCMOS33-compatible header pads.
  The .cst files are correct and complete.
ACTION REQUIRED: None — .cst files are verified correct.
```

---

### COMPONENT 5: JSN-SR04T Waterproof Ultrasonic

```
STATUS: VERIFIED WITH CONDITIONS
SPEC CHECKED (makerguides.com JSN-SR04T tutorial; HC-SR04 protocol family):
  a) Echo pin: outputs 5V HIGH logic level (standard 5V module). ESP32 GPIO max input = 3.6V.
     Direct connection WITHOUT voltage divider would EXCEED ESP32 abs-max → GPIO damage risk.
  b) Trigger pin: ESP32 3.3V output should clear the TTL logic HIGH threshold — bench-verify
     the sensor fires reliably from 3.3V (some units need 5V trigger; level-shift if flaky).
  c) Power supply: 5V required, draws ~30mA active / 5mA idle.
  d) Range: 25cm–450cm. CRITICAL NOTE: minimum range = 25cm = ESTOP threshold in CLAUDE.md.
     Objects closer than 25cm fall in the blind zone and may read erratically.
  e) Protocol: standard HC-SR04 (trigger ≥20µs HIGH, echo pulse width ∝ distance).
VERDICT: Functionally correct sensor for collision avoidance, but the 5V echo output is a
  hardware damage BLOCKER if wired directly to ESP32.
ACTION REQUIRED:
  MANDATORY: Insert 1kΩ + 2kΩ voltage divider on ECHO before ESP32 GPIO.
    Vout = 5V × 2/(1+2) = 3.33V ≤ 3.6V ESP32 max. ✅ (Parts in owned kit.)
  RECOMMENDED: Raise ESTOP threshold from 25cm to 30cm in collision_safety_node.
    JSN-SR04T minimum reliable range = 25cm; the 5cm margin prevents dead-zone blindness
    at exactly the ESTOP distance. This is a one-line ROS 2 config change.
  VERIFY: Bench-confirm sensor triggers reliably from 3.3V trigger pulse (≥20µs).
    If flaky, drive trigger through a level-shifter or transistor to 5V.
```

---

### COMPONENT 6: MPU-6050 IMU (HiLetgo GY-521 Module)

```
STATUS: VERIFIED OK
SPEC CHECKED (InvenSense PS-MPU-6000A datasheet; components101.com GY-521 module page):
  a) Chip VDD: 2.375–3.46V. GY-521 module includes onboard LDO regulator — VCC input accepts
     3–5V, regulated to 3.3V for the chip. ✅
  b) I2C voltage: GY-521 has onboard 4.7kΩ pull-ups on SDA and SCL. When powered from
     ESP32 3V3 rail, pull-ups are referenced to 3.3V → I2C bus stays ≤3.3V. ✅
  c) I2C address: 0x68 (AD0=LOW, default). Confirmed. ✅
  d) No external pull-ups needed — already on module. ✅
  e) Current draw: ~3.9mA operating. Negligible on the 3.3V rail. ✅
VERDICT: Fully ESP32-3.3V-compatible. No modifications, no level shifting, no external
  pull-ups needed.
ACTION REQUIRED: Power GY-521 VCC from ESP32 3V3 rail (NOT 5V). Wiring: VCC→3V3,
  GND→GND, SDA→ESP32 SDA, SCL→ESP32 SCL, AD0 floating/LOW for address 0x68.
```

---

### COMPONENT 7: Hosim 3S LiPo 11.1V 5000mAh 30C XT60

```
STATUS: VERIFIED OK
SPEC CHECKED (Amazon listing B0G48J626R, hosim.com product page):
  a) 30C discharge: 30C × 5000mAh = 150A max continuous. System draw ~5A running / ~7A peak
     = 3–5% utilization. Massive margin — LiPo is NOT the power constraint (buck is). ✅
  b) XT60 polarity: square-chamfered pin = positive, rounded corner = negative. Connector is
     keyed (reverse mating is mechanically prevented), but verify with multimeter first. ✅
  c) Voltage range: 12.6V full / 11.1V nominal / 9.0V cutoff (3.0V/cell). L298N VS accepts
     up to 46V, buck converter accepts 12.6V. Within spec. ✅
  d) Dimensions: ~130×40×25mm. Mounts on hull platform, NOT inside electronics enclosure. ✅
  e) Budget note: budget specifies 50C; owned is 30C. No electrical difference at this load.
     Optionally correct the budget record.
VERDICT: Owned LiPo is correct and massively over-margined. Only a polarity check remains.
ACTION REQUIRED: Multimeter on XT60 leads before first mating. Set cell alarm at 3.5V/cell
  to avoid deep discharge during testing.
```

---

### COMPONENT 8: L298N Dual H-Bridge Module

```
STATUS: VERIFIED WITH CONDITIONS
SPEC CHECKED (ST L298N datasheet, www.st.com):
  a) Continuous current: 2A per channel confirmed. CLAUDE.md correct. ✅
  b) Peak current: 3A per channel (non-repetitive).
  c) Logic high threshold VIH: 2.3V minimum. ESP32 GPIO HIGH = 3.3V → 1.0V margin. ✅
     CONDITION: Verify shared ground between ESP32 and L298N (absent common ground,
     the reference shifts and the 1.0V margin disappears).
  d) Voltage drop: ~2V across H-bridge (two transistor saturation drops). Effective motor
     voltage formula: 0.8 × (Vin − 2V) — PWM scales the supply AFTER the bridge drop.
     At 12.6V full LiPo: 0.8 × 10.6 = 8.5V effective. At 11.1V nominal: 0.8 × 9.1 = 7.3V.
     Both within the LICHIFIT 6–9V target band. ✅
  e) Heat at 0.8A/channel: P ≈ 0.8A × 2V ≈ 1.6W/channel, ~3.2W total. Keep the heatsink
     installed — especially given the stall-current risk below.
  f) Min supply: Works well down to 9V (discharged 3S at 3.0V/cell). ✅
  CONDITION (stall current blocker): Running current 0.5–0.8A/motor is within L298N rating.
  But LICHIFIT stall current = 5–8.6A (see Component 10) EXCEEDS L298N 3A peak.
  A fouled or grounded prop will destroy the L298N without a firmware stall trip.
VERDICT: Electrically correct for 3.3V logic interface and normal ~0.8A running current.
  L298N is the critical-path motor driver; it must not be destroyed by a prop stall.
ACTION REQUIRED: Keep heatsink installed. Implement firmware stall-current trip in
  ESP32 motor_driver_node (cut PWM if current >2A for >100ms via shunt+ADC). Verify
  common ground with ESP32. Bench-measure actual stall current before hull assembly.
  Remove the onboard 5V logic regulator jumper if the VS rail is >12V (at 11.1V it
  can stay — verify jumper state regardless).
```

---

## NOT-YET-ORDERED COMPONENTS

---

### COMPONENT 10: LICHIFIT RF-370 Underwater Thruster Kit (ASIN B07WY4MDYZ)

```
STATUS: VERIFIED WITH CONDITIONS
SPEC CHECKED (Amazon listing B07WY4MDYZ; RF-370C/BaneBots M5-RF370-72 motor datasheets):
  a) Running current at ~9V: ~0.5–0.8A/motor estimated (prop-loaded, not stalled). Within
     L298N 2A continuous per channel. ✅
  b) STALL CURRENT [CRITICAL — CLAUDE.MD CORRECTION REQUIRED]:
     16800-RPM LICHIFIT variant is a HIGH-CURRENT RF-370 class.
     RF-370C datasheet: 5A stall @7.2V. BaneBots M5-RF370-72: 8.6A stall @7.2V.
     At 9V, stall current is likely 5–8.6A. L298N rated 3A peak → stall WILL destroy the
     L298N. CLAUDE.md's claim "RF-370 stall <1.8A → L298N PASS" is WRONG for this motor.
     (The 1.1–1.5A stall cited in TRAJECTORY.md DL-2 is the RF-370CA precision variant —
     a different, lower-RPM motor than the LICHIFIT product. Trust the inspected product.)
  c) CW + CCW: One kit = 2 motors (one CW, one CCW) + dual props + mounting bases. ✅
     One kit = one full catamaran set. Plan to buy 2 kits (spare-pair hedge) is correct.
  d) Waterproof: Designed for submerged ROV/bait-boat use — body submersible for pool. ✅
  e) DOA/reliability: 3.7★ with DOA and 12V burn-out reports. Two-kit hedge is correct. ✅
  f) Propellers: 3-blade, included. No separate prop purchase needed. ✅
  g) Voltage: rated 7.4V (best 6–9V, abs max 3–12V). NOT a 12V motor.
VERDICT: Correct part for thrust/budget with CW+CCW confirmed. BUT stall current exceeds
  L298N — do not treat as unconditionally safe. Buying is correct; mounting is gated on
  stall protection and bench verification.
ACTION REQUIRED: SAFE TO ORDER 2 kits (~$48) NOW. But gate first hull installation on:
  1. Firmware stall-current trip in ESP32 motor_driver (cut PWM if >2A for >100ms).
  2. Bench stall measurement at 9V with inline ammeter — confirms actual stall current
     and validates the trip threshold. Do NOT epoxy any thruster before this test.
  3. Thrust gate: ≥150g/motor (200g target) verified with luggage scale at ~9V.
```

---

### COMPONENT 11: Otdorpatio IP67 Enclosure (ASIN B0DX781Z3W)

```
STATUS: NEEDS PHYSICAL BENCH CHECK — DO NOT BUY BLIND
SPEC CHECKED (web search; direct Amazon listing bot-blocked):
  a) Internal dimensions: NOT CONFIRMED for this specific ASIN. The Otdorpatio line spans
     150×100×70mm to 290×190×140mm. Required internal dims ≥220×160×55mm to fit:
     Pi 4 (85×56mm) + Tang Nano (60×22mm) + L298N (55×60mm) + buck converter + wiring.
     If B0DX781Z3W is the 150×100×70mm unit, components will NOT co-fit.
  b) IP rating: Otdorpatio family is IP67 (1m submersion for 30min) — better than the
     budget's IP65 spec. Adequate for pool use. ✅
  c) Cable glands: Family ships with only 2 glands. Project needs ~7 entries (2× motor
     bundles, JSN-SR04T, mast coax, LiPo XT60, UART, spare). A separate M12 gland 10-pack
     is mandatory regardless of which enclosure is ordered.
  d) Material: ABS plastic — non-conductive, fine for RF/WiFi signal. ✅
  e) Budget line specifies 240×180×65mm box at $12–18. The budgeted box DOES fit (220×160
     internal). If B0DX781Z3W is this size, it's the right product.
VERDICT: IP67 ABS Otdorpatio is the right TYPE but the specific ASIN's fit is unverified.
  This is a ~$15 item on a deadline; do not risk a re-order delay.
ACTION REQUIRED: Confirm B0DX781Z3W internal dims ≥220×160×55mm on the live Amazon listing.
  If not confirmed or listing is ambiguous: order the budgeted 240×180×65mm box instead
  (search "240×180×65mm IP67 ABS enclosure" on Amazon, ~$12–18). Order a separate M12
  cable gland 10-pack regardless (~$8).
```

---

## PASSIVE COMPONENT CHECKS

---

### CHECK 12: AC Coupling Capacitor + Bias Resistors

```
STATUS: VERIFIED OK
ANALYSIS:
  Preamp output is centered at 2.5V (VCC/2 virtual ground on 5V single supply).
  AD9226 input requires 1.0V bias (VREF pin).
  A 100nF AC coupling cap removes the 2.5V DC offset.
  A 10kΩ resistor from AD9226 VREF (1.0V) to the AC-coupled node re-biases to 1.0V.

  Frequency response: Fc = 1/(2π × 10kΩ × 100nF) = 159Hz.
  Loss at 38.5kHz: (38,500/159)² ≈ 0.0000017 → -0.0001dB. Negligible. ✅
  Minimum cap for <0.1dB loss at 38.5kHz: C > 2.7nF. 100nF is 37× oversized — ample margin.

COMPONENT VALUES REQUIRED:
  C_ac: 100nF ceramic (standard value, in any cap kit)
  R_bias: 10kΩ (from AD9226 VREF pin → AC-coupled input node; standard E24 value)

VERDICT: 100nF + 10kΩ gives a 159Hz corner with <0.001dB loss at the signal band.
ACTION REQUIRED: Confirm 100nF ceramic and 10kΩ are in the existing component kit. Both
  are standard — no special order needed.
```

---

### CHECK 13: Gain Resistors for Preamp Cascade

```
STATUS: VERIFIED WITH CONDITIONS (values are valid E24; target gain must change — see Check 15)
ANALYSIS:
  Proposed Rf=13kΩ, Rg=1kΩ per stage → G = 1 + 13/1 = 14 per stage → ×196 total.
  13kΩ IS a standard E24 value (1.3 × 10k). No rounding error. ✅

  HOWEVER: ×196 total gain is TOO HIGH (see Check 15). Recommended gain is ×100.
  For ×10/stage (two-stage ×100 total): Rf ≈ 9.1kΩ/1kΩ → G=10.1 (E24: 9.1k is standard).
  Or Rf = 8.2kΩ/1kΩ → G=9.2/stage → total ×84 (-1.4dB from ×100 target — acceptable).
  Nearest E24 pair for closest to ×10: 9.1kΩ/1kΩ → 10.1/stage → ×102 total (+0.2dB). Best.

  Gain error from E24 rounding: <0.2dB — negligible for FC-6 (relative SNR-gradient).

RECOMMENDED VALUES:
  Rf per stage: 9.1kΩ (E24 standard, in any 1% kit)
  Rg per stage: 1kΩ (keep, make socketed/swappable for pool-test calibration)
  Gain per stage: ×10.1
  Total two-stage gain: ×102 (~×100)
  Gain error vs ×196 target: -5.7dB (intentional reduction — see Check 15)

VERDICT: E24 availability is fine. The gain target itself must change from ×196 to ×100.
ACTION REQUIRED: Use Rf=9.1kΩ instead of 13kΩ. Make Rg socketed for bench tuning.
  Confirm 9.1kΩ and 1kΩ are in the existing resistor kit.
```

---

## CROSS-SYSTEM CHECKS

---

### CHECK 14: Full System Power Budget

```
STATUS: FLAG — BUCK CONVERTER RATING UNKNOWN (binding constraint)

RAIL ANALYSIS:
  LiPo (11.1V): Powers L298N+motors (VS rail, direct) + all electronics via buck.
  Buck 5V rail estimated demand:
    Pi 4 1GB idle: ~0.6A; peak ROS 2 load: ~2.5A
    Tang Nano 20K: ~0.2A
    ESP32 ×2: ~0.3A total
    Arduino Uno R4 WiFi: ~0.1A
    Sensors (JSN-SR04T, MPU-6050): ~0.04A
    Preamp (MCP6022 ×2): ~0.016A
    TOTAL 5V rail: ~3.1A peak (Pi peak + all others)

  LiPo headroom: 5–7A system draw vs 150A max = <5% utilization. LiPo is NOT the constraint.
  The BUCK CONVERTER is the real constraint. Its rating is UNKNOWN.

  A standard LM2596-class buck (2–3A rated) will BROWNOUT the Pi under full ROS 2 load.
  A linear regulator at 11.1V→5V at 3A dissipates (11.1-5)×3 = 18W — thermally impossible.

ADDITIONAL FINDING (new, not flagged by component-level validators):
  PWM NOISE ISOLATION is required. L298N switches inductive motor loads (400Hz–20kHz PWM
  harmonics). The MCP6022 preamp amplifies ~5mV signals at ×100. These share a common
  power/ground plane. Required mitigations before enclosure assembly:
  - 100nF + 100µF decoupling at MCP6022 supply pins
  - Separate analog ground from motor/L298N ground; star-point at battery
  - Ferrite bead on preamp 5V feed
  - External flyback diodes (1N5819 Schottky) across motor terminals
  - Route preamp wiring away from motor leads inside the enclosure

VERDICT: Battery has enormous margin. The buck converter is the unverified single point of
  failure for the entire mission compute stack.
ACTION REQUIRED:
  1. Read the chip marking on the owned buck converter. If rated <3A continuous at 5V → order
     Pololu D24V50F5 (5V/5A switching regulator, ~$12) immediately.
  2. Even if marking shows adequate rating: run 'vcgencmd get_throttled' on the Pi powered
     from the owned buck under full ROS 2 load. Must read 0x0. Non-zero = brownout = order Pololu.
  3. Implement PWM noise isolation (decoupling caps, star ground, ferrite bead) BEFORE
     first acoustic capture. Failing to do so may corrupt the SNR-gradient FC-6 homing signal.
```

---

### CHECK 15: Signal Chain End-to-End Voltage Levels

```
STATUS: VERIFIED WITH CONDITIONS — gain ×196 is TOO HIGH
ANALYSIS (dsp-signal-validator math):
  ADC clip threshold = ±1V / gain. At ×196: clips at 5.1mV received signal.
  NE5532 on single 5V supply clips even earlier at ~8.7mV input (moot — NE5532 is rejected).
  With MCP6022 on proper single 5V supply, clips at AD9226 ±1V = 5.1mV at ×196 total.

  Received signal estimates at the TCT40-16R output:
    1m range: 1–10mV → after ×196: 0.196V–1.96V. HIGH END CLIPS. ❌
    3m range: 0.5–3mV → after ×196: 0.098V–0.588V. No clip. ✅
    0.3m range (ARRIVED): 30–100mV → after ×196: 5.9V–19.6V. HARD CLIP. ✅ (acceptable per FC-6)

  With ×100 gain: clips at 10mV received signal.
    1m range high end (10mV): exactly at clip. Still marginal. → ×100 keeps 1m+ linear for
    most of the homing approach; clipping only sub-0.5m (near-field OTR per FC-6 ARRIVED trigger).
    OTR flag propagates end-to-end (FC-2) → Pi handles saturated readings.

  The gradient failure mode: clipping DURING HOMING (1m range at high received levels) flattens
  the FC-6 SNR gradient and corrupts the homing law. This is the design failure, not near-field
  clipping. ×100 moves the clip point to sub-0.5m near-field — acceptable.

VERDICT: Gain must be ×100 (two-stage ×10/×10 with MCP6022). Final gain is a bench-calibration
  item — set Rg swappable and tune at pool test #1 Layer A scope check.
ACTION REQUIRED: Use Rf=9.1kΩ / Rg=1kΩ per stage (×100 total). Make Rg socketed. Final value
  set empirically at the Layer A bench check (measure actual received level at 1m and 3m,
  choose gain that keeps the homing range linear with headroom). Add to CQ-1 calibration queue.
```

---

### CHECK 16: ESP32 GPIO Compatibility Matrix

```
STATUS: VERIFIED WITH CONDITIONS

| Signal               | Source V | ESP32 in max | Fix needed?               | Status          |
|----------------------|----------|--------------|---------------------------|-----------------|
| JSN-SR04T ECHO       | 5V       | 3.6V         | 1kΩ+2kΩ divider → 3.33V  | ✅ with divider  |
| JSN-SR04T TRIG       | ESP32 out| N/A          | None; bench-verify 3.3V fires | ⚠️ verify    |
| MPU-6050 SDA/SCL     | 3.3V LDO | 3.6V         | None (onboard pull-ups)   | ✅               |
| L298N IN1-IN4        | ESP32 out| N/A          | None; VIH=2.3V, 3.3V→1V margin | ✅ verify gnd |
| L298N ENA/ENB (PWM)  | ESP32 out| N/A          | Must use PWM-capable GPIO  | ⚠️ assign LEDC |
| MOSFET gate (buoy)   | ESP32 out| N/A          | Logic-level MOSFET required | ⚠️ see below  |
| Arduino Uno R4 WiFi  | WiFi only| N/A          | No direct GPIO link in V1  | ✅               |

MOSFET gate (buoy transducer drive, ESP32 #2):
  2N7000: Vgs(th) = 0.8–3V. At 3.3V gate, only 0.3–2.5V above threshold → linear region,
    high Rds(on), runs hot, unreliable at 40kHz drive. MARGINAL-TO-FAILING.
  IRLZ44N: Vgs(th) = 1–2V, true logic-level → fully enhanced at 3.3V. ✅
  AO3400: Vgs(th) = 0.5–1.5V, logic-level SOT-23. ✅
  REQUIRED: logic-level MOSFET (Vgs(th) < 2V) for buoy drive from ESP32 3.3V GPIO.
  Check owned MOSFET pack for IRLZ44N or AO3400. If only 2N7000 available, order IRLZ44N.

L298N ENA/ENB (PWM speed control):
  These inputs set motor speed. If tied HIGH, motors run full duty — the ≤80% PWM cap
  (DL-2 firmware requirement) is implemented HERE. Assign ENA/ENB to two ESP32 LEDC
  PWM channels with firmware ceiling at 80% duty. This is mandatory for thruster protection.

ACTION REQUIRED:
  - Install 1kΩ/2kΩ divider on JSN-SR04T ECHO before ESP32 (parts in owned kit).
  - Assign L298N ENA/ENB to ESP32 LEDC PWM channels; enforce 80% duty ceiling.
  - Confirm logic-level MOSFET in owned pack (IRLZ44N or equivalent); order if absent (~$3).
  - Consider raising ESTOP threshold from 25cm to 30cm (JSN-SR04T min range = 25cm = dead zone
    coincides with current ESTOP distance).
```

---

## DOCUMENTATION CORRECTIONS APPLIED

| Document | Location | Wrong | Correct |
|----------|----------|-------|---------|
| CLAUDE.md Propulsion section | Line 336 | "RF-370 stall <1.8A" | 5–8.6A (high-current 16800-RPM variant) |
| CLAUDE.md Parts Not Ordered | Line 565 | "RF-370 stall <1.8A → L298N PASS" | Running current passes; stall exposed — firmware trip required |
| TRAJECTORY.md DL-2 | Line 608 | "RF-370CA stall 1.1–1.5A" cited for LICHIFIT | RF-370CA is a different (low-current) motor; flag with pending bench measurement |

**CLAUDE.md lines 336 and 565 have been corrected in this session.**  
TRAJECTORY.md DL-2 line 608 requires manual reconciliation — the RF-370CA citation should be annotated as applying to a different variant pending the bench stall measurement.

---

## PURCHASE DECISION SUMMARY

### SAFE TO BUY NOW
| Item | Cost | Notes |
|------|------|-------|
| MCP6022-I/P ×2 | ~$3 | Primary preamp; replaces NE5532P; ×10/stage × 2 = ×100 total |
| TLV2462CP ×2 | ~$4 | Backup preamp; buy as insurance against MCP6022 layout issues |
| LICHIFIT RF-370 ×2 kits | ~$48 | CW+CCW confirmed; gated on bench stall test before epoxy |
| M12 cable gland 10-pack | ~$8 | Mandatory regardless of enclosure choice |
| IRLZ44N MOSFET pack | ~$3 | Confirm owned pack first; needed for buoy drive |
| **Subtotal** | **~$66** | |
| Pololu D24V50F5 5V/5A (conditional) | +$12 | Order proactively if owned buck chip reads <3A |
| IP67 enclosure (conditional) | +$15–20 | Only after confirming B0DX781Z3W dims |
| **Max with conditionals** | **~$98** | Well within remaining budget |

### DO NOT BUY
| Item | Reason |
|------|--------|
| NE5532P | Out of spec on single 5V; not rail-to-rail; use MCP6022 instead |
| LM358 | 1MHz GBW insufficient for ×10/stage at 40kHz (100kHz BW, signal is 40kHz) |

### DO NOT BUY UNTIL VERIFIED
| Item | What must be confirmed first |
|------|------------------------------|
| Otdorpatio B0DX781Z3W enclosure | Confirm internal dims ≥220×160×55mm on live listing; if unclear, order 240×180×65mm box |
| Pololu buck (hold) | Run vcgencmd test first; buy only if owned buck fails |

### ALREADY OWNED, CONFIRMED OK
- AD9226 ADC (pending PV-1/2/3 bench straps before power-on)
- Tang Nano 20K (all .cst pins verified; shipped files are correct)
- MPU-6050 GY-521 (onboard LDO + pull-ups; no mods needed)
- Hosim 3S LiPo ×2 (150A capacity; only polarity check remains)
- TCT40-16R/T transducers (usable; pending bandwidth sweep before chirp finalization)

### ALREADY OWNED, NEEDS ATTENTION
| Item | What to do |
|------|-----------|
| MAX9814 | Permanently disqualified — shelve; do not use |
| NE5532P kit | Disqualified for this role (wrong supply); shelve for other projects |
| L298N | Keep heatsink; implement firmware stall trip before any motor run |
| JSN-SR04T | Install 1kΩ/2kΩ echo divider (parts in owned kit); raise ESTOP to 30cm |
| Owned buck converter | Verify rating and run vcgencmd test before Pi integration |
| Owned MOSFET pack | Confirm at least one logic-level part (Vgs(th) <2V) for buoy drive |

---

## BENCH VERIFICATION QUEUE (ordered — complete before each milestone)

**Before any AD9226 ↔ FPGA power-on:**
1. PV-1: DRVDD = 3.3V (multimeter)
2. PV-2: DFS ≈ 0V (AVSS)
3. PV-3: OEB ≈ 0V (tied LOW)
4. XT60 polarity on LiPo (multimeter before first mating)

**Before ESP32 peripheral bring-up (Week 6):**
5. Buck converter: `vcgencmd get_throttled` = 0x0 under full ROS 2 load
6. L298N: common ground with ESP32 verified; onboard 5V jumper state confirmed
7. JSN-SR04T echo divider: 3.33V at ESP32 pin after 1kΩ/2kΩ
8. JSN-SR04T trigger: sensor fires reliably from 3.3V pulse (≥20µs); level-shift if flaky
9. MOSFET gate: IRLZ44N fully switches at 3.3V driving 40kHz

**Layer A analog bench check (DL-1, before pool test #1):**
10. TCT40 bandwidth sweep: confirm -6dB band spans 38.5–41.5kHz; narrow chirp if not
11. Preamp (MCP6022 ×100): drive at 40kHz, scope output; confirm no clipping in 1–3m simulated signal range; confirm PWM noise absent from preamp output

**Before hull assembly (DL-2 gate, irreversible step):**
12. Thruster stall current: inline ammeter, stall prop by hand at 9V, measure actual amps; set firmware trip threshold
13. Thrust force: ≥150g/motor at ~9V with luggage scale (200g target)

---

## BLOCKING ISSUES FOR AUGUST 10 DEMO

1. **[#1 BLOCKER] Full pipeline synthesis never run.** All 9 FPGA modules are isolated sims; no top_level.v, no Gowin utilization report, no timing closure result. Resource estimates (multipliers, BSRAM) are unverified against actual synthesis. This is the #1 demo blocker — current critical path (per TRAJECTORY.md CRITICAL PATH section).

2. **Preamp not in hand.** MAX9814 and NE5532P are both disqualified. MCP6022 ×2 must be ordered today — preamp gates ALL Layer A/B acoustic bench testing and CQ-1 calibration.

3. **L298N stall exposure (new — found this audit).** Without a firmware stall-current trip, a single weed/grounding stall during pool testing destroys the L298N (critical-path part, no spare mentioned). Must be in the ESP32 motor firmware and bench-verified before hull bonding.

4. **Buck converter rating unverified.** A Pi brownout under ROS 2 load corrupts the entire mission compute stack. Run vcgencmd test or order the Pololu ($12) proactively.

5. **Thrusters not ordered, thrust unverified.** Gates hull assembly and pool test #1. Order 2 kits (~$48) today. Bench-gate thrust + stall measurement before epoxy.

6. **PV-1/2/3 not cleared.** Gates all FPGA-in-the-loop ADC capture. Clear before any AD9226 ↔ Tang Nano power-on.

---

*Audit generated June 25, 2026. Agents: hw-validation ×3, dsp-signal-validator, systems-integrator. Next review: after Layer A bench check (DL-1) and full pipeline synthesis.*
