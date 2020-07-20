if {defined NTSC_NES} {
constant clock_rate(21'477'272)
constant cpu_div(12)
constant ppu_div(4)
constant vblank_lines(20)

// TODO lots of weird half-APU-cycle details here
constant apu_quarter_frame_cycles(7457*cpu_div)

align(2)
noise_period_table:
  dh    4,    8,   16,   32,   64,  96,  128,  160
  dh  202,  254,  380,  508, 762, 1016, 2034, 4068

dmc_rate_table:
  dh   428,  380,  340,  320,  286,  254,  226,  214
  dh   190,  160,  142,  128,  106,   84,   72,   54

dmc_cycle_table:
  dh   41088,  36480,  32640,  30720,  27456,  24384,  21696,  20544
  dh   18240,  15360,  13632,  12288,  10176,   8064,   6912,   5184


macro ppu_mul(reg, tmp) {
  sll {reg}, 2
  nop // pad to equal size to make swapping easier
}
} else if {defined PAL_NES} {
constant clock_rate(26'601'712)
constant cpu_div(16)
constant ppu_div(5)
constant vblank_lines(70)

constant apu_quarter_frame_cycles(8311*cpu_div)

align(2)
noise_period_table:
  dh   4,   8,  14,  30,  60,   88,  118,  148
  dh 188, 236, 354, 472, 708,  944, 1890, 3778

dmc_rate_table:
  dh   398,  354,  316,  298,  276,  236,  210,  198
  dh   176,  148,  132,  118,   98,   78,   66,   50

dmc_cycle_table:
  dh   50944,  45312,  40448,  38144,  35328,  30208,  26880,  25344
  dh   22528,  18944,  16896,  15104,  12544,   9984,   8448,   6400
  
macro ppu_mul(reg, tmp) {
  sll {tmp}, {reg}, 2
  add {reg}, {tmp}
}
}

align(4)
