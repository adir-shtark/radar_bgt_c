open_hw_manager
connect_hw_server -url localhost:3121
after 2000
refresh_hw_server [current_hw_server]
set targets [get_hw_targets]
puts "TARGETS: $targets"
if {[llength $targets] == 0} {
    puts "ERROR: no hw target on localhost:3121"
    exit 1
}
open_hw_target [lindex $targets 0]
set dev [lindex [get_hw_devices] 0]
puts "DEVICE: $dev"
if {$dev eq ""} {
    puts "ERROR: no hardware device"
    exit 1
}
current_hw_device $dev
set root [file normalize [file join [file dirname [info script]] ..]]
# Bitstream checked in from the last build, vivado_proj_vga4.
set bit [file join $root bitstream radar_top.bit]
set ltx [file join $root bitstream radar_top.ltx]
if {![file exists $bit]} {
    puts "ERROR: bitstream not found: $bit"
    exit 1
}
set_property PROGRAM.FILE $bit $dev
set_property PROBES.FILE $ltx $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "PROGRAMMED $bit"
exit 0
