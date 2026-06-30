// ============================================================
// Module:      sonar_driver.h
// Description: JSN-SR04T waterproof ultrasonic range driver +
//              collision ESTOP latch. Trigger pulse / echo timing,
//              cm conversion, and a 30cm ESTOP with 1-second clear
//              hysteresis above 30cm before release.
// Target:      ESP32 #1 (vehicle), micro-ROS, Arduino framework
// Pipeline:    JSN-SR04T (trig/echo) -> THIS -> /collision/range_cm (10Hz)
//                                       -> ESTOP signal to motor_control
// Author:      fpga-verilog-engineer agent (firmware task)
// Date:        2026-06-29
// ============================================================
//
// CLAUDE.md hardware contract sources:
//  - JSN-SR04T echo through 1k+2k divider before ESP32 GPIO (5V->3.3V).
//  - Trigger: any free GPIO.
//  - Publishes /collision/range_cm at 10Hz.
//  - ESTOP at 30cm (NOT 25cm — JSN-SR04T blind zone is 25cm; 25cm
//    threshold risks missing obstacles inside the sensor dead zone).
//  - When ESTOP triggered: zero motor PWM, do NOT resume until range
//    > 30cm for 1 full second.
//  - Trigger pulse: 10us HIGH; distance_cm = echo_us / 58.0.
//
#ifndef SONAR_DRIVER_H
#define SONAR_DRIVER_H

#include <Arduino.h>

// ---- Pins ----
#define SONAR_TRIG_PIN   13   // any free GPIO
#define SONAR_ECHO_PIN   34   // input-only GPIO, fed via 1k+2k divider (5V->3.3V)

// ---- Timing constants ----
#define SONAR_TRIG_US        10      // CLAUDE.md: 10us HIGH trigger pulse
#define SONAR_US_PER_CM      58.0f   // CLAUDE.md: distance_cm = echo_us / 58.0
#define SONAR_ECHO_TIMEOUT_US 30000  // ~5m max range -> timeout, treat as "no echo"

// ---- ESTOP thresholds (CLAUDE.md) ----
#define SONAR_ESTOP_CM        30.0f  // ESTOP at 30cm (NOT 25cm — blind-zone margin)
#define SONAR_CLEAR_HOLD_MS   1000   // must stay > 30cm for 1 full second to clear

struct SonarState {
  float    range_cm;        // last valid measurement
  bool     estop;           // latched ESTOP state
  uint32_t clear_start_ms;  // when range first went clear (>30cm); 0 = not clear
  bool     valid;
};

static SonarState g_sonar;

inline void sonar_setup() {
  pinMode(SONAR_TRIG_PIN, OUTPUT);
  pinMode(SONAR_ECHO_PIN, INPUT);
  digitalWrite(SONAR_TRIG_PIN, LOW);

  g_sonar.range_cm = 0.0f;
  g_sonar.estop = false;
  g_sonar.clear_start_ms = 0;
  g_sonar.valid = false;
}

// Fire one ping, measure echo, return distance in cm (-1 on timeout).
inline float sonar_measure() {
  // 10us trigger pulse.
  digitalWrite(SONAR_TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(SONAR_TRIG_PIN, HIGH);
  delayMicroseconds(SONAR_TRIG_US);
  digitalWrite(SONAR_TRIG_PIN, LOW);

  // pulseIn returns echo HIGH duration in us (0 on timeout).
  unsigned long echo_us = pulseIn(SONAR_ECHO_PIN, HIGH, SONAR_ECHO_TIMEOUT_US);
  if (echo_us == 0) {
    return -1.0f;  // no echo within range window
  }
  return (float)echo_us / SONAR_US_PER_CM;
}

// Update ESTOP latch using the latest measurement. Call at 10Hz.
// Returns the current ESTOP state.
inline bool sonar_update() {
  float d = sonar_measure();
  uint32_t now = millis();

  if (d < 0.0f) {
    // No echo: open water or out of range. Treat as clear distance.
    // (JSN-SR04T returns no echo when nothing is within range.)
    d = SONAR_ESTOP_CM + 100.0f;
    g_sonar.valid = false;
  } else {
    g_sonar.range_cm = d;
    g_sonar.valid = true;
  }

  if (d <= SONAR_ESTOP_CM) {
    // Obstacle within ESTOP range — latch and reset clear timer.
    g_sonar.estop = true;
    g_sonar.clear_start_ms = 0;
  } else {
    // Range is clear. Require sustained clearance before releasing ESTOP.
    if (g_sonar.estop) {
      if (g_sonar.clear_start_ms == 0) {
        g_sonar.clear_start_ms = now;  // start the 1-second clear window
      } else if ((now - g_sonar.clear_start_ms) >= SONAR_CLEAR_HOLD_MS) {
        g_sonar.estop = false;         // sustained clear -> release ESTOP
        g_sonar.clear_start_ms = 0;
      }
    }
  }
  return g_sonar.estop;
}

inline float sonar_get_range_cm() { return g_sonar.range_cm; }
inline bool  sonar_get_estop()    { return g_sonar.estop; }
inline bool  sonar_get_valid()    { return g_sonar.valid; }

#endif // SONAR_DRIVER_H
