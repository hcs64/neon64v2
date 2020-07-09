//define LOG_PPU_DATA()
//define LOG_VRAM_ADDR()
//define LOG_SPRITES()
//define DUMP_RGB_PALETTE()
//define DUMP_VRAM()
//define MAPPER9()
define MAPPER10()

begin_low_page()

align_dcache()

// 0x0000-0x4000 in 0x400 (1K, >>10) pages
ppu_map:;     fill 4*16

align(8)
ppu_bg32_pat_lines:;  dd 0,0
ppu_bg32_atr_lines:;  dd 0
ppu_bg_x_lines:; dd 0
ppu_sp_pri:;  dd 0

ppu_catchup_cb:; dw 0

ppu_scroll:;  dh 0

ppu_fine_x_scroll:; db 0
ppu_scroll_latch:; db 0
ppu_read_buffer:; db 0
ppu_ctrl:;    db 0
ppu_mask:;    db 0
ppu_status:;  db 0
cur_scanline:;  db 0
odd_frame:;   db 0
oam_addr:;    db 0
are_sprites_evaled:;  db 0
sp0_this_line:; db 0

align(4)

end_low_page()

begin_bss()
align(32)
ppu_ram:; fill 0x800

oam:; fill 0x100

align(64)
working_rgb_palette:; fill 32*2
palette_ram:; fill 32

align(8)
num_sprites_line:; fill 240
align(8)
sprites_line:; fill 8*240

align(8)
ppu_catchup_current_cycle:; dd 0
ppu_catchup_ra:; dw 0

align(4)
conv_pos:;      dw 0
bg_pat_pos:;    dw 0
sp_pat_pos:;    dw 0

bg_atr_pos:;    dw 0
sp_atr_pos:;    dw 0
sp_x_pos:;      dw 0

scanline_counter_hook:; dw 0
ppu_frame_count:; dw 0

conv_write_cached:; db 0

align(4)

end_bss()

