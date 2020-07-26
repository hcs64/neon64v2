// Convert 2bpp NES to 4bpp and 8bpp N64, place sprites

//define RSP_BUSY_LOOP()

// Work around missing SFV instr in cen64
// NOTE this doesn't currently fit in IMEM, so it also
// disables sprite rendering.
//define SIMULATE_SFV()

InitPPU:
  lqv v8[e0],ShiftMux0(r0)
  lqv v9[e0],ShiftMux1(r0)
  lqv v10[e0],BitsOfBytes(r0)
  lqv v26[e0],Line0FGPriority(r0)
  lqv v27[e0],Line1FGPriority(r0)
  lqv v28[e0],Masks(r0)
  lqv v29[e0],ShiftMuxSp0(r0)
  lqv v30[e0],ShiftMuxSp1(r0)
  lqv v31[e0],Zeroes(r0)

  jr ra
  nop

InitPPU2:
  la t0, conv_src_buffer & 0x7f'ffff
  la t1, conv_dst_bg_buffer0 & 0x7f'ffff
  la t2, conv_dst_sp_buffer0 & 0x7f'ffff
  sw t0, dmem_src_pos (r0)
  sw t1, dmem_dst_bg_pos (r0)
  jr ra
  sw t2, dmem_dst_sp_pos (r0)

