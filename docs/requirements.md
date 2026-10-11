# Requirements — radar_bgt_c (Basys3 / BGT60TR13C)

## REQ-001 System purpose
The FPGA on a Digilent Basys3 shall configure an Infineon BGT60TR13C over SPI, acquire one FMCW chirp per frame from three RX ADCs, compute the nearest target in **40 cm … 1 m**, and report **distance, speed, and azimuth** over UART to a host Python plot. Speed is **inter-frame range-rate** (dart-class 2–25 m/s), not intra-frame Doppler.

## REQ-002 User control
- **REQ-002a** SW0 (`reset`, V17) high holds wait-for-reset. Low starts HW/SW reset, configuration, then continuous frames.
- **REQ-002b** Returning SW0 high re-enters wait-for-reset and clears sticky error LEDs on the next release.
- **REQ-002c** SW1 (`cal_mode`, V16) high averages empty-room range profiles into a baseline; display and UART report no-target while calibrating.

## REQ-003 Radar configuration
| ID | Parameter | Value |
| --- | --- | --- |
| REQ-003a | Samples per chirp | 128 (`PLL1_3.APU`) |
| REQ-003b | Chirps per frame | 1 (`CCR2.FRAME_LEN=0`, `MAX_FRAME_CNT=1`) |
| REQ-003c | Frame period | T_RAMP + T_SED ≈ 70 µs + 1.40 ms ≈ **1.5 ms** (~670 Hz) |
| REQ-003d | Modulation | Saw-tooth (`PACR2.FSTDNEN=2`, FSD/RSD/RTD=0) |
| REQ-003e | FIFO packing | Mode 3 — three ADCs (`CSU1_1.BBCH_SEL=3'b111`) |
| REQ-003f | RF bandwidth | Full 5.5 GHz (58.0 → 63.5 GHz) |
| REQ-003g | ADC sample rate | 2 Msps (`ADC0.ADC_DIV=40`) |
| REQ-003h | FIFO CREF | 191 (192 words − 1) |

## REQ-004 SPI
FPGA is SPI master, mode 0, MSB first, 32-bit register frames, 12.5 MHz SCLK, FIFO burst from address 0x60 as in `hardware-contract.md`. No IRQ pin: poll `FSTAT.CREF`.

## REQ-005 Pins
Only ports assigned in `docs/Basys-3-Master.xdc`. Radar IRQ is not connected.

## REQ-006 Distance
- Range FFT length 128; search bins **15…37** (≈40.9 cm … 100.9 cm).
- `ΔR = c/(2B) = 2.727 cm`, `distance_cm = round(k * 2727 / 1000)`.
- Nearest passing bin wins. If none, `no_target`.
- A hit also has to pass the noise filter (REQ-014). Otherwise `no_target`.
- 7-segment shows integer centimetres or `----`.

## REQ-007 Speed
- `speed_cms = (R_n − R_{n-1}) / Δt` in centimetres per second, signed (approaching negative).
- Invalidate if the spatial detector reports `no_target` or the gap is > 10 ms. The flying gate does not clear the tracker.
- No Doppler FFT.

## REQ-008 Angle
- Azimuth from phase difference of RX1 and RX3 at the winning range bin.
- `θ = arcsin(Δφ · λ / (2π · d))` with `d = λ/2`.
- UART field is degrees × 10 (int16).

## REQ-009 UART
- 115200 8N1 on `uart_tx` (A18).
- ASCII line, at most 200 Hz: `S,<seq>,<dist_cm>,<speed_cms>,<angle_x10>,<flags>\n`

## REQ-010 Analog front-end
- TX_DAC = 31. All three RX: VGA=4, HP_GAIN=18 dB, HPF_SEL=3 (80 kHz). `CSU1_2 = 0x0238E3`.

## REQ-011 Errors
- `error_flag` (LED0): SPI/CHIP_ID/config timeout.
- `overflow_err` (LED1): `FSTAT.FOF_ERR`.

## REQ-012 Platform
- FPGA: `xc7a35tcpg236-1`, 100 MHz `clk` (W5).
- No MicroBlaze, DMA, or AXI interconnect.
- Reproducible batch build via `vivado/build.tcl`.

## REQ-014 Noise filter
The design shall report a target only when all of the following hold:

- **REQ-014a** CA-CFAR: the bin is at least 4× the mean power of 8 reference cells (4 each side), with 2 guard cells each side, and still at or above the absolute floor.
- **REQ-014b** Size: −6 dB extent is 1…4 bins. A baseball is 7.3 cm (about 2.7 bins at 2.727 cm/bin). Wider returns are not a baseball.
- **REQ-014c** Flying: `|speed_cms|` is between 800 and 6000 (8…60 m/s), either direction. Stationary clutter and one-frame glitches are `no_target`. The first frame of a track has no speed and stays blank until the next frame.

## REQ-013 Verification
Unit tests cover SPI frames, Mode-3 unpack (192 words), peak window (baseball point target, wide blob, CFAR clutter, flying-speed gate), range-rate, AoA, UART line format, and a synthetic beat that maps to a known centimetre value inside 40–100 cm.
