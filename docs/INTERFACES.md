# INTERFACES.md

## radar_top
Producer: board. Consumer: all internal modules.

| Signal | Dir | Width | Clock | Notes |
| --- | --- | --- | --- | --- |
| clk | in | 1 | — | 100 MHz |
| reset | in | 1 | async in | SW0 |
| cal_mode | in | 1 | async in | SW1, 2-FF sync |
| spi_sclk | out | 1 | derived | idle 0 |
| spi_mosi | out | 1 | derived | |
| spi_miso | in | 1 | sampled on sclk rise | |
| spi_cs_n | out | 1 | clk | idle 1 |
| spi_reset_n | out | 1 | clk | |
| error_flag | out | 1 | clk | sticky |
| overflow_err | out | 1 | clk | sticky |
| seg | out | 7 | clk | active-low |
| an | out | 4 | clk | active-low |
| uart_tx | out | 1 | clk | idle 1 |

## bgt60_spi_master
| Signal | Dir | Width | Notes |
| --- | --- | --- | --- |
| start | in | 1 | captured when ~busy |
| cmd | in | 2 | 0=write, 1=read, 2=fifo burst |
| addr | in | 7 | |
| wdata | in | 24 | |
| burst_nwords | in | 10 | 192 for one chirp |
| busy / done | out | 1 | done 1-cycle |
| rdata | out | 24 | last register read |
| gsr0 | out | 8 | |
| fifo_word / fifo_word_valid | out | 24 / 1 | |

## mode3_unpack
| Signal | Dir | Width | Notes |
| --- | --- | --- | --- |
| word / word_valid | in | 24 / 1 | |
| chirp_start | in | 1 | pulse before first word |
| rx1/rx2/rx3 | out | 12 | |
| sample_idx | out | 8 | 0…127 |
| sample_valid | out | 1 | time-aligned triplet |
| chirp_done | out | 1 | after sample 127 |

## fft128 (stream / xfft wrap)
AXI-Stream 128, 16-bit real/imag packed `{imag[15:0], real[15:0]}`. `tlast` on sample/bin 127.

## peak_window
| Signal | Dir | Width | Notes |
| --- | --- | --- | --- |
| bin_re / bin_im | in | 16 | FFT output |
| bin_valid / fft_last | in | 1 | |
| cal_mode | in | 1 | |
| speed_valid / speed_cms | in | 1 / 16 | from range_rate, flying gate |
| frame_done | out | 1 | after 3 RX FFTs + noise filter |
| distance_cm | out | 16 | |
| no_target | out | 1 | spatial miss (size or CFAR) |
| gated_no_target | out | 1 | spatial miss, or not flying |
| peak_bin | out | 8 | |
| rx1_re/im, rx3_re/im | out | 16 | complex at peak bin |

## range_rate
| Signal | Dir | Width | Notes |
| --- | --- | --- | --- |
| sample_valid | in | 1 | pulse with a new distance |
| no_target | in | 1 | |
| distance_cm | in | 16 | |
| speed_cms | out | 16 | signed |
| speed_valid | out | 1 | |

## aoa_phase
| Signal | Dir | Width | Notes |
| --- | --- | --- | --- |
| start | in | 1 | with valid IQ |
| re1/im1/re3/im3 | in | 16 | |
| done | out | 1 | |
| angle_x10 | out | 16 | signed degrees × 10 |

## uart_telemetry
| Signal | Dir | Width | Notes |
| --- | --- | --- | --- |
| send | in | 1 | accepted when ~busy |
| seq, dist_cm, speed_cms, angle_x10 | in | 16 | |
| flags | in | 8 | |
| uart_tx | out | 1 | |
| busy | out | 1 | |

## seven_seg_driver
`value[15:0]`, `blank`, outputs `seg[6:0]`, `an[3:0]`.
