---
name: project-ranging-architecture
description: V1 ranging is SNR-gradient homing, not ToF range — buoy/vehicle share no time reference (FC-5/FC-6, June 2026)
metadata:
  type: project
---

The matched filter peak is a correlation LAG + MAGNITUDE, NOT absolute range.

**Why:** Buoys (ESP32 #2) transmit LFM chirps autonomously/continuously. The
vehicle has no shared time reference with the buoy (GPS-denied, no radio sync,
no wired link, no transponder echo). So `T_transmit` is unknown in the vehicle's
time base → neither one-way nor two-way ToF is measurable. FC-3's `Range = ... ÷ 2`
round-trip equation is physically impossible; its 421,875 Hz sample rate is still
valid for lag-to-time diagnostics.

**How to apply (locked as FC-5/FC-6 in docs/TRAJECTORY.md, June 15 2026):**
- `peak_detector.v` outputs `corr_peak`(16b) + `snr`(8b) as PRIMARY navigation
  signal (SNR monotonic with proximity). `peak_lag` kept diagnostic-only + as the
  V2 TDOA dual-receiver bearing hook (difference of two lags cancels the unknown
  common clock offset — why TDOA works without sync).
- FPGA pipeline is UNCHANGED structurally — build matched filter + peak detector
  exactly as planned (FC-1 integer scale, FC-2 OTR, 800-sample BSRAM). Only output
  meaning/labeling changes. Do NOT redesign the DSP.
- `acoustic_homing_node`: SCAN by SNR-vs-heading, HOME by gradient ascent on SNR
  (not PID-on-range), ARRIVED = SNR plateau/saturation for 3 readings (not
  range<0.4m). Lock threshold must sit above the ~20-30% pool-wall multipath floor.
- ROS topic `/acoustic/range_m` → renamed `/acoustic/corr_snr`. 8-byte UART packet
  format UNCHANGED; only Pi-side interpretation of the range_cm bytes changes.
- SNR-vs-distance thresholds (ACQUIRING lock, ARRIVED plateau) need empirical pool
  calibration — cannot be set in simulation.

**Cross-domain lesson:** A DSP output's *physical meaning* can depend on a
system-level fact (clock synchronization) that neither hw-validation nor
dsp-signal-validator owns — exactly the gap systems-integrator exists to catch.
See [[project-pipeline-baselines]].