scope ConvertLines: {
  lli ra, ConvertLines

  lw t0, dmem_conv_buf_read (r0)
  lw t1, dmem_conv_buf_write (r0)

  lw a0, dmem_src_pos (r0)
  lw a1, dmem_dst_bg_pos (r0)
  beq t0, t1, skip_conv
  lw s8, dmem_dst_sp_pos (r0)

-
  mfc0 t0, C0_DMA_FULL
  bnez t0,-
  nop

  lli t0, dmem_src
  mtc0 t0, C0_MEM_ADDR
  mtc0 a0, C0_DRAM_ADDR
  lli t0, conv_src_size-1
  mtc0 t0, C0_RD_LEN

-
  mfc0 t0, C0_DMA_BUSY
  bnez t0,-
  nop

  lli a2, dmem_src + src_bg_pat
  lli a3, dmem_dst
  lli t8, dmem_src + src_bg_atr
  lli t0, src_sp_pat - src_bg_pat

  lqv v11[e0], 0(a2) // V3 = Tile BitPlane 0,1 Row 0..7
bg_loop:
// We're doing the same operation for each of 8 8-pixel rows in v11.
// An element holds the high and low bitplane for one row.

// select bits
select_bits(v11)

// Prefetch the next tile
  lqv v11[e0], 16(a2) // V3 = Tile BitPlane 0,1 Row 0..7
  addiu a2, 16

// Column 7,6
// The elements of v0-v7 now contain each bit 0-7 of both bitplanes.
// For columns 7 and 6, we want to go from
//   AB.. .... CD.. ....
// to packed within 14-7
//   ...C A..D B... ....
// in order to be in place for sfv to write that as
//    ..C A..D B
// This involves shifting A and B right by different amounts, and
// C and D left by different amounts, and finally combining them all.
//
// Since we have each bit of a byte in its own reg
//   v7 = A... .... C... ....
//   v6 = .B.. .... .D.. ....
// we want to do these shifts:
//   (11-15) = >> 4 = .... A... .... C...
//   (12- 7) = << 5 = ...C .... .... ....
//   ( 7-14) = >> 7 = .... .... B... ....
//   ( 8- 6) = << 2 = .... ...D .... ....
// Left shifts use vm?n, a multiply, which doesn't clamp until bit 31.
// Right shifts use vm?l, which shifts the multiply result down by 16.
// Occasionally (see cols 1 & 3) we can do two shifts together if both
// bits need to be shifted in the same direction.
// Since there is only one bit in each column (they were 8 bits apart
// so only one of each pair ends up in the 14-7 window) we can combine
// with the accumulator using the vma? ops.
// We don't need to worry about the bits outside of 14-7, as long
// as they don't carry into bit 7, which isn't the case here.

  vmudl v12,v7,v8[e15]
  vmadn v12,v7,v9[e15]
  vmadl v12,v6,v8[e14]
  vmadn v12,v6,v9[e14]

// Column 5,4
  vmudl v13,v5,v8[e13]
  vmadn v13,v5,v9[e13]
  vmadl v13,v4,v8[e12]
  vmadn v13,v4,v9[e12]

// Load attribute bits
  luv v16[e0], 0(t8)

// Column 3,2
  vmudn v14,v3,v9[e11]
  vmadl v14,v2,v8[e10]
  vmadn v14,v2,v9[e10]

// Column 1,0
  vmudn v15,v1,v9[e9]
  vmadl v15,v0,v8[e8]
  vmadn v15,v0,v9[e8]

// Add attribute bits to pixels
// These are in bytes as
//   .... ..AB
// luv loads them as
//   .... ...A B... ....
// and we want them at
//   .AB. .AB. .... ....
// so they can end up, after sfv, as
//   AB.. AB..
// this is done by multiplying with 0b0100'0100,
// effectively (x<<2)|(x<<6), which is stashed in
// an otherwise unused element of ShiftMux0.
  vmudn v16,v16,v8[e9]

// Each element of v16 holds doubled attributes for
// each row, combine with each pair of pixels.
  vor v12,v12,v16[e0]
  vor v13,v13,v16[e0]
  vor v14,v14,v16[e0]
  vor v15,v15,v16[e0]

if !{defined SIMULATE_SFV} {
// Store Columns 7,6
  sfv v12[e0],0(a3)
  sfv v12[e8],16(a3)
  addi a3, 1
// Store Columns 5,4
  sfv v13[e0],0(a3)
  sfv v13[e8],16(a3)
  addi a3, 1
// Store Columns 3,2
  sfv v14[e0],0(a3)
  sfv v14[e8],16(a3)
  addi a3, 1
// Store Columns 1,0
  sfv v15[e0],0(a3)
  sfv v15[e8],16(a3)
  addi a3, 1+(32-4)
} else {

macro sfv_sim(e) {
evaluate rep_i(0)
  mfc2 t1,v12[{e}]
  srl t2, t1, 7
  sb t2, 0(a3)
  addiu a3, 1

  mfc2 t1,v13[{e}]
  srl t2, t1, 7
  sb t2, 0(a3)
  addiu a3, 1

  mfc2 t1,v14[{e}]
  srl t2, t1, 7
  sb t2, 0(a3)
  addiu a3, 1

  mfc2 t1,v15[{e}]
  srl t2, t1, 7
  sb t2, 0(a3)
  addiu a3, 1

evaluate rep_i({rep_i}+1)
}

  sfv_sim(e0)
  sfv_sim(e2)
  sfv_sim(e4)
  sfv_sim(e6)
  sfv_sim(e8)
  sfv_sim(e10)
  sfv_sim(e12)
  sfv_sim(e14)
}

  addi t0, -16
  bnez t0, bg_loop
  addi t8, 8

// Adjust for fine X scroll
scope FineXBG {
constant lines_left(sp_s0)
constant left_shift(sp_s1)
constant right_shift(sp_s2)
constant leftover(sp_s3)
constant tiles_left(sp_s4)
constant tile32(sp_s5)

// Working backwards in each line, shift each tile left, combine with the
// part that was shifted out of the previous tile.
  lli a2, dmem_dst+(32*8-1)*4
  lli tile32, dmem_dst+(33*8-1)*4
  lli lines_left, 8-1
shift_line_loop:
  lbu left_shift, dmem_src+src_bg_x (lines_left)
  lw leftover, 0 (tile32)
  addi tile32, -4
  lli tiles_left, 32
  bnez left_shift,+
  sll left_shift, 2
// srlv can only do up to 31 bits, so we can't do this for X=0 (it would be useless anyway)
  j shift_tile_loop_end
  addi a2, -32*4
+
// overloading tiles_left's 32 as 32 bits here
  sub right_shift, tiles_left, left_shift
  srlv leftover, right_shift

shift_tile_loop:

// SU loads take 3 cycles, so unroll these loops 4x
evaluate rep_i(0)
while {rep_i} < 4 {
evaluate src(t0 + {rep_i})
  lw {src}, -{rep_i} * 4 (a2)
  evaluate rep_i({rep_i} + 1)
}

evaluate rep_i(0)
while {rep_i} < 4 {
evaluate src(t0 + {rep_i})
evaluate shifted(t4 + {rep_i})
  sllv {shifted}, {src}, left_shift
  or {shifted}, leftover
  srlv leftover, {src}, right_shift
  sw {shifted}, -{rep_i} * 4 (a2)

  evaluate rep_i({rep_i} + 1)
}

  addi tiles_left, -4
  bnez tiles_left, shift_tile_loop
  addi a2, -4*4
shift_tile_loop_end:

  bnez lines_left, shift_line_loop
  addi lines_left, -1
}  // end scope FineXBG

// Apply left BG mask
  lbu t0, dmem_src + src_mask (r0)
  andi t0, 0b10
  bnez t0,+
  nop
  lli t0, 0
  lli t1, 32*4*(8-1)
-
  sw r0, dmem_dst (t0)
  bne t0, t1,-
  addi t0, 32*4
+

// DMA out BG
  lli t0, dmem_dst
  mtc0 t0, C0_MEM_ADDR
  mtc0 a1, C0_DRAM_ADDR
  lli t0, conv_dst_bg_size-1
  mtc0 t0, C0_WR_LEN

  addi a1, conv_dst_bg_size

// There's only one port to DMEM, so it's a good idea to wait for this DMA to
// finish before proceeding to the sprites.
-
  mfc0 t0, C0_DMA_BUSY
  bnez t0,-
  nop


// ##### Sprites
if !{defined SIMULATE_SFV} {
// Convert to 8bpp
  lli a2, dmem_src+src_sp_pat
  lli a3, dmem_src+src_sp_atr
  lli sp_s1, 8
  lli sp_s2, dmem_src+src_sp_x
  lli sp_s3, dmem_dst+0x80
  lli sp_s4, dmem_src+src_sp_pri

  lqv v11[e0], 0(a2)

sprite_loop:
macro sprite_convert(_76,_54,_32,_10) {
// Column 7,6
  vmudl v13,v7,v29[e15]
  vmadn v13,v7,v30[e15]
  vand v13,v13,v28[e8]
  vmudl v14,v6,v29[e14]
  vand v14,v14,v28[e9]
  vor {_76},v13,v14[e0]

// Column 5,4
  vmudl v13,v5,v29[e13]
  vmadn v13,v5,v30[e13]
  vand v13,v13,v28[e8]
  vmudl v14,v4,v29[e12]
  vand v14,v14,v28[e9]
  vor {_54},v13,v14[e0]

// Column 3,2
  vmudl v13,v3,v29[e11]
  vmadn v13,v3,v30[e11]
  vand v13,v13,v28[e8]
  vmudl v14,v2,v29[e10]
  vand v14,v14,v28[e9]
  vor {_32},v13,v14[e0]

// Column 1,0
  vmudl v13,v1,v29[e9]
  vmadn v13,v1,v30[e9]
  vand v13,v13,v28[e8]
  vmudl v14,v0,v29[e8]
  vmadn v14,v0,v30[e8]
  vand v14,v14,v28[e9]
  vor {_10},v13,v14[e0]

// Add attributes
  vmudl v24,v24,v8[e11]
  vmudn v24,v24,v10[e8]
  vor v24,v24,v10[e12]  // 0x1010, sprite palette

  vor {_76},{_76},v24[e0]
  vor {_54},{_54},v24[e0]
  vor {_32},{_32},v24[e0]
  vor {_10},{_10},v24[e0]
}

// First line (with 2 lines we can do a full transpose)
  lpv v24[e0], 0(a3) // attributes
select_bits(v11)
// Preload next line
  lqv v11[e0], 16(a2)
sprite_convert(v16,v17,v18,v19)

// Second line
  lpv v24[e0], 8(a3) // attributes
select_bits(v11)
// Preload next line
  lqv v11[e0], 32(a2)
sprite_convert(v20,v21,v22,v23)

// So now we have
// v16: pixel 0,1 of 8 sprites on line 0
// v17: pixel 2,3
// v18: pixel 4,5
// v19: pixel 6,7
// v20: pixel 0,1 of 8 sprites on line 1
// v21: pixel 2,3, line 1
// v22: pixel 4,5, line 1
// v23: pixel 6,7, line 1

// (0.0,0.1),...
// (0.2,0.3),...
// (0.4,0.5),...
// (0.6,0.7),...
// (8.0,8.1),...
// (8.2,8.3),...
// (8.4,8.5),...
// (8.6,8.7),...

// The idea is to transpose this to
// (0.0,0.1),(0.2,0.3),(0.4,0.5),(0.6,0.7),(8.0,8.1),(8.2,8.3),(8.4,8.5),(8.6,8.7)
// ...
// v16: line 0 sprite 0, line 1 sprite 0
// v17: line 0 sprite 1, line 1 sprite 1
// v18: line 0 sprite 2, line 1 sprite 2
// v19: line 0 sprite 3, line 1 sprite 3
// v20: line 0 sprite 4, line 1 sprite 4
// v21: line 0 sprite 5, line 1 sprite 5
// v22: line 0 sprite 6, line 1 sprite 6
// v23: line 0 sprite 7, line 1 sprite 7

// Begin transpose
  lli t0, dmem_dst
// Note: I'm not 100% sure that this is the layout in DMEM.
//         v17[0],v18[1],v19[2],v20[3],v21[4],v22[5],v23[6],v16[7] -> 0x70
  stv v16[e2], 0x70(t0)
  stv v16[e4], 0x60(t0)
  stv v16[e6], 0x50(t0)
  stv v16[e8], 0x40(t0)
  stv v16[e10], 0x30(t0)
  stv v16[e12], 0x20(t0)
  stv v16[e14], 0x10(t0)

// Complete transpose
// 0x70 -> v16[1],v17[2],v18[3],v19[4],v20[5],v21[6],v22[7],v23[0]
  ltv v16[e14], 0x70(t0)
  ltv v16[e12], 0x60(t0)
  ltv v16[e10], 0x50(t0)
  ltv v16[e8], 0x40(t0)
  ltv v16[e6], 0x30(t0)
  ltv v16[e4], 0x20(t0)
  ltv v16[e2], 0x10(t0)

// Compute opacity mask
// The resulting mask selects pre-existing bytes (pixels) to keep
macro sprite_mask(dest, src) {
// Select bit 0, inverted
  vnor {dest},{src},v28[e10]
// Select bit 1, inverted
  vnor v24,{src},v28[e11]
// >> 1
  vmudl v24,v24,v30[e10]
// AND the two bits together
  vand {dest},{dest},v24[e0]
// Expand into byte mask
  vmudn {dest},{dest},v28[e12]
}

// Add priority (0x20)
  lbu t0, 0 (sp_s4)
  lbu t1, 1 (sp_s4)
  addi sp_s4, 2
  sll t0, 32-8
  sll t1, 32-8

macro sprite_priority(reg) {
  bltz t0,+
  sll t0, 1
  vor {reg},{reg},v26[e0]
+
  bltz t1,+
  sll t1, 1
  vor {reg},{reg},v27[e0]
+
}
sprite_priority(v16)
sprite_priority(v17)
sprite_priority(v18)
sprite_priority(v19)

sprite_priority(v20)
sprite_priority(v21)
sprite_priority(v22)
sprite_priority(v23)

// Not needed for lowest-priority sprite
//sprite_mask(v7, v23)
sprite_mask(v6, v22)
sprite_mask(v5, v21)
sprite_mask(v4, v20)
sprite_mask(v3, v19)
sprite_mask(v2, v18)
sprite_mask(v1, v17)
sprite_mask(v0, v16)

// Zero out line 0
  lli t1, 256
  move t0, sp_s3
-
  sqv v31[e0],0(t0)
  addi t1, -16
  bnez t1,-
  addi t0, 16

// Fill in line 0 sprites
  lbu t3, 7(sp_s2)
  lbu t2, 6(sp_s2)
  lbu t1, 5(sp_s2)
  lbu t0, 4(sp_s2)

  add t3, sp_s3
  sdv v23[e0], 0(t3)

macro layer_sprite(pos, pixels, mask, element) {
// TODO I should do this for both lines at once.
// The problem right now is sprites sticking off the end of the line into the next one,
// to prevent that I erase the next line after drawing the first, but there should be an
// easier way, like padding at the end of the line? It's too bad we can't do stride from
// the RSP side.

// Pull in the pre-existing pixels
  ldv v14[{element}], 0({pos})
// Complement mask (NOR 0) for opacity
  vnor v15,v31,{mask}[e0]
// Select opaque pixels
  vand v15,v15,{pixels}[e0]
// Select uncovered pixels
  vand v14,v14,{mask}[e0]
// Combine
  vor v14,v14,v15[e0]
  sdv v14[{element}], 0({pos})
}

  add t2, sp_s3
  add t1, sp_s3
  add t0, sp_s3

layer_sprite(t2, v22, v6, e0)
layer_sprite(t1, v21, v5, e0)
layer_sprite(t0, v20, v4, e0)

  lbu t3, 3(sp_s2)
  lbu t2, 2(sp_s2)
  lbu t1, 1(sp_s2)
  lbu t0, 0(sp_s2)

  add t3, sp_s3
  add t2, sp_s3
  add t1, sp_s3
  add t0, sp_s3

layer_sprite(t3, v19, v3, e0)
layer_sprite(t2, v18, v2, e0)
layer_sprite(t1, v17, v1, e0)
layer_sprite(t0, v16, v0, e0)

  addi sp_s3, 256
  addi sp_s2, 8

// Zero out line 1
  lli t1, 256
  move t0, sp_s3
-
  sqv v31[e0],0(t0)
  addi t1, -16
  bnez t1,-
  addi t0, 16

// Fill in line 1 sprites
  lbu t3, 7(sp_s2)
  lbu t2, 6(sp_s2)
  lbu t1, 5(sp_s2)
  lbu t0, 4(sp_s2)

  add t3, sp_s3
  sdv v23[e8], 0(t3)

  add t2, sp_s3
  add t1, sp_s3
  add t0, sp_s3

layer_sprite(t2, v22, v6, e8)
layer_sprite(t1, v21, v5, e8)
layer_sprite(t0, v20, v4, e8)

  lbu t3, 3(sp_s2)
  lbu t2, 2(sp_s2)
  lbu t1, 1(sp_s2)
  lbu t0, 0(sp_s2)

  add t3, sp_s3
  add t2, sp_s3
  add t1, sp_s3
  add t0, sp_s3

layer_sprite(t3, v19, v3, e8)
layer_sprite(t2, v18, v2, e8)
layer_sprite(t1, v17, v1, e8)
layer_sprite(t0, v16, v0, e8)

  addi sp_s3, 256
  addi sp_s2, 8

  addi a2, 16*2
  addi sp_s1, -2
  bnez sp_s1,sprite_loop
  addi a3, 8*2

// Apply left sprite mask
  lbu t0, dmem_src + src_mask (r0)
  andi t0, 0b100
  bnez t0,+
  nop
  lli t0, 0
  lli t1, 32*8*(8-1)
-
  sw r0, dmem_dst+0x80+0 (t0)
  sw r0, dmem_dst+0x80+4 (t0)
  bne t0, t1,-
  addi t0, 32*8
+

// DMA out sprites
  lli t0, dmem_dst+0x80
  mtc0 t0, C0_MEM_ADDR
  mtc0 s8, C0_DRAM_ADDR
  lli t0, conv_dst_sp_size-1
  mtc0 t0, C0_WR_LEN

  addi s8, conv_dst_sp_size

-
  mfc0 t0, C0_DMA_BUSY
  bnez t0,-
  nop
} // if !{defined SIMULATE_SFV}

  addi a0, conv_src_size

if {defined RSP_BUSY_LOOP} {
  // Each iteration adds about 3 cycles (two instrs, extra for branch taken)
  la t0, 15'000'000/(240/8)/60
-
  bnez t0,-
  addi t0, -1
}

// Prepare pointers for next time
  lw t0, dmem_conv_buf_read (r0)
  lli t1, num_conv_buffers-1
  bne t0, t1,++
  addi t0, 1

  lw t0, dmem_frames_finished (r0)
  addi t0, 1
  sw t0, dmem_frames_finished (r0)

// Finished a frame's-worth of conv buffers, switch
  lb t0, dmem_which_framebuffer (r0)
  la a0, conv_src_buffer & 0x7f'ffff
  la a1, conv_dst_bg_buffer0 & 0x7f'ffff
  la s8, conv_dst_sp_buffer0 & 0x7f'ffff
// Opposite index for palettes as we're still writing into them now
  la a2, rgb_palette1 & 0x7f'ffff
  la a3, RenderDlist1.ClearCmd & 0x7f'ffff

  xori t0, 1
  beqz t0,+
  sb t0, dmem_which_framebuffer (r0)

  la a2, rgb_palette0 & 0x7f'ffff
  la a3, RenderDlist0.ClearCmd & 0x7f'ffff
  la t0, conv_dst_bg_buffer1 - conv_dst_bg_buffer0
  add a1, t0
  add s8, t0
+

// Copy RGB palette for the RDP
  lli t0, dmem_dst
  mtc0 t0, C0_MEM_ADDR
  la t0, frame_rgb_palette & 0x7f'ffff
  mtc0 t0, C0_DRAM_ADDR
  lli t0, 0x20*2-1
  mtc0 t0, C0_RD_LEN

  lli t0, dmem_dst
  mtc0 t0, C0_MEM_ADDR
  mtc0 a2, C0_DRAM_ADDR
  lli t0, 0x20*2-1
  mtc0 t0, C0_WR_LEN

-
  mfc0 t0, C0_DMA_BUSY
  bnez t0,-
  nop

// Write fill color into dlist
  lhu t0, dmem_dst (r0)
  lui t2, 0x3700
  sll t1, t0, 16
  or t0, t1
  sw t2, dmem_dst + 0 (r0)
  sw t0, dmem_dst + 4 (r0)

  lli t0, dmem_dst
  mtc0 t0, C0_MEM_ADDR
  mtc0 a3, C0_DRAM_ADDR
  lli t0, 8-1
  mtc0 t0, C0_WR_LEN

-
  mfc0 t0, C0_DMA_BUSY
  bnez t0,-
  nop

  la t0, ScheduleFinishFrame
  sw t0, dmem_completion_vector (r0)
  lli t0, 0
+
  sw a0, dmem_src_pos (r0)
  sw a1, dmem_dst_bg_pos (r0)
  sw s8, dmem_dst_sp_pos (r0)
  sw t0, dmem_conv_buf_read (r0)

skip_conv:
  lw t0, dmem_conv_buf_read (r0)
  lw t1, dmem_conv_buf_write (r0)
  beq t0, t1,+
  lli t0, 1
  sb t0, dmem_work_left (r0)
+
  j Yield
  nop
}
