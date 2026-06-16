---
name: tang-nano-20k-headers
description: Complete verified J5/J6 20-pin header pinout for Tang Nano 20K (from official Sipeed pin diagram + schematic 3921 rev 1.22)
metadata:
  type: project
---

Verified against BOTH the official Sipeed rendered pin-label diagram (wiki.sipeed.com .../assets/nano_20k/tang_nano_20k_pinlabel.png) AND the official schematic `Tang_Nano_20K_3921_Schematics.pdf` (rev 1.22, KiCad, connectors J5/J6 = Conn_01x20). Both agree. All header banks are LVCMOS33 (Bank0/1/3/4/5/6 all VIO=3.3V on this board).

The two 20-pin headers expose these FPGA pins (each shared with an onboard alias function — board does NOT have free dedicated GPIO):

LEFT header J6 (top->bottom): pos = pin (alias)
1=73 IOT40A, 2=74 IOT34B, 3=75 IOT34A, 4=85 IOT4B, 5=77 IOT30A,
6=15 IOL47A(LED0), 7=16 IOL47B(LED1), 8=27 IOB8A, 9=28 IOB8B, 10=25 IOB6A,
11=26 IOB6B, 12=29 IOB14A, 13=30 IOB14B, 14=31 IOB29A,
15=17 IOL49A(LED2), 16=20 IOL51B(LED5), 17=19 IOL51A(LED4), 18=18 IOL49B(LED3),
19=3V3, 20=GND.
(Bottom 6 left-header signal pins 17/20/19/18 are ALL onboard LEDs — avoid for I/O.)

RIGHT header J5 (top->bottom):
1=5V, 2=GND, 3=76 IOT30B, 4=80 IOT27A(SDIO_D2), 5=42 IOB42B(LCD_R3),
6=41 IOB43A(LCD_R4), 7=56 IOR36A(I2S_BCLK), 8=54 IOR38A(I2S_DIN),
9=51 IOR45A(PA_EN, audio amp shutdown), 10=48 IOR49B(LCD_DE),
11=55 IOR36B(I2S_LRCK), 12=49 IOR49A(LCD_BL), 13=86 IOT4A, 14=79 IOT27B(WS2812/2812_DIN),
15=GND, 16=3V3, 17=72 IOT40B, 18=71 IOT44A, 19=53 IOR38B(EDID_CLK), 20=52 IOR39A(EDID_DAT).

KEY FACTS:
- Pins 25,26,27,28,29,30,31 (IOB6/8/14/29, Bank5) are the cleanest "general" header GPIO on the LEFT header — NOT tied to LEDs, NOT SDRAM, NOT power. Best choice for a parallel bus. They sit contiguously at J6 positions 8-14.
- Pin 79 = WS2812 onboard RGB LED data (right header pos14). Usable as GPIO if onboard WS2812 unused, but it will also drive that LED.
- Pins 41,42 = onboard nothing critical except RGB-LCD R3/R4 (LCD connector unused in ASV) -> usable.
- Pins 71,72,73,74,75,76,77,80,85,86 (IOT bank1) are header-accessible HSPI/SDIO-alias pins; free if SD card + HSPI unused.
- AVOID on headers: 15,16,17,18,19,20 (LEDs), 51 (PA_EN audio), 79 (WS2812) unless those functions are unused.
- NOT on either header (consumed onboard / in-package, do NOT use for external wiring): SDRAM die pins, MS5351 pins 10/11, BL616 UART pins 69/70, JTAG pins 5/6/7/8, crystal pin 4, flash pins, HDMI/DVI differential pairs, MSPI.
- The 27MHz clock (pin 4) and UART (69 SYS_TX / 70 SYS_RX go to BL616) are NOT on the 2 headers.

How to apply: For any ASV external bus on the Tang Nano 20K, hand-pick from this verified list. The 14-pin AD9226 bus should use the Bank5 block 25-31 plus adjacent IOT/IOB header pins, all on the LEFT header J6 for single-ribbon wiring where possible.

VALIDATED 2026-06-13: adc_interface.cst now uses adc_data[0..11]=73,74,75,85,77,27,28,25,26,29,30,31; otr=80; adc_clk=76. All confirmed real header pads, LVCMOS33, zero collision with uart_tx.cst (4/86/88). Approved with conditions (DRVDD=3.3V + OEB-low/DFS=AVSS are bench checks, not .cst). Note: adc_data[11]=pin31 is MSB, adc_data[0]=pin73 is LSB — ribbon order matters.
