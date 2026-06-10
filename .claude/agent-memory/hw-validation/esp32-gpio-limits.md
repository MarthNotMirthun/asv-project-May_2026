---
name: esp32-gpio-limits
description: ESP32 GPIO is NOT 5V tolerant — abs max input is VDD+0.3V (3.6V at VDD=3.3V). Any 5V sensor output into ESP32 needs level shifting.
metadata:
  type: project
---

ESP32 (Espressif) GPIO input electrical limits:
- VIH spec referenced to VDD; max applied pin voltage = VDD + 0.3V = 3.6V at VDD=3.3V
- NOT 5V tolerant. 5V directly on a GPIO risks damage to the pad/ESD diode.

**How to apply:** Any 5V-powered peripheral driving a signal INTO the ESP32 needs level shifting. Confirmed case: JSN-SR04T ECHO pin swings to 5V → needs divider or BSS138 shifter. TRIGGER pin (ESP32 driving OUT to 5V sensor) is usually fine since JSN-SR04T input threshold is met by 3.3V, but verify per sensor.

JSN-SR04T ECHO divider: R1=1k (from ECHO), R2=2k (to GND), tap to GPIO → ~3.3V. Acceptable for the slow (~ms) echo pulse. Use BSS138 if edge speed ever matters.

Source: espressif.com/sites/default/files/documentation/esp32_datasheet_en.pdf
