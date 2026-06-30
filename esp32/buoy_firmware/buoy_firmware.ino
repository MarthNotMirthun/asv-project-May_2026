// ============================================================
// Module:      buoy_firmware.ino
// Description: ASV acoustic beacon (buoy) firmware. Standalone
//              LFM chirp generator - no micro-ROS, no sensors.
//              Drives 3x TCT40-16T via IRLZ44N MOSFETs at 120deg
//              spacing for 360deg coverage. Single codebase for
//              both buoys; sweep direction selected at compile
//              time via BUOY_ID (code-division beacon ID, FC-7).
// Target:      ESP32 #2 (buoy controller), Arduino framework
// Pipeline:    THIS -> IRLZ44N gates -> 3x TCT40-16T -> air ->
//              TCT40-16R (vehicle) -> AD9226 -> FPGA matched filter
// Date:        2026-06-30
// ============================================================
//
// CLAUDE.md / TRAJECTORY.md FC-7 contract:
//  - Buoy 1: UP-sweep LFM, 38.5 -> 41.5 kHz
//  - Buoy 2: DOWN-sweep LFM, 41.5 -> 38.5 kHz
//  - Both buoys share the SAME 38.5-41.5kHz transducer passband;
//    beacon ID is by sweep DIRECTION, not frequency band.
//  - Chirp duration T = 5.0ms, repeat at 20Hz (50ms period).
//  - 2109 reference samples @ 421,875Hz on the receive side is
//    unaffected by transmit-side implementation here.
//
// Build instructions:
//  Set BUOY_ID below to 1 (this board drives Buoy 1, UP-sweep) or
//  2 (this board drives Buoy 2, DOWN-sweep) BEFORE flashing each
//  physical buoy board. Each buoy is a separate ESP32 board running
//  this same file with only BUOY_ID changed.
//
#define BUOY_ID 1   // <-- SET TO 1 or 2 BEFORE FLASHING (see above)

#if (BUOY_ID != 1) && (BUOY_ID != 2)
#error "BUOY_ID must be defined as 1 or 2"
#endif

#include "chirp_generator.h"

// Buoy 1 = UP-sweep (38.5->41.5kHz), Buoy 2 = DOWN-sweep (41.5->38.5kHz). (FC-7)
#define BUOY_UP_SWEEP (BUOY_ID == 1)

uint32_t t_last_chirp = 0;

void setup() {
  chirp_setup();
  Serial.begin(115200);
  Serial.printf("ASV buoy firmware - BUOY_ID=%d (%s-sweep)\n",
                BUOY_ID, BUOY_UP_SWEEP ? "UP" : "DOWN");

  // Visual confirmation of compiled BUOY_ID in the field (no serial needed).
  chirp_blink_id(BUOY_ID);

  t_last_chirp = millis();
}

void loop() {
  uint32_t now = millis();

  // 20Hz chirp rate (CHIRP_PERIOD_MS = 50ms). The 5ms chirp itself is
  // blocking (chirp_play); no other duties run on this standalone board,
  // so blocking timing is acceptable and keeps the sweep ramp jitter-free.
  if ((now - t_last_chirp) >= CHIRP_PERIOD_MS) {
    t_last_chirp = now;
    chirp_play(BUOY_UP_SWEEP);
  }
}