scope PPU {

constant idle_pixels(1)
constant tile_pixels(8)
constant sprite_fetch_pixels(tile_pixels*8)
constant bg_prefetch_tiles(2)
constant bg_prefetch_pixels(tile_pixels*bg_prefetch_tiles)
constant bg_fetch_tiles(34)
constant bg_dummy_nt_pixels(4)
constant visible_pixels(256)
constant hblank_pixels(sprite_fetch_pixels+bg_prefetch_pixels+bg_dummy_nt_pixels)
constant scanline_pixels(idle_pixels+visible_pixels+hblank_pixels)
constant vblank_delay(1)

Init:
  addi sp, 8
  sw ra, -8(sp)

// Init vars
  lli ppu_vaddr, 0
  sw r0, ppu_catchup_cb (r0)
  sh r0, ppu_scroll (r0)
  sb r0, ppu_fine_x_scroll (r0)
  sb r0, ppu_scroll_latch (r0)
  sb r0, ppu_read_buffer (r0)
  sb r0, ppu_ctrl (r0)
  sb r0, ppu_mask (r0)
  sb r0, ppu_status (r0)
  sb r0, cur_scanline (r0)
  sb r0, odd_frame (r0)
  sb r0, oam_addr (r0)
  ls_gp(sw r0, scanline_counter_hook)
  la t0, rgb_palette0
  ls_gp(sb r0, conv_write_cached)
  ls_gp(sw r0, frames_finished)
  ls_gp(sw r0, ppu_frame_count)

if {defined MAPPER9} {
  ls_gp(sh r0, mapper9_latch0)
}
if {defined MAPPER10} {
  ls_gp(sb r0, mapper10_latch + 0)
  ls_gp(sb r0, mapper10_latch + 1)
}

// Clear VRAM
  lli t0, 0x800
  la t1, ppu_ram
-
  sd r0, 0 (t1)
  addi t0, -8
  bnez t0,-
  addi t1, 8

// Clear OAM
  lli t0, 0x100
  la t1, oam
-
  sd r0, 0 (t1)
  addi t0, -8
  bnez t0,-
  addi t1, 8

// Clear CHR RAM
  lli t0, 0x2000
  la t1, chrram
-
  sd r0, 0 (t1)
  addi t0, -8
  bnez t0,-
  addi t1, 8

// Clear palette RAM
  ls_gp(sd r0, palette_ram + 0)
  ls_gp(sd r0, palette_ram + 8)

// Clear RGB palette and blank palette
  la_gp(t4, working_rgb_palette)
  la t1, rgb_palette0
  sh r0, 0 (t1)
  sh r0, 0x20*2 (t1)
  sh r0, 0x20*4 (t1)
  sh r0, 0x20*6 (t1)
  sh r0, 0 (t4)

  lli t0, 0x0001
  lli t2, 31
-
  sh t0, 2 (t1)
  sh r0, 2 + 0x20*2 (t1)
  sh t0, 2 + 0x20*4 (t1)
  sh r0, 2 + 0x20*6 (t1)
  sh t0, 2 (t4)
  addi t4, 2
  addi t2, -1
  bnez t2,-
  addi t1, 2

  la t1, rgb_palette0
  la t0, 0x20*8/DCACHE_LINE
-
  cache data_hit_write_back, 0(t1)
  addi t0, -1
  bnez t0,-
  addi t1, DCACHE_LINE

  la a0, 0
  la_gp(a1, FrameLoop)
  jal Scheduler.ScheduleTaskFromNow
  lli a2, ppu_task

  jal SetConvertPos
  lli a0, 0

  jal StartFrame
  ls_gp(sb r0, conv_dst_idx)

  lw ra, -8(sp)
  jr ra
  addi sp, -8

// a0 = 0 to reset, 1 to advance
SetConvertPos:
  lli t3, 0
  la t2, conv_src_buffer
  beqz a0,+
  ls_gp(lw t1, conv_pos)

  ls_gp(lbu t3, conv_write_cached)
  addi t3, 1
  lli t0, num_conv_buffers
  beq t3, t0, SetConvertPos
  lli a0, 0
  la t2, conv_src_size
  add t2, t1
+
  ls_gp(sb t3, conv_write_cached)
  lui t0, SP_MEM_BASE
  sw t3, SP_DMEM + dmem_conv_buf_write (t0)
  ls_gp(sw t2, conv_pos)

  addi t0, t2, src_bg_pat
  ls_gp(sw t0, bg_pat_pos)

  addi t0, t2, src_sp_pat
  ls_gp(sw t0, sp_pat_pos)

  addi t0, t2, src_bg_atr
  ls_gp(sw t0, bg_atr_pos)

  addi t0, t2, src_sp_atr
  ls_gp(sw t0, sp_atr_pos)

  addi t0, t2, src_sp_x
  ls_gp(sw t0, sp_x_pos)

  jr ra
  nop

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
  sd t2, 0x30 (t4)
  sd t3, 0x38 (t4)
  cache data_hit_write_back, 0x30 (t4)

  ls_gp(lw t0, ppu_frame_count)
  addi t0, 1
  ls_gp(sw t0, ppu_frame_count)

  sb r0, are_sprites_evaled (r0)
// pre-render scanline
  daddi cycle_balance, idle_pixels * ppu_div

// Clear vblank, sp0, overflow in status and clear NMI
  lbu t0, ppu_status (r0)
  sb r0, nmi_pending (r0)
  andi t0, 0b0001'1111
  sb t0, ppu_status (r0)

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
  daddi cycle_balance, sprite_fetch_pixels * ppu_div

sprites_enabled:
// ##### Precompute what sprites end up on what lines.

  daddi cycle_balance, sprite_fetch_pixels * ppu_div
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
if {defined MAPPER10} {
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

if {defined MAPPER9} {
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

if {defined MAPPER9} {
  jal Mapper9Latch0
  ls_gp(lhu t0, mapper9_latch0)
}
if {defined MAPPER10} {
  ls_gp(lbu t0, mapper10_latch + 0)
  jal Mapper10Latch
  lli t1, 0x0000

  ls_gp(lbu t0, mapper10_latch + 1)
  jal Mapper10Latch
  lli t1, 0x1000
}


// Scanline counter, just before prefetch seems like the right place for this,
// for MMC3 at least.
  ls_gp(lw t1, scanline_counter_hook)
  lbu t0, ppu_mask (r0)
  beqz t1,+
  andi t0, 0b0001'1000
  beqz t0,+
  nop
  jalr t1
  nop
// Any IRQ will be observed by the CPU at the start of visible pixels.
// TODO consider different combinations of pattern tables, 8x16 sprites, 2006 clocking...
+

// ##### Fetch background
// TODO This really belongs at the start of visible pixels
  daddi cycle_balance, bg_dummy_nt_pixels * ppu_div

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

// Sprite 0 hit
// FIXME fake sp0, assumes we hit on sp0 X if any pixel in sp0 is solid
  lbu t0, sp0_this_line (r0)
  beqz t0, sp0_set_done
  nop

  lbu t0, ppu_status (r0)
  ls_gp(lbu t1, oam + 3) // sprite 0 X
  andi t0, 0b0100'0000
  bnez t0, sp0_set_done
  nop

  ppu_mul(t1, t2)
  daddi cycle_balance, bg_prefetch_tiles * tile_pixels * ppu_div
  dadd cycle_balance, t1

  bgezal cycle_balance, Scheduler.Yield
  nop

  lbu t0, ppu_status (r0)
  ls_gp(lbu t1, oam + 3) // sprite 0 X
  ori t0, 0b0100'0000
  sb t0, ppu_status (r0)

  ppu_mul(t1, t2)
  dsub cycle_balance, t1
sp0_set_done:

  daddi cycle_balance, (bg_fetch_tiles * tile_pixels) * ppu_div

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

if {defined MAPPER9} || {defined MAPPER10} {
  lli t1, 0xfd
  beq t0, t1,+
  lli t1, 0xfe
  bne t0, t1,++
  nop
+
  addi sp, 16
  sw t3, -8 (sp)
  sd t2, -16 (sp)
if {defined MAPPER9} {
  jal Mapper9Latch1
  nop
}
if {defined MAPPER10} {
  jal Mapper10Latch
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
if {defined MAPPER9} || {defined MAPPER10} {
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
if {defined MAPPER9} {
  jal Mapper9Latch1
  nop
}
if {defined MAPPER10} {
  lbu t1, ppu_ctrl (r0)
  andi t1, 0b1'0000
  jal Mapper10Latch
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
  jal SetConvertPos
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
  sb t1, nmi_pending (r0)

  la t0, (vblank_lines * scanline_pixels - vblank_delay) * ppu_div
  dadd cycle_balance, t0
  bgezal cycle_balance, Scheduler.Yield
  nop

  j FrameLoop
  nop
}

WriteCtrl:
// In: cpu_t0
  lbu t0, ppu_ctrl (r0)

// Nametable select
  lhu t2, ppu_scroll (r0)
  andi t3, cpu_t0, 0b11
  andi t2, (0b11 << 10) ^ 0x7fff
  sll t3, 10
  or t2, t3
  sh t2, ppu_scroll (r0)

// NMI
  xor t1, t0, cpu_t0
  andi t1, 0b1000'0000
  beqz t1,+
  sb cpu_t0, ppu_ctrl (r0)

// NMI flag changed, set/clear nmi_pending
  lbu t1, ppu_status (r0)
  and t0, cpu_t0, t1
  andi t0, 0b1000'0000
  sb t0, nmi_pending (r0)
+
  jr ra
  nop

WriteScroll:
// In: cpu_t0
  lbu t1, ppu_scroll_latch (r0)
  lhu t0, ppu_scroll (r0)
  xori t2, t1, 1
  bnez t1,+
  sb t2, ppu_scroll_latch (r0)

// First write, X
  andi t0, 0b111'1111'1110'0000
  srl t1, cpu_t0, 3
  or t0, t1
  sh t0, ppu_scroll (r0)

  andi t1, cpu_t0, 0b111
  jr ra
  sb t1, ppu_fine_x_scroll (r0)

+
// Second write, Y
  andi t0, 0b000'1100'0001'1111
  sll t1, cpu_t0, 2
  andi t1, 0b000'0011'1110'0000
  or t0, t1
  sll t1, cpu_t0, 12
  andi t1, 0b111'0000'0000'0000
  or t0, t1

  jr ra
  sh t0, ppu_scroll (r0)

WriteAddr:
// In: cpu_t0
  lbu t1, ppu_scroll_latch (r0)
  lhu t0, ppu_scroll (r0)
  xori t2, t1, 1
  bnez t1,+
  sb t2, ppu_scroll_latch (r0)

// First write, high
  andi t0, 0x00ff
  andi t1, cpu_t0, 0b111'1111
  sll t1, 8
  or t0, t1
  jr ra
  sh t0, ppu_scroll (r0)

+
// Second write, low
  andi t0, 0x7f00
  or t0, cpu_t0
  move ppu_vaddr, t0
  jr ra
  sh t0, ppu_scroll (r0)

WriteData:
if {defined LOG_PPU_DATA} {
  addi sp, 8
  sw ra, -8 (sp)

  jal PrintStr0
  la_gp(a0, ppu_data_write_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, ppu_data_arrow_msg)

  move a0, ppu_vaddr
  jal PrintHex
  lli a1, 4

  jal NewlineAndFlushDebug
  nop

  lw ra, -8 (sp)
  addi sp, -8
}

// In: cpu_t0
  lbu t1, ppu_ctrl (r0)
  move t0, ppu_vaddr
  andi t1, 0b0100 // increment
  beqz t1,+
  addi ppu_vaddr, 1
  addi ppu_vaddr, 31
+
  andi ppu_vaddr, 0x7fff

  andi t0, 0x3fff
  srl t1, t0, 10
  sll t1, 2
  lw t1, ppu_map (t1)
  addi t3, t0, -0x3f00
  bltz t3, done_write_data
  add t1, t0
// Palette
// TODO do palette writes also go to the underlying nametable?

  andi t0, 0x1f
  andi t2, cpu_t0, 0x3f
  sll t2, 1
  add t2, gp
  lli t4, 0xffff
  lhu t4, rgb_palette_lut - gp_base (t2)

  la_gp(t1, working_rgb_palette)
  sll t2, t0, 1
  add t1, t2

  andi t2, t0, 0b11
  bnez t2,+
  add t3, t0, gp

  xori t1, 0b1'0000<<1

// Background, mirror to the other one
// Alpha = 0
  xori t2, t0, 0b1'0000
  andi t4, 0xfffe
  sh t4, 0 (t1)
  add t2, gp
  sb cpu_t0, palette_ram - gp_base (t2)
  xori t1, 0b1'0000<<1
+
  sh t4, 0 (t1)

  jr ra
  sb cpu_t0, palette_ram - gp_base (t3)

done_write_data:
  jr ra
  sb cpu_t0, 0 (t1)

WriteOAM:
// In: cpu_t0
  lbu t2, oam_addr (r0)
  addi t3, gp, oam - gp_base
  addi t1, t2, 1
  andi t1, 0xff
  sb t1, oam_addr (r0)
  add t2, t3
  jr ra
  sb cpu_t0, 0 (t2)

ReadStatus:
// Out: cpu_t1
  sb r0, ppu_scroll_latch (r0)
  lbu cpu_t1, ppu_status (r0)
// NMI may have been asserted, clear it
  sb r0, nmi_pending (r0)
  andi t0, cpu_t1, 0b0111'1111
  jr ra
  sb t0, ppu_status (r0)

ReadData:
// Out: cpu_t1
  lbu t1, ppu_ctrl (r0)
  move t0, ppu_vaddr
  andi t1, 0b0100 // increment
  beqz t1,+
  addi ppu_vaddr, 1
  addi ppu_vaddr, 31
+
  andi ppu_vaddr, 0x7fff

  andi t0, 0x3fff
  srl t1, t0, 10
  sll t1, 2
  lw t1, ppu_map (t1)

  lbu cpu_t1, ppu_read_buffer (r0)
  add t1, t0
  lbu t1, 0 (t1)

  addi t2, t0, -0x3f00
  bltz t2,+
  andi t3, t0, 0x1f
  add t3, gp

  lbu cpu_t1, palette_ram - gp_base (t3)
+
  jr ra
  sb t1, ppu_read_buffer (r0)

OAMDMA:
// In: cpu_t0
  sll t0, cpu_t0, 2
  lw t1, cpu_read_map (t0)
  sll t0, cpu_t0, 8
  add t0, t1

  lbu t2, oam_addr (r0)
  addi t3, gp, oam - gp_base

  move t1, t2
-
  lbu t4, 0 (t0)
  add t8, t1, t3
  sb t4, 0 (t8)
  addi t1, 1
  andi t1, 0xff
  bne t1, t2,-
  addi t0, 1

  jr ra
  sb r0, are_sprites_evaled (r0)
}

include "ppu_tables.asm"

if {defined LOG_PPU_DATA} {
ppu_data_write_msg:
  db "PPUDATA ",0
ppu_data_arrow_msg:
  db " -> ",0
}
if {defined LOG_SPRITES} {
sprites_colon_msg:
  db ": ",0
}

align(4)
