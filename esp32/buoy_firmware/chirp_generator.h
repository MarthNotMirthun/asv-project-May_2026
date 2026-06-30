// ============================================================
// Module:      chirp_generator.h
// Description: LFM (linear frequency modulated) chirp generator
//              for the ASV acoustic beacons. Drives 3x TCT40-16T
//              transducers (120 deg spacing) via IRLZ44N MOSFET
//              gate drive, using ESP32 LEDC hardware PWM stepped
//              through a discrete frequency ramp to approximate
//              the analog LFM sweep with a square wave.
// Target:      ESP32 #2 (buoy), standalone (no micro-ROS)
// Reference:   CLAUDE.md FC-7 (TRAJECTORY.md) - code-division beacon
//              ID by sweep direction, both buoys share the same
//              38.5-41.5kHz TCT40-16T transducer passband.
//              DL-1 addendum - square-wave digital drive validated
//              for this transducer; no DAC/analog synth needed.
// Date:        2026-06-30
// ============================================================
//
// IRLZ44N gate drive circuit (per transducer channel, x3):
//   ESP32 GPIO --[150-220ohm series resistor]--> IRLZ44N Gate
//   IRLZ44N Gate --[100k pulldown to GND]        (holds gate low
//                                                  if GPIO floats
//                                                  during boot)
//   IRLZ44N Drain -> TCT40-16T (+) ; TCT40-16T (-) -> TX supply rail
//   1N4148 clamp diode: cathode to TX supply rail, anode to Drain
//                        (clamps inductive/piezo flyback above rail)
//   IRLZ44N Source -> GND (common with ESP32 GND)
//   IRLZ44N Vgs(th) = 1-2V -> fully enhanced at 3.3V ESP32 GPIO (CLAUDE.md)
//
// GPIO pin assignment (3 gates per buoy board):
//   TX1_PIN = GPIO25  (LEDC ch 0, all 3 pins share this channel ->
//   TX2_PIN = GPIO26   identical waveform out of all 3 gates, since
//   TX3_PIN = GPIO27   the 3 transducers are driven in unison for
//                       360 deg coverage, not individually modulated)
//   STATUS_LED_PIN = GPIO2 (onboard LED; blinks BUOY_ID at boot,
//                            toggles once per chirp for field debug)
//
// TX supply rail: confirm at Layer A bench check (DL-1 addendum used
// 5V bench drive for the FPGA TX validation; use the same nominal 5V
// for the buoy MOSFET drain rail unless bench testing says otherwise).
//
#ifndef CHIRP_GENERATOR_H
#define CHIRP_GENERATOR_H

#include <Arduino.h>

// ---- Pin map ----
#define CHIRP_TX1_PIN        25
#define CHIRP_TX2_PIN        26
#define CHIRP_TX3_PIN        27
#define CHIRP_STATUS_LED_PIN 2

// ---- LEDC configuration ----
#define CHIRP_LEDC_CHANNEL   0
#define CHIRP_LEDC_RES_BITS  8     // ledcWriteTone manages duty internally

// ---- Chirp spec (CLAUDE.md FC-7, both buoys share this band) ----
#define CHIRP_F_LOW_HZ    38500.0f
#define CHIRP_F_HIGH_HZ   41500.0f
#define CHIRP_DURATION_MS 5        // T = 5.0ms (FC-7)
#define CHIRP_PERIOD_MS   50       // 20Hz repeat rate (FC-7)
#define CHIRP_N_STEPS     50       // 100us/step over 5ms - discrete approx. of LFM ramp
#define CHIRP_STEP_US     (uint32_t)((CHIRP_DURATION_MS * 1000UL) / CHIRP_N_STEPS)

inline void chirp_setup() {
  pinMode(CHIRP_STATUS_LED_PIN, OUTPUT);
  digitalWrite(CHIRP_STATUS_LED_PIN, LOW);

  // All 3 TX gates share one LEDC channel -> identical waveform on
  // all 3 transducers (they are driven in unison, not phased).
  ledcSetup(CHIRP_LEDC_CHANNEL, (uint32_t)CHIRP_F_LOW_HZ, CHIRP_LEDC_RES_BITS);
  ledcAttachPin(CHIRP_TX1_PIN, CHIRP_LEDC_CHANNEL);
  ledcAttachPin(CHIRP_TX2_PIN, CHIRP_LEDC_CHANNEL);
  ledcAttachPin(CHIRP_TX3_PIN, CHIRP_LEDC_CHANNEL);
  ledcWriteTone(CHIRP_LEDC_CHANNEL, 0);  // silent until first chirp
}

// Blocking: steps the LEDC tone frequency through a discrete linear
// ramp from f_start to f_stop over CHIRP_DURATION_MS, then silences
// the output. up_sweep=true -> f_start=LOW, f_stop=HIGH (Buoy 1);
// up_sweep=false -> f_start=HIGH, f_stop=LOW (Buoy 2), per FC-7.
inline void chirp_play(bool up_sweep) {
  float f_start = up_sweep ? CHIRP_F_LOW_HZ  : CHIRP_F_HIGH_HZ;
  float f_stop  = up_sweep ? CHIRP_F_HIGH_HZ : CHIRP_F_LOW_HZ;

  for (int i = 0; i < CHIRP_N_STEPS; i++) {
    float frac = (float)i / (float)(CHIRP_N_STEPS - 1);
    float f = f_start + (f_stop - f_start) * frac;
    ledcWriteTone(CHIRP_LEDC_CHANNEL, f);
    delayMicroseconds(CHIRP_STEP_US);
  }
  ledcWriteTone(CHIRP_LEDC_CHANNEL, 0);  // silence between chirps

  digitalWrite(CHIRP_STATUS_LED_PIN, !digitalRead(CHIRP_STATUS_LED_PIN));
}

// Boot-time visual ID: blink the status LED `id` times so the buoy's
// compiled BUOY_ID can be confirmed in the field without a serial console.
inline void chirp_blink_id(int id) {
  for (int i = 0; i < id; i++) {
    digitalWrite(CHIRP_STATUS_LED_PIN, HIGH);
    delay(200);
    digitalWrite(CHIRP_STATUS_LED_PIN, LOW);
    delay(200);
  }
  delay(500);
}

#endif // CHIRP_GENERATOR_H
