# Unit simulation

From the repo root, with Icarus Verilog:

```
iverilog -g2005 -I rtl/dsp -o sim/tb_spi_master rtl/spi/bgt60_spi_master.v simulation/unit/bgt60_spi_slave_model.v simulation/unit/tb_spi_master.v
vvp sim/tb_spi_master
```

Or run `simulation/run_unit.ps1`.

`tb_radar_top` uses `FAST_SIM=1` and `USE_XFFT=0` (RTL 128-pt FFT).
