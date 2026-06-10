---
name: l298n-logic-inputs
description: L298N logic inputs (IN1-4, ENA/ENB) have VIH min 2.3V — a 3.3V ESP32 GPIO drives them reliably. L298N needs its own Vss 5V logic supply separate from motor Vs.
metadata:
  type: project
---

L298N (ST L298) logic input spec:
- VIH (high-level input) = 2.3V min to Vss. ESP32 VOH ~3.0-3.3V clears 2.3V with ~0.7-1.0V margin → SAFE direct drive.
- VIL (low-level) = 1.5V max typical.
- Vss = logic supply, range 4.5-7V, normally 5V. Must be provided SEPARATELY from Vs (motor supply, up to 46V / 12V LiPo here).

**Why:** L298N is TTL-threshold (2.3V VIH), so 3.3V logic drives inputs directly — no level shift needed despite it being a "5V logic" part. Common confusion. The gotcha is Vss: many L298N modules have a 5V onboard regulator (jumper enabled) that derives Vss from Vs when Vs <= 12V. With 3S LiPo at 12.6V full charge this is borderline — the 7805 regulator dropout/heat margin is thin. Consider feeding Vss=5V externally or removing the 5V jumper and supplying logic 5V from a dedicated buck.

L298N inputs draw low current; ESP32 IOH is adequate. Decouple Vss aggressively (0.1uF + bulk) — L298N is a heavy EMI source, flyback/snubber diodes mandatory on motor outputs.

Source: st.com/resource/en/datasheet/l298.pdf
