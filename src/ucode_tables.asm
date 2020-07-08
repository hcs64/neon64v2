// Resident tables at the start of DMEM for the APU ucode
ResidentDMEMStart:
dmem_abuf_addrs:
evaluate rep_i(0)
while {rep_i} < num_abufs {
  dw (audiobuffer&0x7f'ffff) + {rep_i}*abuf_size
evaluate rep_i({rep_i}+1)
}

align(4)
dmem_initial_task_ras:
  dh Ucode.ConvertLines, Ucode.RunAPU

dmem_pulse_mix_table:
  db 0
evaluate rep_i(1)
while {rep_i} <= 15+15 {
  db (9552 * 255) / (8128 / {rep_i} + 100) / 100
evaluate rep_i({rep_i}+1)
}

dmem_dtn_mix_table:
  db 0
evaluate rep_i(1)
while {rep_i} <= 3*15+2*15+127 {
  db (16367 * 255) / (24329 / {rep_i} + 100) / 100
evaluate rep_i({rep_i}+1)
}

dmem_pulse_sequence_table:
 db 0b0000'0001
 db 0b0000'0011
 db 0b0000'1111
 db 0b1111'1100

dmem_tri_sequence_table:
evaluate rep_i(0)
while {rep_i} < 32 {
if {rep_i} < 16 {
  db (15-{rep_i})*3
} else {
  db ({rep_i}-16)*3
}
  evaluate rep_i({rep_i}+1)
}

align(16)
ResidentDMEMEnd:

constant resident_dmem_size(ResidentDMEMEnd-ResidentDMEMStart)

// These are all loaded into VU regs once at boot for the PPU ucode
// Unfortunately it isn't possible to use constants for VU reg names(?)

// v31
Zeroes:
  fill 8*2,0

// v10
BitsOfBytes:
  dh 0x0101, 0x0202, 0x0404, 0x0808
  dh 0x1010, 0x2020, 0x4040, 0x8080

macro select_bits(src) {
// select bits
  vand v7,{src},v10[e15]
  vand v6,{src},v10[e14]
  vand v5,{src},v10[e13]
  vand v4,{src},v10[e12]
  vand v3,{src},v10[e11]
  vand v2,{src},v10[e10]
  vand v1,{src},v10[e9]
  vand v0,{src},v10[e8]
}


// Pseudo shifts (and adds) to put bits in 12,11 and 8,7 (for sfv)
// v8
ShiftMux0:
  dh  1<<(16+( 7- 8)) // -16
  //dh  1<<    (11- 9)  // unused, combined with mux1
  dh  0b0100'0100     // used to promote attributes (4bpp)
  dh  1<<(16+( 7-10)) // -16
  //dh  1<<    (11-11)  // unused, combined with mux1
  dh  1<<(16-(8-2))   // used to promote attributes (8bpp)
  dh  1<<(16+( 7-12)) // -16
  dh  1<<(16+(11-13)) // -16
  dh  1<<(16+( 7-14)) // -16
  dh  1<<(16+(11-15)) // -16

// v9
ShiftMux1:
  dh  1<<( 8- 0)
  dh  (1<<(12- 1))|(1<<(11-9))
  dh  1<<( 8- 2)
  dh  (1<<(12- 3))|(1<<(11-11))
  dh  1<<( 8- 4)
  dh  1<<(12- 5)
  dh  1<<( 8- 6)
  dh  1<<(12- 7)

// Pseudo shifts to put bits in 9,8 and 1,0 (for sdv)
// v29
ShiftMuxSp0:
//   ....'...A ....'...B
//
//   ....'.... ....'...A
// + ....'..A. ....'..B.
// = ....'..A. ....'..BA
  dh  0x10000>>-( 0- 8) // >>8 | <<1
//   ....'..A. ....'..B.
//   
//   ....'...A ....'...B
// + ....'..B. ....'....
// = ....'..BA ....'...B
  dh  0x10000>>-( 8- 9) // >>1 | <<8
//   ....'.A.. ....'.B..
//
//   ....'.... ....'...A
// + ....'..A. ....'..B.
// = ....'..A. ....'..BA
  dh (0x10000>>-( 0-10))|(0x10000>>-( 1- 2)) // >>10 | >> 1
//   ....'A... ....'B...
//
//   ....'...A ....'...B
// + ....'..B. ....'....
// = ....'..BA ....'...B
  dh  0x10000>>-( 8-11) // >>3 | << 6
//   ...A'.... ...B'....
//
//   ....'.... ....'...A
// + ....'..A. ....'..B.
// = ....'..A. ....'..BA
  dh (0x10000>>-( 0-12))|(0x10000>>-( 1- 4)) // >>12 | >> 3
//   ..A.'.... ..B.'....
//
//   ....'...A ....'...B
// + ....'..B. ....'....
// = ....'..BA ....'...B
  dh  0x10000>>-( 8-13) // >>5 | << 4
//   .A..'.... .B..'....
//
//   ....'.... ....'...A
// + ....'..A. ....'..B.
// = ....'..A. ....'..BA
  dh (0x10000>>-( 0-14))|(0x10000>>-( 1- 6)) // >>14 | >> 5
//   A...'.... B...'....
//
//   ....'...A ....'...B
// + ....'..B. ....'....
// = ....'..BA ....'...B
  dh  0x10000>>-( 8-15) // >>7 | << 2

// v30
ShiftMuxSp1:
  dh       1<< ( 1- 0) // left
  dh       1<< ( 9- 1) // left
  //dh 0x10000>>-( 1- 2) // right (unused)
  dh 0x10000>> 1       // right shift 1 (for opacity mask)
  dh       1<< ( 9- 3) // left
  dh 0x10000>>-( 1- 4) // right (unused)
  dh       1<< ( 9- 5) // left
  dh 0x10000>>-( 1- 6) // right (unused)
  dh       1<< ( 9- 7) // left

// v28
Masks:
  dh 0x0300, 0x0003, 0b1111'1110'1111'1110, 0b1111'1101'1111'1101
  dh 0x00ff,0,0,0

// v26
Line0FGPriority:
  dh 0x2020, 0x2020, 0x2020, 0x2020
  dh 0,0,0,0
// v27
Line1FGPriority:
  dh 0,0,0,0
  dh 0x2020, 0x2020, 0x2020, 0x2020

