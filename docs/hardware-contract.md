# Hardware Contract — radar_bgt_c / BGT60TR13C / Basys3

## 1. Board pins

| Port | Dir | Pin | IOSTANDARD | Notes |
| --- | --- | --- | --- | --- |
| clk | in | W5 | LVCMOS33 | 100 MHz |
| reset | in | V17 | LVCMOS33 | SW0, active-high |
| cal_mode | in | V16 | LVCMOS33 | SW1, empty-room calibration |
| spi_sclk | out | A14 (JB1) | LVCMOS33 | Radar CLK |
| spi_mosi | out | A16 (JB2) | LVCMOS33 | Radar DI |
| spi_miso | in | B15 (JB3) | LVCMOS33 | Radar DO |
| spi_cs_n | out | B16 (JB4) | LVCMOS33 | Radar CS_N, idle high |
| spi_reset_n | out | A15 (JB7) | LVCMOS33 | Radar DIO3 / RST |
| error_flag | out | U16 | LVCMOS33 | LED0 |
| overflow_err | out | E19 | LVCMOS33 | LED1 |
| seg[6:0] | out | W7,W6,U8,V8,U5,V5,U7 | LVCMOS33 | Active-low, seg[0]=A … seg[6]=G |
| an[3:0] | out | U2,U4,V4,W4 | LVCMOS33 | Active-low digit enables |
| uart_tx | out | A18 | LVCMOS33 | USB-UART TX, 115200 8N1 |

**ASSUMPTION:** Connect shield **3.3 V digital** castellated SPI/RST (not MMIC 1.8 V pads).
**ASSUMPTION:** Shield 80 MHz XTAL drives radar `OSC_CLK`.

Do not invent `set_input_delay` / `set_output_delay` for SPI.

## 2. SPI register word

32 bits, MSB first, SPI mode 0 (idle CLK low; sample on rising; change on falling).

```
[31:25] address (7 bit)
[24]    R/W   1 = write, 0 = read
[23:0]  data
```

MISO during the same 32 clocks: `[31:24] GSR0`, `[23:0]` register data.

SCLK = 12.5 MHz (sysclk/8). CS_N lead/trail ≥ 2 sysclk. CS_N high between register accesses.

Write helper: `word = {addr, 1'b1, data24}`.

## 3. FIFO burst

```
ADDR=0x7F, RW=1, SADDR=0x60, RWB=0, NBURSTS=0
word = 32'hFFC0_0000
```

Then **192 × 24-bit** FIFO words. One chirp Mode 3 = 128 samples × 3 RX = 384 samples = 192 words.

Poll **`FSTAT.CREF` (bit 21)**. Do not evaluate `FILL_STATUS` while MADC is filling.

## 4. Hardware reset
While `spi_cs_n = 1`: `spi_reset_n` 1 → 0 → 1. Each phase 1 ms.

## 5. Software reset
Write `MAIN.SW_RESET=1` (bit 1). Poll until bits [3:1] are 0. Wait 1 ms.

## 6. Mode-3 FIFO packing (128 samples)

| Word | [23:12] | [11:0] |
| --- | --- | --- |
| 3k     | ADC1[2k]   | ADC2[2k]   |
| 3k+1   | ADC3[2k]   | ADC1[2k+1] |
| 3k+2   | ADC2[2k+1] | ADC3[2k+1] |

k = 0 … 63. After 192 words, each RX has 128 samples.

## 7. Clocks and reset (FPGA)

| Clock | Freq | Domain |
| --- | --- | --- |
| clk | 100 MHz | Entire FPGA design |
| spi_sclk | 12.5 MHz | Generated pin, not a clock network |
| Radar SYS_CLK | 80 MHz | On-sensor / shield XTAL |

FPGA reset: synchronous active-high from SW0, two-FF synchronizer. SW1 same.

## 8. Numerical contract

| Item | Format |
| --- | --- |
| ADC sample | unsigned 12-bit, 0…4095 |
| FFT input | signed 16-bit = `{4'b0, sample} - 2048` |
| FFT | 128-pt, scaled, natural-order bins |
| Magnitude | unsigned 32-bit `re^2+im^2` |
| RX combine | NCI `\|X1\|²+\|X2\|²+\|X3\|²` |
| Search | bins 15…37 |
| cm | `distance_cm = (k * 2727 + 500) / 1000` |
| speed | signed 16-bit cm/s; approaching negative |
| angle | signed 16-bit degrees × 10 |
| ΔR | 2.727 cm (B = 5.5 GHz) |

## 9. UART line

```
S,<seq>,<dist_cm>,<speed_cms>,<angle_x10>,<flags>\n
```

flags bit0 = target valid, bit1 = error, bit2 = overflow, bit3 = speed valid.

Example: `S,1842,67,-1520,-85,9` → 67 cm, −15.20 m/s, −8.5°, valid+speed.

## 10. ILA (`ila_dsp_chain`, USE_ILA=1 only)

Clock: `clk` 100 MHz. Do not probe MOSI, SPI command/address/wdata, register ROM.

| Probe | Width | Net |
| --- | --- | --- |
| 0 | 1 | spi_miso |
| 1 | 1 | spi_sclk |
| 2 | 1 | spi_cs_n |
| 3 | 24 | spi_fifo_word |
| 4 | 1 | spi_fifo_valid |
| 5 | 12 | u_rx1 |
| 6 | 12 | u_rx2 |
| 7 | 12 | u_rx3 |
| 8 | 8 | sample_idx |
| 9 | 1 | sample_valid |
| 10 | 1 | chirp_done |
| 11 | 1 | peak_done |
| 12 | 16 | distance_cm |
| 13 | 1 | no_target (1 unless a flying baseball-sized return passed the noise filter) |
| 14 | 16 | speed_cms |
| 15 | 16 | angle_x10 |
| 16 | 1 | uart_tx |
| 17 | 1 | uart_start |
