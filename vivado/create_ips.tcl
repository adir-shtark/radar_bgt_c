# Xilinx FFT 9.1 (128-pt) + ILA 6.2 for Vivado 2023.1
# Probe map: docs/hardware-contract.md §10.

proc rdi_set_ip {ip prop val} {
    if {[catch {set_property $prop $val $ip} err]} {
        puts "WARNING: could not set $prop = $val ($err)"
        return 0
    }
    puts "SET $prop = [get_property $prop $ip]"
    return 1
}

# ---------------------------------------------------------------------------
# xfft_0 — 128-point range FFT (USE_XFFT=1)
# ---------------------------------------------------------------------------
if {[llength [get_ips xfft_0]] == 0} {
    create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name xfft_0
}

set ip [get_ips xfft_0]
if {[llength $ip] == 0} {
    error "xfft_0 does not exist after create_ip"
}

rdi_set_ip $ip CONFIG.transform_length 128
rdi_set_ip $ip CONFIG.implementation_options pipelined_streaming_io
rdi_set_ip $ip CONFIG.input_width 16
rdi_set_ip $ip CONFIG.phase_factor_width 16
rdi_set_ip $ip CONFIG.scaling_options scaled
rdi_set_ip $ip CONFIG.rounding_modes truncation
rdi_set_ip $ip CONFIG.output_ordering natural_order
rdi_set_ip $ip CONFIG.aresetn true
rdi_set_ip $ip CONFIG.throttle_scheme nonrealtime
rdi_set_ip $ip CONFIG.data_format fixed_point
rdi_set_ip $ip CONFIG.cyclic_prefix_insertion false
rdi_set_ip $ip CONFIG.run_time_configurable_transform_length false
rdi_set_ip $ip CONFIG.ovflo false
rdi_set_ip $ip CONFIG.xk_index false
rdi_set_ip $ip CONFIG.target_clock_frequency 100
rdi_set_ip $ip CONFIG.target_data_throughput 50
rdi_set_ip $ip CONFIG.channels 1

if {[catch {generate_target all $ip} xfft_err]} {
    error "xfft_0 generate_target failed: $xfft_err"
}
puts "xfft_0 generated"

# ---------------------------------------------------------------------------
# ila_dsp_chain — USE_ILA=1 bitstream only
# ---------------------------------------------------------------------------
if {[llength [get_ips ila_dsp_chain]] == 0} {
    create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_dsp_chain
}

set ila [get_ips ila_dsp_chain]

rdi_set_ip $ila CONFIG.C_NUM_OF_PROBES 18
rdi_set_ip $ila CONFIG.C_DATA_DEPTH 2048
rdi_set_ip $ila CONFIG.C_EN_STRG_QUAL 1
if {![rdi_set_ip $ila CONFIG.C_ADV_TRIGGER true]} {
    rdi_set_ip $ila CONFIG.C_ADV_TRIGGER 1
}
rdi_set_ip $ila CONFIG.ALL_PROBE_SAME_MU true
if {![rdi_set_ip $ila CONFIG.ALL_PROBE_SAME_MU_CNT 4]} {
    rdi_set_ip $ila CONFIG.ALL_PROBE_SAME_MU_CNT 2
}
rdi_set_ip $ila CONFIG.C_INPUT_PIPE_STAGES 1

# hardware-contract.md §10
set probe_widths {1 1 1 24 1 12 12 12 8 1 1 1 16 1 16 16 1 1}
for {set i 0} {$i < 18} {incr i} {
    rdi_set_ip $ila CONFIG.C_PROBE${i}_WIDTH [lindex $probe_widths $i]
}

set nprobes [get_property CONFIG.C_NUM_OF_PROBES $ila]
if {$nprobes != 18} {
    error "ila_dsp_chain C_NUM_OF_PROBES=$nprobes expected=18"
}

if {[catch {generate_target all $ila} ila_err]} {
    error "ila_dsp_chain generate_target failed: $ila_err"
}
puts "ila_dsp_chain generated"
