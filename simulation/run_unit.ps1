$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
New-Item -ItemType Directory -Force -Path sim | Out-Null

function Run-Tb($name, $files) {
    Write-Host "==== $name ===="
    & iverilog -g2005 -I rtl/dsp -o "sim/$name" @files
    if ($LASTEXITCODE -ne 0) { throw "compile failed $name" }
    & vvp "sim/$name"
    if ($LASTEXITCODE -ne 0) { throw "sim failed $name" }
}

Run-Tb tb_spi_master @(
    "rtl/spi/bgt60_spi_master.v",
    "simulation/unit/bgt60_spi_slave_model.v",
    "simulation/unit/tb_spi_master.v"
)
Run-Tb tb_mode3_unpack @(
    "rtl/radar/mode3_unpack.v",
    "simulation/unit/tb_mode3_unpack.v"
)
Run-Tb tb_peak_window @(
    "rtl/dsp/bg_profile_sub.v",
    "rtl/dsp/noise_filter.v",
    "rtl/dsp/peak_window.v",
    "simulation/unit/tb_peak_window.v"
)
Run-Tb tb_range_rate @(
    "rtl/dsp/range_rate.v",
    "simulation/unit/tb_range_rate.v"
)
Run-Tb tb_aoa_phase @(
    "rtl/dsp/aoa_phase.v",
    "simulation/unit/tb_aoa_phase.v"
)
Run-Tb tb_uart_telemetry @(
    "rtl/uart/uart_tx.v",
    "rtl/uart/telemetry.v",
    "simulation/unit/tb_uart_telemetry.v"
)
Write-Host "All unit tests passed (except tb_radar_top; run separately, longer)."
