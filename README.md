# radar_bgt_c

Artix-7 design for the Digilent Basys 3 that drives an Infineon BGT60TR13C FMCW radar. The FPGA configures the chip over SPI, captures one chirp (128 samples on three receivers), and reports the nearest baseball-sized flying target between 40 cm and 1 m: distance, inter-frame speed, and azimuth.

There is no processor, DMA, or AXI interconnect. One 100 MHz clock. Production generics are `USE_XFFT=1` and `USE_ILA=1` (Xilinx FFT 9.1 plus an ILA). Simulation uses the behavioral FFT (`USE_XFFT=0`).

The checked-in bitstream is from the last Vivado build, `vivado_proj_vga4` (Vivado 2023.1, 8 Oct 2026). Setup and hold are met: WNS 0.157 ns, WHS 0.024 ns. Routed utilization on `xc7a35tcpg236-1` is about 68.5% LUT, 57.3% FF, and 99.4% slices.

## Hardware

| Item | Connection |
| --- | --- |
| Board | Digilent Basys 3, `xc7a35tcpg236-1` |
| Radar | Infineon BGT60TR13C shield on Pmod JB |
| Clock | `clk` W5, 100 MHz |
| Reset | SW0 (`reset`, V17). High holds the controller in reset. |
| Calibrate | SW1 (`cal_mode`, V16). High learns an empty-room range profile. |
| SPI | JB1–JB4 and JB7: SCLK A14, MOSI A16, MISO B15, CS_N B16, RESET_N A15. 12.5 MHz, mode 0. |
| UART | `uart_tx` A18, 115200 8N1, to the Basys 3 USB-UART |
| Status | LD0 `error_flag` (SPI / chip-id / config). LD1 `overflow_err` (FIFO overflow). |
| Display | 7-segment, centimetres, or `----` when there is no target |

Radar register values, the chirp timeline, and the DSP chain are in [docs/architecture.md](docs/architecture.md), [docs/requirements.md](docs/requirements.md), [docs/hardware-contract.md](docs/hardware-contract.md), and [docs/INTERFACES.md](docs/INTERFACES.md). The Infineon datasheet and shield manual are not in this repository.

## What a frame does

1. Hardware reset on the radar reset pin, then a soft reset and a chip-id check.
2. Program the register ROM: 1 chirp, 128 samples, 5.5 GHz sweep, Mode-3 FIFO (three ADCs).
3. Burst-read 192 FIFO words and unpack them into RX1, RX2, and RX3.
4. Three 128-point range FFTs, non-coherent power, optional empty-room subtract.
5. Keep the nearest bin in 15…37 that passes CA-CFAR and a 1…4 bin extent (a baseball, not a wide blob).
6. Speed is the change in range between frames. A hit is reported only when the speed is 8…60 m/s in either direction.
7. Azimuth is the RX1–RX3 phase difference, in tenths of a degree.

UART line, at most 200 Hz:

```
S,<seq>,<dist_cm>,<speed_cms>,<angle_x10>,<flags>
```

`flags` bit 0 stays set while the 7-segment is holding the last accepted throw (300 ms).

## Repository layout

| Path | Contents |
| --- | --- |
| `rtl/` | Synthesizable Verilog |
| `docs/Basys-3-Master.xdc` | Pin and timing constraints |
| `vivado/` | Scripts that create the project, IP, bitstream, and program the board |
| `bitstream/` | `radar_top.bit` and `radar_top.ltx` from `vivado_proj_vga4` |
| `simulation/` | Icarus Verilog unit benches |
| `python/radar_plot.py` | Live distance, speed, angle, and plan-position plot |
| `reports/*.rpt` | Utilization, timing, DRC, methodology, and CDC from the `vivado_proj_vga4` route |

Generated Vivado directories are not in git. `vivado_proj`, `vivado_proj_gain`, and `vivado_proj_hold` are older local builds. Rebuild with the scripts below; the default project directory is `vivado_proj/`.

## Build

Vivado **2023.1** is required (the FFT and ILA IP were generated with that version).

```
C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch -source vivado/build.tcl
```

That creates `vivado_proj/`, generates the XFFT and ILA, and writes a bitstream plus the reports under `reports/`. To use another directory (the last local build used `vivado_proj_vga4`):

```
set RADAR_PROJ_DIR=C:\path\to\vivado_proj_vga4
C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch -source vivado/build.tcl
```

## Program the board

With the Basys 3 connected and a local Vivado hardware server on port 3121:

```
C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch -source vivado/program_device.tcl
```

The script programs `bitstream/radar_top.bit` and loads `bitstream/radar_top.ltx` for the ILA.

## Simulate

[Icarus Verilog](https://steveicarus.github.io/iverilog/) on `PATH`:

```
powershell -File simulation/run_unit.ps1
```

Benches cover SPI frames, Mode-3 unpack, the peak window (point target, wide blob, CFAR, flying-speed gate), range-rate, angle, the UART line, and a synthetic beat inside 40–100 cm. `tb_radar_top` uses `FAST_SIM=1`.

## Plot

```
pip install pyserial matplotlib
python python/radar_plot.py
```

The script picks the Basys 3 USB-UART port. Override it with `--port COM5`. `--file capture.txt` replays a saved log instead of the live port. `python/sample_capture.txt` is a short example.

## Bring-up

1. SW0 high (reset held), SW1 low.
2. Program the FPGA.
3. Release SW0. LD0 should stay off after configuration. LD1 means the radar FIFO overflowed.
4. Point the radar at an empty lane, raise SW1 until the baseline is stored, then lower SW1.
5. Run `python/radar_plot.py`. A throw in the 40 cm–1 m window that is moving at 8–60 m/s shows distance on the 7-segment for 300 ms and a point on the plot.
