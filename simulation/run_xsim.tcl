# Run unit tests with Vivado xsim. Usage from repo root:
#   C:\Xilinx\Vivado\2023.1\bin\vivado.bat -mode batch -source simulation/run_xsim.tcl

set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
file mkdir sim
set inc [file join $root rtl dsp]

proc run_tb {name srcs} {
    global root inc
    set work [file join $root sim $name]
    file mkdir $work
    cd $work
    set xvlog_cmd [list xvlog -sv -work work --include $inc]
    foreach s $srcs { lappend xvlog_cmd $s }
    puts "==== compile $name ===="
    if {[catch {eval exec $xvlog_cmd} err]} {
        puts $err
        error "xvlog failed $name"
    }
    if {[catch {exec xelab -debug typical work.$name -s ${name}_sim} err]} {
        puts $err
        error "xelab failed $name"
    }
    if {[catch {exec xsim ${name}_sim -runall} err]} {
        puts $err
        error "xsim failed $name"
    }
    puts $err
    cd $root
}

set r $root
run_tb tb_spi_master [list \
    [file join $r rtl spi bgt60_spi_master.v] \
    [file join $r simulation unit bgt60_spi_slave_model.v] \
    [file join $r simulation unit tb_spi_master.v]]

run_tb tb_mode3_unpack [list \
    [file join $r rtl radar mode3_unpack.v] \
    [file join $r simulation unit tb_mode3_unpack.v]]

run_tb tb_peak_window [list \
    [file join $r rtl dsp bg_profile_sub.v] \
    [file join $r rtl dsp noise_filter.v] \
    [file join $r rtl dsp peak_window.v] \
    [file join $r simulation unit tb_peak_window.v]]

run_tb tb_range_rate [list \
    [file join $r rtl dsp range_rate.v] \
    [file join $r simulation unit tb_range_rate.v]]

run_tb tb_aoa_phase [list \
    [file join $r rtl dsp aoa_phase.v] \
    [file join $r simulation unit tb_aoa_phase.v]]

run_tb tb_uart_telemetry [list \
    [file join $r rtl uart uart_tx.v] \
    [file join $r rtl uart telemetry.v] \
    [file join $r simulation unit tb_uart_telemetry.v]]

puts "ALL UNIT TESTS PASSED"
