---
name: fir-selectivity-limit
description: 32-tap FIR cannot reach 30dB adjacent-band rejection at fs=421.875kHz / 8kHz band separation — physical limit
metadata:
  type: project
---

The dual FIR banks (34-38kHz / 42-46kHz, centers 36/44kHz) at fs=421875 Hz with 32 taps CANNOT achieve the spec'd >30dB adjacent-band rejection. Measured ~0.4-2.5dB only, regardless of window (Hamming, Blackman) or design bandwidth.

**Why:** At fs=421.875kHz the 36kHz and 44kHz centers are only ~0.019 apart in normalized frequency, while a 32-tap FIR's frequency resolution is ~1/32 = 0.031. The filter main lobe is wider than the band gap — no 32-tap windowed-sinc design can resolve the two bands. The fs / 32-taps / 30dB-rejection spec triad is internally inconsistent. The CIC oversamples (422kSPS) far above Nyquist for a 46kHz signal, which is what makes the bands so close in normalized terms.

**How to apply:** The FIR banks provide only ~2-3dB pre-selection + DC/out-of-band roll-off; the matched filter correlator downstream provides the REAL selectivity (the consolidated fix list itself acknowledges this). When building/reviewing FIR or matched-filter work, do NOT assert an absolute 30dB FIR rejection in testbenches — assert RELATIVE selectivity (passband response > adjacent-band response). If true 30dB FIR rejection is ever required, the levers are: many more taps (100+), or decimate harder so the bands sit at higher normalized frequency. Both conflict with locked decisions, so flag to the user rather than silently changing. See [[verified-modules]].
