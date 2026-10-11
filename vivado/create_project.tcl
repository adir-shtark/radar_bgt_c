# Create Vivado 2023.1 project for Basys3 radar_bgt_c.
# Usage:
#   C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch -source vivado/create_project.tcl

set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(RADAR_PROJ_DIR)] && $::env(RADAR_PROJ_DIR) ne ""} {
    set proj_dir $::env(RADAR_PROJ_DIR)
} else {
    set proj_dir [file join $root vivado_proj]
}
set part xc7a35tcpg236-1

puts "Tool: [version]"
if {![string match "*v2023.1*" [version]]} {
    puts "WARNING: expected Vivado v2023.1, got [version]"
}

file mkdir $proj_dir
create_project radar_bgt_c $proj_dir -part $part -force

set_property target_language Verilog [current_project]
set_property top radar_top [current_fileset]

set rtl_files [list \
    [file join $root rtl radar_top.v] \
    [file join $root rtl common sync_2ff.v] \
    [file join $root rtl spi bgt60_spi_master.v] \
    [file join $root rtl radar bgt60_reg_rom.v] \
    [file join $root rtl radar bgt60_ctrl.v] \
    [file join $root rtl radar mode3_unpack.v] \
    [file join $root rtl dsp fft128_stream.v] \
    [file join $root rtl dsp fft128_xfft_wrap.v] \
    [file join $root rtl dsp bg_profile_sub.v] \
    [file join $root rtl dsp noise_filter.v] \
    [file join $root rtl dsp peak_window.v] \
    [file join $root rtl dsp range_rate.v] \
    [file join $root rtl dsp aoa_phase.v] \
    [file join $root rtl uart uart_tx.v] \
    [file join $root rtl uart telemetry.v] \
    [file join $root rtl display seven_seg_driver.v] \
]

add_files -norecurse $rtl_files
set_property include_dirs [list [file join $root rtl dsp]] [current_fileset]
add_files -fileset constrs_1 -norecurse [file join $root docs Basys-3-Master.xdc]

set sim_files [list \
    [file join $root simulation unit tb_spi_master.v] \
    [file join $root simulation unit tb_mode3_unpack.v] \
    [file join $root simulation unit tb_peak_window.v] \
    [file join $root simulation unit tb_range_rate.v] \
    [file join $root simulation unit tb_aoa_phase.v] \
    [file join $root simulation unit tb_uart_telemetry.v] \
    [file join $root simulation unit tb_radar_top.v] \
    [file join $root simulation unit bgt60_spi_slave_model.v] \
]
add_files -fileset sim_1 -norecurse $sim_files
set_property include_dirs [list [file join $root rtl dsp]] [get_filesets sim_1]
set_property top tb_radar_top [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set_property generic {USE_XFFT=1 USE_ILA=1} [get_filesets sources_1]

if {[catch {source [file join $root vivado create_ips.tcl]} ip_err]} {
    puts "ERROR: IP generation failed ($ip_err)"
    exit 1
}

puts "Project created at $proj_dir"
