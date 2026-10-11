# Architecture — radar_bgt_c

## 1. Purpose
Artix-7 (Basys3) SPI host for BGT60TR13C: configure a fast 1-chirp FMCW scene, stream Mode-3 FIFO (128 samples × 3 RX), 128-point range FFT, nearest baseball-sized flying target in 40 cm–1 m, inter-frame range-rate speed, RX1/RX3 azimuth, UART telemetry, 7-seg debug.

## 2. Block diagram

```
SW0 reset ──► bgt60_ctrl (FSM)
SW1 cal_mode ─────────────┐
         │                │
         ├─► bgt60_spi_master ── SPI ── BGT60TR13C
         │         │
         │         ▼
         │    mode3_unpack ──► range FFT (128, ×3 RX)
         │                         │
         │                         ▼
         │                    peak_window + bg_profile_sub
         │                         │
         │                    noise_filter (CFAR + baseball extent)
         │                         │
         │              ┌──────────┼──────────┐
         │              ▼          ▼          │
         │        range_rate   aoa_phase      │
         │              │          │          │
         │              │          │     speed│
         │              │          │          ▼
         │              │          │     fly gate ──► seven_seg
         │              └────┬─────┘          │
         │                   ▼                │
         │             uart_telemetry ◄───────┘
         │                   │
         │                   ▼
         │                 uart_tx
         └─► spi_reset_n, error LEDs
```

Single 100 MHz clock. No processor, DMA, AXI interconnect, or Doppler FFT.

## 3. Clock / reset
- `clk` 100 MHz, constrained 10 ns.
- SPI SCLK = clk/8 = 12.5 MHz (`MISO_HS=0`).
- Radar 80 MHz XTAL is on the Infineon shield.
- FPGA reset: SW0 → 2-FF sync, active-high `rst_sync`.
- Radar reset: DIO3 sequence while CS_N=1.

## 4. Controller FSM

| State | Action |
| --- | --- |
| WAIT_RESET | SW0=1: hold `spi_cs_n=1`, `spi_reset_n=0` |
| HW_RESET | 1 ms high, 1 ms low, 1 ms high on `spi_reset_n` |
| SOFT_RESET | write MAIN SW_RESET, poll until bits [3:1] clear |
| READ_CHIP_ID | read 0x02; require DIGITAL_ID=3 and RF_ID=3 |
| CONFIG_REGS | walk register ROM |
| START_FRAME | write MAIN FRAME_START |
| POLL_FIFO | read FSTAT; FOF_ERR → overflow_err; CREF=1 → BURST |
| BURST | unbounded FIFO burst, **192** words into unpacker |
| FEED / FWAIT | three sequential 128-pt FFTs (RX1, RX2, RX3) |
| DSP_WAIT | wait `peak_window.frame_done` |
| FRAME_NEXT | FSM_RESET then FRAME_START (1 chirp, no 64-group cube) |
| ERROR | sticky error_flag; wait SW0 |

## 5. Why 1 chirp / 128 samples
A dart at 20 m/s crosses 60 cm in ~30 ms. A 64-chirp / 100 ms frame yields 0–1 samples. One chirp, 128 samples, 192 FIFO words drains in ~369 µs at 12.5 MHz. Proven PLL1_7 T_SED ≈ 1.395 ms keeps CS idle during drain and still gives ~670 Hz frames (several range-rate points while the dart is in the window). UART is decimated to ≤200 Hz.

## 6. Register ROM
SPI write word = `{addr[6:0], 1'b1, data[23:0]}`. Analog CSx/PACR values match the proven 3-RX Infineon set. Chirp/frame/PLL/ADC/SFCTL fields are retuned for 128 samples / 1 chirp.

| Addr | Name | Data | Notes |
| --- | --- | --- | --- |
| 0x00 | MAIN | 0x7869C0 | T_WU≈1 ms; FRAME_START set separately |
| 0x01 | ADC0 | 0x0A0A40 | ADC_DIV=40 (2 Msps) |
| 0x04 | PACR1 | 0xE967FD | Infineon 3-RX + OSCCLKEN |
| 0x05 | PACR2 | 0x0805B4 | saw |
| 0x06 | SFCTL | 0x7000BF | PREFIX=0; MISO_HS=0; CREF=191 |
| 0x07 | SADC_CTRL | 0x010D00 | |
| 0x0B | CSCI | 0x000BE0 | |
| 0x0F | CSCDS | 0x000B60 | |
| 0x10 | CSU1_0 | 0x13FC51 | TX/RX/VCO/LO |
| 0x11 | CSU1_1 | 0x7FF41F | BBCH_SEL=111; TX_DAC=31 |
| 0x12 | CSU1_2 | 0x0238E3 | VGA=4, HP_GAIN=18 dB, HPF=80 kHz all RX |
| 0x16 | CSC1 | 0x000490 | CS_EN=1 |
| 0x2C | CCR0 | 0x52C200 | T_INIT1≈15 µs |
| 0x2D | CCR1 | 0x00024F | TR_START≈8 µs |
| 0x2E | CCR2 | 0x000001 | FRAME_LEN=0 (1 chirp); MAX_FRAME_CNT=1 |
| 0x2F | CCR3 | 0xABD464 | T_INIT0≈70 µs |
| 0x30 | PLL1_0 | 0xAA0000 | FSU 58 GHz |
| 0x31 | PLL1_1 | 0x000649 | RSU=1609 |
| 0x32 | PLL1_2 | 0x0002BC | RTU=700 → T_RAMP=70 µs |
| 0x33 | PLL1_3 | 0x000080 | APU=128 |
| 0x34–0x36 | PLL1_4..6 | 0 | saw |
| 0x37 | PLL1_7 | 0x36D310 | SH_EN=1; REPS=0; T_SED≈1.395 ms |

