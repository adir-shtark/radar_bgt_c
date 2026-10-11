# Batch build with Vivado 2023.1: create project, XFFT+ILA IP, synth, impl, bitstream.
# Usage from repo root:
#   C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch -source vivado/build.tcl

set root [file normalize [file join [file dirname [info script]] ..]]
source [file join $root vivado create_project.tcl]

if {[catch {source [file join $root vivado create_ips.tcl]} ip_err]} {
    puts "ERROR: IP generation failed ($ip_err)"
    exit 1
}

set reports [file join $root reports]
file mkdir $reports

set_param general.maxThreads 4
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: synthesis failed"
    exit 1
}
open_run synth_1
report_utilization -file [file join $reports synth_util.rpt]
report_timing_summary -file [file join $reports synth_timing.rpt]

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: implementation failed"
    exit 1
}
open_run impl_1
report_timing_summary -file [file join $reports impl_timing.rpt]
report_utilization -file [file join $reports impl_util.rpt]
report_drc -file [file join $reports impl_drc.rpt]
report_methodology -file [file join $reports impl_methodology.rpt]
report_cdc -file [file join $reports impl_cdc.rpt]

puts "Build complete. Bitstream under vivado_proj/"
puts "Hardware Manager probes file: impl_1/radar_top.ltx"
