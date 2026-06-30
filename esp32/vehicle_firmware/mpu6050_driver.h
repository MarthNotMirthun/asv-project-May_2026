// ============================================================
// Module:      mpu6050_driver.h
// Description: MPU-6050 IMU driver over I2C. Direct register reads
//              (no external lib dependency). Fills a sensor_msgs/Imu
//              with gyro (angular_velocity) + accel (linear_acceleration).
//              Covariances set to -1 (unknown) for bring-up.
// Target:      ESP32 #1 (vehicle), micro-ROS, Arduino framework
// Pipeline:    MPU-6050 (I2C) -> THIS -> /imu/data (Imu, 100Hz)
// Author:      fpga-verilog-engineer agent (firmware task)
// Date:        2026-06-29
// ============================================================
//
// CLAUDE.md hardware contract sources:
//  - MPU-6050 on I2C: GPIO21 SDA, GPIO22 SCL.
//  - Publishes /imu/data at 100Hz.
//  - Covariances set to -1 (unknown) for bring-up.
//
#ifndef MPU6050_DRIVER_H
#define MPU6050_DRIVER_H

#include <Arduino.h>
#include <Wire.h>

// ---- I2C pins (CLAUDE.md: GPIO21 SDA, GPIO22 SCL) ----
#define MPU_I2C_SDA   21
#define MPU_I2C_SCL   22
#define MPU_I2C_FREQ  400000   // 400kHz fast-mode I2C

// ---- MPU-6050 register map ----
#define MPU_ADDR          0x68  // AD0 low
#define MPU_REG_PWR_MGMT1 0x6B
#define MPU_REG_SMPLRT    0x19
#define MPU_REG_CONFIG    0x1A
#define MPU_REG_GYRO_CFG  0x1B
#define MPU_REG_ACCEL_CFG 0x1C
#define MPU_REG_ACCEL_OUT 0x3B  // ACCEL_XOUT_H .. GYRO_ZOUT_L = 14 bytes
#define MPU_REG_WHOAMI    0x75

// ---- Full-scale conversion constants ----
// Accel FS = +/-2g  -> 16384 LSB/g.  g = 9.80665 m/s^2.
// Gyro  FS = +/-250 dps -> 131 LSB/(deg/s). deg->rad = pi/180.
#define MPU_ACCEL_LSB_PER_G   16384.0f
#define MPU_GRAVITY           9.80665f
#define MPU_GYRO_LSB_PER_DPS  131.0f
#define MPU_DEG2RAD           0.017453293f

struct ImuSample {
  float ax, ay, az;   // linear acceleration (m/s^2)
  float gx, gy, gz;   // angular velocity (rad/s)
  bool  valid;
};

inline void mpu_write_reg(uint8_t reg, uint8_t val) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

inline uint8_t mpu_read_reg(uint8_t reg) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);   // repeated start
  Wire.requestFrom(MPU_ADDR, (uint8_t)1);
  if (Wire.available()) return Wire.read();
  return 0;
}

// Returns true if WHO_AM_I responds as expected.
inline bool mpu_setup() {
  Wire.begin(MPU_I2C_SDA, MPU_I2C_SCL, MPU_I2C_FREQ);
  delay(50);

  // Wake from sleep (PWR_MGMT_1 = 0), select PLL X-gyro clock.
  mpu_write_reg(MPU_REG_PWR_MGMT1, 0x01);
  delay(10);

  // Sample rate divider: 1kHz/(1+7) = 125Hz internal; we poll at 100Hz.
  mpu_write_reg(MPU_REG_SMPLRT, 0x07);
  // DLPF config ~44Hz (accel) / 42Hz (gyro) — reduces motor vibration noise.
  mpu_write_reg(MPU_REG_CONFIG, 0x03);
  // Gyro FS = +/-250 dps (0x00).
  mpu_write_reg(MPU_REG_GYRO_CFG, 0x00);
  // Accel FS = +/-2g (0x00).
  mpu_write_reg(MPU_REG_ACCEL_CFG, 0x00);
  delay(10);

  uint8_t who = mpu_read_reg(MPU_REG_WHOAMI);
  // MPU-6050 returns 0x68; some clones return 0x70/0x72 — accept non-zero.
  return (who != 0x00 && who != 0xFF);
}

// Burst-read 14 bytes and convert to SI units.
inline ImuSample mpu_read() {
  ImuSample s;
  s.valid = false;

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(MPU_REG_ACCEL_OUT);
  Wire.endTransmission(false);
  uint8_t n = Wire.requestFrom(MPU_ADDR, (uint8_t)14);
  if (n < 14) {
    s.ax = s.ay = s.az = 0.0f;
    s.gx = s.gy = s.gz = 0.0f;
    return s;
  }

  int16_t raw_ax = (Wire.read() << 8) | Wire.read();
  int16_t raw_ay = (Wire.read() << 8) | Wire.read();
  int16_t raw_az = (Wire.read() << 8) | Wire.read();
  int16_t raw_t  = (Wire.read() << 8) | Wire.read();  // temperature (unused)
  (void)raw_t;
  int16_t raw_gx = (Wire.read() << 8) | Wire.read();
  int16_t raw_gy = (Wire.read() << 8) | Wire.read();
  int16_t raw_gz = (Wire.read() << 8) | Wire.read();

  s.ax = ((float)raw_ax / MPU_ACCEL_LSB_PER_G) * MPU_GRAVITY;
  s.ay = ((float)raw_ay / MPU_ACCEL_LSB_PER_G) * MPU_GRAVITY;
  s.az = ((float)raw_az / MPU_ACCEL_LSB_PER_G) * MPU_GRAVITY;
  s.gx = ((float)raw_gx / MPU_GYRO_LSB_PER_DPS) * MPU_DEG2RAD;
  s.gy = ((float)raw_gy / MPU_GYRO_LSB_PER_DPS) * MPU_DEG2RAD;
  s.gz = ((float)raw_gz / MPU_GYRO_LSB_PER_DPS) * MPU_DEG2RAD;
  s.valid = true;
  return s;
}

#endif // MPU6050_DRIVER_H