T_ACQU = 128/2e6 = 64 µs. T_RAMP = 10+1+64+3−8 = 70 µs. RTU = 700. RSU = round(2^20 × 5.5e9 / (8×700×640e6)) = 1609. BW ≈ 5.500 GHz. FRAME_START uses MAIN 0x7869C1. FSM_RESET uses 0x7869C4.

## 7. DSP
1. DC subtract: `{4'b0, sample} - 2048`.
2. One 128-pt FFT core, three times per chirp. Production: XFFT 9.1 pipelined streaming, 16-bit, scaled, natural order. Simulation: `fft128_stream` (`USE_XFFT=0`).
3. Non-coherent `|X1|²+|X2|²+|X3|²` on bins 0…63.
4. Optional empty-room subtract (`cal_mode`).
5. Nearest bin in 15…37 above floor and a local-max test. `distance_cm = (k * 2727 + 500) / 1000`.
6. `noise_filter`: CA-CFAR (2 guard + 4 reference bins each side, threshold = 4× reference mean) and a −6 dB extent of 1…4 bins. A baseball is 7.3 cm ≈ 2.7 bins at ΔR = 2.727 cm; the specular return is one bin and FFT spread stays inside four. Wider returns are rejected.
7. Speed: `(cm_n - cm_{n-1}) * 1e6 / dt_us` → `speed_cms`. Lost if gap > 10 ms. The filter reports the target only when `|speed|` is 800…6000 cm/s (a thrown baseball, either direction). The first sighting has no rate yet, so it stays `no_target` until the next frame.
8. Azimuth: CORDIC atan2 on RX1 and RX3 at winning bin; `θ = arcsin(Δφ/π)` with d=λ/2; output degrees × 10.

## 8. UART / display
ASCII `S,<seq>,<dist_cm>,<speed_cms>,<angle_x10>,<flags>\n` at ≤200 Hz. An accepted flying hit is copied into hold registers the cycle after the gate opens (distance and speed have already updated). `frame_clr` still wipes the detector workspace and does not wait on this copy. The 7-seg shows that distance for 300 ms; UART flag bit0 stays set for the same window. After 300 ms with no new hit both go back to no-target.

## 9. Decisions
- DECISION-001: Poll FSTAT.CREF (no IRQ in XDC).
- DECISION-002: 12.5 MHz SPI, MISO_HS=0.
- DECISION-003: Single 100 MHz domain.
- DECISION-004: 1 chirp / 128 samples / 3 RX. No RD cube, no Doppler FFT.
- DECISION-005: PREFIX_EN=0.
- DECISION-006: Speed = inter-frame range-rate (user: fast target).
- DECISION-007: ILA optional (`USE_ILA=1` bitstream only). Do not probe config MOSI/ROM.
- DECISION-008: Keep proven PLL1_7 T_SED ≈ 1.395 ms (longer than 369 µs drain; ~670 Hz frames).
- DECISION-009: Azimuth from RX1–RX3; elevation out of scope.
- DECISION-010: Noise filter passes only a baseball-sized flying return. Extent 1…4 bins (7.3 cm ball, ΔR = 2.727 cm). CA-CFAR alpha ≈ 4 on 8 reference cells. Flying gate 800…6000 cm/s. Range-rate still runs on the spatial hit so the next frame can measure speed.
- DECISION-011: Display and UART hold the last accepted hit for 300 ms. `frame_clr` still starts the next chirp on the same clock.

## 10. Specialist ownership
| Artifact | Owner |
| --- | --- |
| This document + contracts | Master |
| `rtl/**/*.v` | Master (no RTL Task agent in this repo) |
| `vivado/*.tcl`, XDC | Master / vivado-quality |
| `simulation/**` | Master |
| Architecture report | architecture-report-agent |
| Warning audit | warning-report-agent / vivado-quality |
