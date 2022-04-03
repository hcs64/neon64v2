scope FrameLoop: {
-
  lli t0, 1
  ls_gp(sb t0, rsp_interrupt_wait)
  lui t1, SP_MEM_BASE
  lw t0, SP_DMEM + dmem_conv_buf_read (t1)
  beqz t0,+
  nop
-
  ls_gp(lbu t0, rsp_interrupt_wait)
  bnez t0,-
  nop
  j --
  nop
+

// commit palette
  la t4, frame_rgb_palette
  ls_gp(ld t0, working_rgb_palette + 0x00)
  ls_gp(ld t1, working_rgb_palette + 0x08)
  ls_gp(ld t2, working_rgb_palette + 0x10)
  ls_gp(ld t3, working_rgb_palette + 0x18)

  cache data_create_dirty_exclusive, 0x00 (t4)
  sd t0, 0x00 (t4)
  sd t1, 0x08 (t4)
  cache data_hit_write_back, 0x00 (t4)
  cache data_create_dirty_exclusive, 0x10 (t4)
  sd t2, 0x10 (t4)
  sd t3, 0x18 (t4)
  cache data_hit_write_back, 0x10 (t4)

  ls_gp(ld t0, working_rgb_palette + 0x20)
  ls_gp(ld t1, working_rgb_palette + 0x28)
  ls_gp(ld t2, working_rgb_palette + 0x30)
  ls_gp(ld t3, working_rgb_palette + 0x38)

  cache data_create_dirty_exclusive, 0x20 (t4)
  sd t0, 0x20 (t4)
  sd t1, 0x28 (t4)
  cache data_hit_write_back, 0x20 (t4)
  cache data_create_dirty_exclusive, 0x30 (t4)
  sd t2, 0x30 (t4)
  sd t3, 0x38 (t4)
  cache data_hit_write_back, 0x30 (t4)

  ls_gp(lw t0, ppu_frame_count)
  addi t0, 1
  ls_gp(sw t0, ppu_frame_count)

  sb r0, are_sprites_evaled (r0)
// pre-render scanline
  daddi cycle_balance, idle_pixels * ppu_div

// Clear vblank, sp0, overflow in status
  lbu t0, ppu_status (r0)
  andi t0, 0b0001'1111
  sb t0, ppu_status (r0)
  daddi t0, r0, -1
  sd t0, ppu_sp0_cycle (r0)

  bgezal cycle_balance, Scheduler.Yield
  nop

// Technically there's normal access happening during the prerender line, but
// doesn't seem important yet.
  daddi cycle_balance, visible_pixels * ppu_div
  bgezal cycle_balance, Scheduler.Yield
  nop

  lbu t1, odd_frame (r0)
  lbu t0, ppu_mask (r0)
  xori t2, t1, 1
  sb t2, odd_frame (r0)

  andi t0, 0b001'1000
// If rendering is disabled, don't reset scroll or skip idle
  beqz t0, line_loop
  sb r0, cur_scanline (r0)

// Rendering is enabled, prepare for line 0
// reset scroll
// This combines the end-of-scanline reset of X with the start-of-frame reset of Y
  lhu ppu_vaddr, ppu_scroll (r0)

// Skip the idle cycle on odd frames.
// Technically this goes at the end of the prerender line, but shouldn't matter
  bnez t1, skip_idle
  nop

line_loop:
// First (idle) cycle
// Technically at the beginning of the visible pixels, but shouldn't matter here (sp0 hit is another story)
  daddi cycle_balance, idle_pixels * ppu_div
skip_idle:

if {defined LOG_VRAM_ADDR} {
  move a0, ppu_vaddr
  jal PrintHex
  lli a1, 4

  jal PrintStr0
  la_gp(a0, newline)

  lbu a0, cur_scanline (r0)
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop
}

if {defined PPU_MMC3} {
// The counter ticks when we fetch the first sprite tile

constant mmc3_irq_delay(4)

  daddi cycle_balance, mmc3_irq_delay * ppu_div
  bgezal cycle_balance, Scheduler.Yield
  nop

  lbu t0, ppu_mask (r0)
  andi t0, 0b0001'1000
  neg t0
  bltzal t0, Mapper4.ScanlineCounter
  nop
// TODO consider different combinations of pattern tables, 8x16 sprites, 2006 clocking...
  daddi cycle_balance, (sprite_fetch_pixels - mmc3_irq_delay) * ppu_div
} else {
  daddi cycle_balance, sprite_fetch_pixels * ppu_div
}

  lbu t0, ppu_mask (r0)
  andi t0, 0b0001'0000
  bnez t0, sprites_enabled
  nop

// Init shift regs
  lui ppu_t0, 0xffff
  lli ppu_t1, 0
  lli ppu_t2, 0
  lli t9, 0

// Zero sprites on this line
  lbu t0, cur_scanline (r0)
  la_gp(a0, num_sprites_line)
  add a0, t0
  sb r0, 0(a0)

  sb r0, sp0_this_line (r0)

  j sprite_fetch_done
  nop

sprites_enabled:
// ##### Precompute what sprites end up on what lines.


  lbu t9, are_sprites_evaled (r0)
  la_gp(a0, num_sprites_line + 1)
  bnez t9, yes_sprites_evaled
  la_gp(a1, oam)
  la_gp(a2, sprites_line + 8)

// Clear all counters
  la_gp(t0, num_sprites_line)
  lli t1, 240
-
  sd r0, 0 (t0)
  addi t1, -8
  bnez t1,-
  addi t0, 8

// TODO note what scanline we first hit overflow?
// Won't be completely accurate but better than nothing
scope {
  lbu t1, ppu_ctrl (r0)
  lli t9, 8
  andi t1, 0b10'0000  // 8x16 mode
  srl t1, 2
  add t9, t1

  lli t0, 0
all_spr_loop:
  lbu t1, 0 (a1)  // Y index
  addi a1, 4
  add a3, t1, t9

next_line:
  beq t1, a3, eval_next // end of sprite
  addi t2, t1, -0xef
  bgez t2, eval_next // offscreen
  add t2, t1, a0

  lbu t3, 0 (t2)      // # sprites on this line
  sll t4, t1, 3
  add t4, a2          // list of sprites on this line

  addi t3, -8
  beqz t3, next_line  // line is full
  addi t1, 1

  addi t3, 8+1
  sb t3, 0 (t2)
  add t3, t4
  j next_line
  sb t0, -1 (t3)

eval_next:
  addi t2, t0, -63
  bnez t2, all_spr_loop
  addi t0, 1

  sb t9, are_sprites_evaled (r0)
}

if {defined LOG_SPRITES} {
  addi sp, 16
  sb t9, -16 (sp)

  lli t0, 0

-
  sb t0, -8(sp)
  move a0, t0
  jal PrintHex
  lli a1, 2
  jal PrintStr0
  la_gp(a0, sprites_colon_msg)

  lbu t0, -8(sp)
  la_gp(a0, num_sprites_line)
  add a0, t0
  lbu a0, 0(a0)
  jal PrintHex
  lli a1, 2
  jal NewlineAndFlushDebug
  nop
  lbu t0, -8(sp)
  lli t1, 239

  bne t1, t0,-
  addi t0,1

  jal NewlineAndFlushDebug
  nop

  lbu t9, -16 (sp)
  addi sp, -16
}

yes_sprites_evaled:

// ##### Fetch sprites
  andi t9, 0b1'0000
  beqz t9, spr_8x8
  sb r0, sp0_this_line (r0)

macro sprite_fetch(height) {
  la_gp(a0, num_sprites_line)
  la_gp(a1, oam)

if {height} == 8 {
  lbu a3, ppu_ctrl (r0)
}
  lbu t0, cur_scanline (r0)
if {height} == 8 {
  andi a3, 0b1000
  sll a3, 12-3
}
  la_gp(a2, sprites_line)

  add a0, t0
  sll t1, t0, 3
  add a2, t1

  addi t0, -1

// ppu_t0: Pattern shift reg
  lui ppu_t0, 0xffff
// ppu_t1: Attribute shift reg
  lli ppu_t1, 0
// ppu_t2: X pos shift reg
  lli ppu_t2, 0
// t9: priority shift reg (0 fg, 1 bg)
  lli t9, 0


  lli t2, 0
-
  lbu t1, 0 (a0)
  beq t2, t1, sprite_fetch_done
  addi t2, 1

// Sprite index
  lbu t1, 0 (a2)
  addi a2, 1

// Load sprite
  sll t1, 2
  add t1, a1
  lbu t8, 3 (t1)  // X

// Store X
  dsll ppu_t2, 8
  or ppu_t2, t8

  lbu t8, 1 (t1)  // Tile index

// TODO I don't think this is needed?
if {defined PPU_MMC4} {
if {height} == 8 {
  lli t4, 0xfd
  beq t4,t8,+
  lli t4, 0xfe
  bne t4,t8,++
  nop
+
  srl t4, a3, 12
  add t4, gp
  sb t8, mapper10_latch - gp_base (t4)
+
} else {
// 8x16 is not used, I think?
  syscall 1
}
}

  lb t3, 2 (t1)  // Attributes
  lbu t4, 0 (t1)  // Y

// Y flip (bit 7, sign)
  bgez t3,+
  sub t4, t0, t4
if {height} == 8 {
  addi t4, -7
} else {
  addi t4, -15
}
  neg t4
+

// Fetch tiles
if {height} == 8 {
  sll t8, 4
  add t4, t8
  add t4, a3
} else {
// High rows are in the next tile
  andi a3, t4, 0b1000
  andi t4, 0b111
  sll a3, 1
  add t4, a3
// Low bit of idx selects pattern bank
  andi a3, t8, 1
  andi t8, 0b1111'1110
  sll a3, 12
  add t4, a3
  sll t8, 4
  add t4, t8
}

if {defined PPU_MMC2} {
  lli t8, 0x0fd0
  beq t4, t8,+
  lli t8, 0x0fe0
  bne t4, t8,++
  nop
+
  ls_gp(sh t4, mapper9_latch0)
+
}
  srl t8, t4, 10
  sll t8, 2
  lw t8, ppu_map (t8)
  // delay slot?
  add t4, t8
  lbu t8, 0 (t4)
  lbu t4, 8 (t4)

// Check if this is sp0
  bne t1, a1,+
  sll t9, 1
// Save its solid pixels
// TODO this should take into account X flip
  or t1, t4, t8
  sb t1, sp0_this_line (r0)
+

// Priority
  andi t1, t3, 0b0010'0000
  srl t1, 5
  or t9, t1

// Palette
  andi t1, t3, 0b11
  dsll ppu_t1, 8
  or ppu_t1, t1

// X flip
  andi t3, 0b0100'0000
  beqz t3,+
  dsll t1, ppu_t0, 16
  la_gp(t3, hflip_table)
  add t8, t3
  lbu t8, 0 (t8)
  add t4, t3
  lbu t4, 0 (t4)
+

  sll t8, 8
  or t4, t8
  bltz ppu_t0,-
  or ppu_t0, t1, t4
// Write full pattern reg

  ls_gp(lw t1, sp_pat_pos)
  sd ppu_t0, 0(t1)
  addi t1, 8
  ls_gp(sw t1, sp_pat_pos)

  j -
  lui ppu_t0, 0xffff
}

sprite_fetch(16)

spr_8x8:
sprite_fetch(8)

sprite_fetch_done:

// ##### Write out remaining pattern
  lbu t1, 0 (a0)
  ls_gp(lw t0, sp_pat_pos)

  addi t2, t1, -4
  bgez t2,+
  addi t2, t1, -8

// < 4 sprites, finish shift and write
// For every sprite less than 4, shift 16
  lli t3, 4
  sub t3, t1
  sll t3, 4-1
  dsllv ppu_t0, t3
  dsllv ppu_t0, t3  // double shift as dsllv can't do 64
  sd ppu_t0, 0 (t0)
  addi t0, 8
  j ++
  move ppu_t0, r0

+
  bgez t2,++
  nop
// < 8 sprites, finish shift and write
// For every sprite less than 8, shift 16
  lli t3, 8
  sub t3, t1
  sll t3, 4-1
  dsllv ppu_t0, t3
  dsllv ppu_t0, t3  // double shift again
+
  sd ppu_t0, 0 (t0)
  addi t0, 8
+

  ls_gp(sw t0, sp_pat_pos)

// Save priority
// For every sprite less than 8, shift 1
  lbu t0, cur_scanline (r0)
  lli t2, 8
  sub t2, t1

  sllv t9, t2
  andi t0, 7
  sb t9, ppu_sp_pri (t0)

// Write out sprite attributes and X positions
  ls_gp(lw t0, sp_atr_pos)
  ls_gp(lw t3, sp_x_pos)

// For every sprite less than 8, shift 8
  sll t2, 3

// Not bothering with double shift here as no sprites means empty patterns from above
  dsllv ppu_t1, t2
  sd ppu_t1, 0 (t0)
  addi t0, 8
  ls_gp(sw t0, sp_atr_pos)

  dsllv ppu_t2, t2
  sd ppu_t2, 0(t3)
  addi t3, 8
  ls_gp(sw t3, sp_x_pos)

// ##### Begin background
  bgezal cycle_balance, Scheduler.Yield
  nop

if {defined PPU_MMC2} {
  jal Mapper9.Latch0
  ls_gp(lhu t0, mapper9_latch0)
}
if {defined PPU_MMC4} {
  ls_gp(lbu t0, mapper10_latch + 0)
  jal Mapper10.Latch
  lli t1, 0x0000

  ls_gp(lbu t0, mapper10_latch + 1)
  jal Mapper10.Latch
  lli t1, 0x1000
}

// ##### Fetch background
// TODO This really belongs at the start of visible pixels
  daddi cycle_balance, bg_dummy_nt_pixels * ppu_div

if 1 != 1 {
  lbu t0, ppu_mask (r0)
  andi t0, 0b0000'1000
  bnez t0, bg_render_enabled
  nop
// BG render disabled, send zeroes

// Clear convert buffers
  ls_gp(lw t0, bg_pat_pos)
  ls_gp(lw t1, bg_atr_pos)

  lli t2, 32/8-1
-
  sd r0, 0 (t0)
  sd r0, 8 (t0)
  sd r0, 0 (t1)
  addi t0, 16
  addi t1, 8
  bnez t2,-
  addi t2, -1

  ls_gp(sw t0, bg_pat_pos)
  ls_gp(sw t1, bg_atr_pos)

// Clear shift registers
  move ppu_t0, 0
  move ppu_t1, 0

  j bg_fetch_flush
  daddi cycle_balance, (bg_fetch_tiles * tile_pixels) * ppu_div
}

bg_render_enabled:

// Set up the fetch loop

// ppu_t0: Pattern shift reg (if gez this shift will fill the reg)
  lui ppu_t0, 0xffff
// ppu_t1: Attribute shift reg ('')
  addi ppu_t1, r0, -0x100
// ppu_t2: Tiles left
  lli ppu_t2, bg_fetch_tiles-2  // not fetching final tile here

  ld t1, target_cycle (r0)
  la_gp(t0, FetchBG)
  sw t0, ppu_catchup_cb (r0)
  dadd t1, cycle_balance
  ls_gp(sd t1, ppu_catchup_current_cycle)

// FIXME fake sp0, set if there are any solid pixels in sp0
  lbu t0, sp0_this_line (r0)
  beqz t0,+
  ld t3, ppu_sp0_cycle (r0)

  ls_gp(lbu t0, oam + 3) // sp0 X
  bgez t3,+
  addi t0, 1  // delay of 1 pixel
  andi t3, t0, 0xff
  bne t3, t0,+  // no hit on X=255
  ppu_mul(t0, t3)
  dadd t2, t0, t1
  daddi t2, bg_prefetch_pixels * ppu_div
  sd t2, ppu_sp0_cycle (r0)
+

  daddi cycle_balance, bg_fetch_tiles * tile_pixels * ppu_div
  bgezal cycle_balance, Scheduler.Yield
  nop

// If there is still fetch left when we resume, finish it.
  lw t0, ppu_catchup_cb (r0)
  bnez t0, FetchBG
  la_gp(ra, bg_fetch_flush)

  j bg_fetch_flush
  nop

macro nt_at_addr(vaddr, nt_addr, at_addr) {
  andi t0, {vaddr}, 0b1100'0000'0000 // NT select
  srl t3, t0, 10-2
  lw t3, ppu_map + 8*4 (t3) // 0x2000 >> 10 == 8
  andi {nt_addr}, {vaddr}, 0b1111'1111'1111 // Current NT address
  addi {nt_addr}, 0x2000
  add {nt_addr}, t3

  andi t1, {vaddr}, 0b00'0001'1100  // Coarse X scroll / 4
  srl t1, 2
  andi t2, {vaddr}, 0b11'1000'0000  // Coarse Y scroll / 4
  srl t2, 4
  or {at_addr}, t1, t2
  addi {at_addr}, 0x23c0
  add {at_addr}, t0
  add {at_addr}, t3
}

macro nt_at_fetch(bg_cycle_balance, nt_addr, pt_base, at_byte, nt_shift, at_shift, tiles_left, nt_full, at_full, yield, finish) {
  bgez {bg_cycle_balance}, {yield}
// Fetch NT byte
  lbu t0, 0 ({nt_addr})
  daddi {bg_cycle_balance}, 8 * ppu_div
  addi {nt_addr}, 1

// Fetch PT bytes
  sll t3, t0, 4
  add t3, {pt_base}
  srl t1, t3, 10
  sll t1, 2
  lw t1, ppu_map (t1)
  dsll t2, {nt_shift}, 16
  add t1, t3, t1
  lbu t3, 0 (t1)
  lbu t1, 8 (t1)
  sll t3, 8
  or t3, t1

if {defined PPU_MMC2} || {defined PPU_MMC4} {
  lli t1, 0xfd
  beq t0, t1,+
  lli t1, 0xfe
  bne t0, t1,++
  nop
+
  addi sp, 16
  sw t3, -8 (sp)
  sd t2, -16 (sp)
if {defined PPU_MMC2} {
  jal Mapper9.Latch1
  nop
}
if {defined PPU_MMC4} {
  jal Mapper10.Latch
  move t1, {pt_base}
}
  lw t3, -8 (sp)
  ld t2, -16 (sp)
  addi sp, -16
+
}

  bgezal {nt_shift}, {nt_full}
  or {nt_shift}, t3, t2

// Select AT bits
  andi t0, {at_byte}, 0b11
  dsll t1, {at_shift}, 8
  bgezal {at_shift}, {at_full}
  or {at_shift}, t0, t1

  beqz {tiles_left}, {finish}
  addi {tiles_left}, -1
}

// We enter here from anywhere that changes state during a line,
// before the change is made.
FetchBG:
// t8: Cycle balance to catch up
  ld t8, target_cycle (r0)
  ls_gp(ld t0, ppu_catchup_current_cycle)
  dadd t8, cycle_balance
  dsub t8, t0, t8

// t9: Initial tiles left, to count tiles completed in each run
  move t9, ppu_t2
// s8: Temp vaddr
  move s8, ppu_vaddr

// Yield immediately if we already ran past this time
  bltz t8,+
  ls_gp(sw ra, ppu_catchup_ra)
  jr ra
  nop
+

// If rendering was disabled mid-line...
// Spend cycles, but avoid updating vaddr
if 1 == 1 {
  lbu t0, ppu_mask (r0)
  andi t0, 0b0000'1000
  bnez t0, fetch_enabled
  nop
if 1 == 1 {
-
  bgez t8,+
  nop
  daddi t8, tile_pixels * ppu_div

  dsll t1, ppu_t0, 16
  bgezal ppu_t0, nt_full
  move ppu_t0, t1

  dsll t1, ppu_t1, 8
  bgezal ppu_t1, at_full
  move ppu_t1, t1

  bnez ppu_t2,-
  addi ppu_t2, -1

  sw r0, ppu_catchup_cb (r0)

+
  sub t0, t9, ppu_t2

// track cycles
  ls_gp(ld t2, ppu_catchup_current_cycle)
  sll t1, t0, 3 // *8
  ppu_mul(t1, t3)
  dadd t2, t1
  ls_gp(sd t2, ppu_catchup_current_cycle)

  ls_gp(lw ra, ppu_catchup_ra)
  jr ra
  nop
}
fetch_enabled:
}


// a2: BG pattern table base + fine Y
  lbu a2, ppu_ctrl (r0)
  srl t0, s8, 12
  andi a2, 0b1'0000
  sll a2, 12-4
  add a2, t0

// a0: Name table address
// a1: Attribute table address
  nt_at_addr(s8, a0, a1)

// AT phase:
// 0 = 1 tile with left..
// 1 = 1 tile with left...
// 2 = 1 tile with right...
// 3 = 1 tile with right, goto 0
  andi t2, s8, 0b00'0000'0011

  sll t2, 2
  add t2, gp
  lw t2, at_phase_jump_table - gp_base (t2)

// Load AT byte
// a3: AT byte, shifted to expose next tile's bits
  lbu a3, 0 (a1)
  andi t0, s8, 0b00'0100'0000 // bit 1 of coarse Y scroll (top or bottom)
  andi t1, s8, 0b00'0000'0010 // bit 1 of coarse X scroll (left or right)
  srl t0, 6-2 // x4
  srlv a3, t0 // select top or bottom
  jr t2
  srlv a3, t1 // select left or right

at_phase_jump_table:
  dw at_phase0, at_phase1, at_phase2, at_phase3

at_phase0:
nt_at_fetch(t8, a0, a2, a3, ppu_t0, ppu_t1, ppu_t2, nt_full, at_full, bg_fetch_yield, bg_fetch_finish)
at_phase1:
nt_at_fetch(t8, a0, a2, a3, ppu_t0, ppu_t1, ppu_t2, nt_full, at_full, bg_fetch_yield, bg_fetch_finish)
  srl a3, 2
at_phase2:
nt_at_fetch(t8, a0, a2, a3, ppu_t0, ppu_t1, ppu_t2, nt_full, at_full, bg_fetch_yield, bg_fetch_finish)
at_phase3:
nt_at_fetch(t8, a0, a2, a3, ppu_t0, ppu_t1, ppu_t2, nt_full, at_full, bg_fetch_yield, bg_fetch_finish)

  andi t0, a0, 0b1'1111
  bnez t0,+
  addi a1, 1

// Wrap to other nametable (horizontal)
  andi s8, 0b111'1111'1110'0000
  xori s8, 0b000'0100'0000'0000

// TODO this can be somewhat simplified given X == 0?
  nt_at_addr(s8, a0, a1)

+
// Fetch a new attribute table byte
  lbu a3, 0 (a1)

  andi t0, s8, 0b00'0100'0000 // bit 1 of coarse Y scroll
  srl t0, 6-2 // x4
  j at_phase0
  srlv a3, t0 // select top or bottom

nt_full:
  ls_gp(lw t0, bg_pat_pos)
  sd ppu_t0, 0 (t0)
  addi t0, 8
  lui ppu_t0, 0xffff
  jr ra
  ls_gp(sw t0, bg_pat_pos)

at_full:
  ls_gp(lw t0, bg_atr_pos)
  sd ppu_t1, 0 (t0)
  addi t0, 8
  addi ppu_t1, r0, -0x100
  jr ra
  ls_gp(sw t0, bg_atr_pos)

bg_fetch_yield:
  sub t0, t9, ppu_t2

// track cycles
  ls_gp(ld t2, ppu_catchup_current_cycle)
  sll t1, t0, 3 // *8
  ppu_mul(t1, t3)
  dadd t2, t1
  ls_gp(sd t2, ppu_catchup_current_cycle)

-
  ls_gp(lw ra, ppu_catchup_ra)

// update vaddr
  add t1, ppu_vaddr, t0
  xor t2, t1, ppu_vaddr
// check for X overflow
  andi ppu_vaddr, 0b111'1111'1110'0000
// # NT wraps, mod 2
  andi t2, 0b000'0000'0010'0000
  sll t2, 10-5
  xor ppu_vaddr, t2
  andi t1, 0b1'1111
  jr ra
  or ppu_vaddr, t1

bg_fetch_finish:
  sub t0, t9, ppu_t2
  j -
  sw r0, ppu_catchup_cb (r0)

bg_fetch_flush:
if {defined PPU_MMC2} || {defined PPU_MMC4} {
// Tile 34
  andi t0, ppu_vaddr, 0b1100'0000'0000  // NT select
  srl t1, t0, 10-2
  lw t1, ppu_map + 8*4 (t1) // 0x2000 >> 10 == 8
  andi t0, ppu_vaddr, 0b1111'1111'1111 // Current NT address
  addi t0, 0x2000
  add t0, t1

  lbu t0, 0 (t0)
  lli t1, 0xfd
  beq t0, t1,+
  lli t1, 0xfe
  bne t0, t1,++
  nop
+
if {defined PPU_MMC2} {
  jal Mapper9.Latch1
  nop
}
if {defined PPU_MMC4} {
  lbu t1, ppu_ctrl (r0)
  andi t1, 0b1'0000
  jal Mapper10.Latch
  sll t1, 12-4
}
+
}

// Store per-line values, cached for now
  lbu t0, cur_scanline (r0)

  lbu t2, ppu_fine_x_scroll (r0)
  andi t1, t0, 0b111
  sb t2, ppu_bg_x_lines (t1)

  sb ppu_t1, ppu_bg32_atr_lines (t1)
  sll t1, 1

  sh ppu_t0, ppu_bg32_pat_lines (t1)

  lbu t0, cur_scanline (r0)
  addi t0, 1

  andi t1, t0, 0b111
  bnez t1,+
  sb t0, cur_scanline (r0)
// Every 8 lines...

// Poke the RSP
// TODO shouldn't this go after SetConvertPos?
  jal RSP.Run
  lli a0, ppu_rsp_task

// Uncached write for the per-line values
// TODO: should these all be already in their destination, just cached, and this could simply be a writeback?
// bg_pat_pos should now be pointing at src_bg32_pat
  ls_gp(lw t0, bg_pat_pos)
  ld t1, ppu_bg32_pat_lines + 0 (r0)
  ld t2, ppu_bg32_pat_lines + 8 (r0)
  sd t1, 0 (t0)
  sd t2, 8 (t0)
  ld t1, ppu_bg32_atr_lines (r0)
  ld t2, ppu_bg_x_lines (r0)
  ld t3, ppu_sp_pri (r0)
  sd t1, src_bg32_atr - src_bg32_pat (t0)
  lbu t1, ppu_mask (r0)
  sd t2, src_bg_x - src_bg32_pat (t0)
  sd t3, src_sp_pri - src_bg32_pat (t0)
  sb t1, src_mask - src_bg32_pat (t0)

// Setup positions for the next buffer
  jal PPU.SetConvertPos
  lli a0, 1
+

  lbu t0, cur_scanline (r0)
  lli t1, 240
  beq t0, t1, postrender_line
  nop

  lbu t0, ppu_mask (r0)
  andi t0, 0b0001'1000
  beqz t0, line_loop
  nop

// Increment fine Y
  addi t0, ppu_vaddr, 0b0001'0000'0000'0000
  andi t1, t0,        0b1000'0000'0000'0000
  beqz t1,+
  nop
// Fine Y = 8, increment coarse Y
  andi ppu_vaddr, 0b1111'1111'1111  // fine Y = 0
  addi t1, ppu_vaddr, 0b0000'0010'0000  // Y += 1
  andi t1, 0b11'1110'0000 // Mask out Y (eliminate overflow)
  andi t2, ppu_vaddr, 0b1100'0001'1111  // Y = 0
  lli t3,  0b11'1100'0000  // Y == 30 (start of attribute tables)
  bne t1, t3,+
// (Delay slot) use incremented Y
  or t0, t1, t2
// Coarse Y = 29 (attribute tables)
  xori t0, t2, 0b1000'0000'0000 // flip nametable (vertical) and Y = 0
+

// Reset X
  lhu t1, ppu_scroll (r0)
  andi t0, 0b111'1011'1110'0000 // X = 0
  andi t1, 0b000'0100'0001'1111 // Select X scroll
  j line_loop
  or ppu_vaddr, t0, t1

postrender_line:
if {defined DUMP_VRAM} {
  addi sp, 4*3

  lli t0, 0
  //la_gp(t1, ppu_ram)
  la t1, chrram
  lli t2, 0
-
  bnez t2,+
  addi t2, -1

  sw t0, -4(sp)
  sw t1, -8(sp)

  jal NewlineAndFlushDebug
  nop

  lw a0, -4(sp)
  jal PrintHex
  lli a1, 4

  jal PrintStr0
  la_gp(a0, space)

  lw t0, -4(sp)
  lw t1, -8(sp)
  lli t2, 3
+
  sw t0, -4(sp)
  sw t1, -8(sp)
  sw t2, -12(sp)
  ld a0, 0(t1)
  jal PrintHex
  lli a1, 16

  lw t0, -4(sp)
  lw t1, -8(sp)
  lw t2, -12(sp)

  addi t0, 8
  subi t3, t0, 0x400
  bnez t3,-
  addi t1, 8

  jal NewlineAndFlushDebug
  nop

  addi sp, -4*3
}

// post-render scanline (before NMI)
// This includes the prefetch which would have been the end of line 239.
  daddi cycle_balance, (hblank_pixels + scanline_pixels + vblank_delay) * ppu_div

// vblank scanlines
  bgezal cycle_balance, Scheduler.Yield
  nop

  lbu t0, ppu_status (r0)
  lbu t1, ppu_ctrl (r0)
  ori t0, 0b1000'0000
  sb t0, ppu_status (r0)

  andi t1, 0b1000'0000
  srl t1, 7-1
  sb t1, nmi_pending (r0)

  la t0, (vblank_lines * scanline_pixels - vblank_delay) * ppu_div
  dadd cycle_balance, t0
  bgezal cycle_balance, Scheduler.Yield
  nop

  j FrameLoop
  nop
}
