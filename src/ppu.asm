//define LOG_PPU_DATA()
//define LOG_VRAM_ADDR()
//define LOG_SPRITES()
//define DUMP_RGB_PALETTE()
//define DUMP_VRAM()

begin_low_page()

align_dcache()

// 0x0000-0x4000 in 0x400 (1K, >>10) pages
ppu_map:;     fill 4*16

align(8)
ppu_bg32_pat_lines:;  dd 0,0
ppu_bg32_atr_lines:;  dd 0
ppu_bg_x_lines:; dd 0
ppu_sp_pri:;  dd 0
ppu_sp0_cycle:; dd 0

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

ppu_frame_count:; dw 0

conv_write_cached:; db 0

align(4)

end_bss()

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

begin_overlay_region(ppu_overlay)
begin_overlay(base)
scope ppu_base {
include "ppu_task.asm"
}

begin_overlay(mmc2)
scope ppu_mmc2 {
define PPU_MMC2()
include "ppu_task.asm"
}

begin_overlay(mmc3)
scope ppu_mmc3 {
define PPU_MMC3()
include "ppu_task.asm"
}

begin_overlay(mmc4)
scope ppu_mmc4 {
define PPU_MMC4()
include "ppu_task.asm"
}

end_overlay_region()

scope PPU {
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
  la t0, rgb_palette0
  ls_gp(sb r0, conv_write_cached)
  ls_gp(sw r0, frames_finished)
  ls_gp(sw r0, ppu_frame_count)

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

  load_overlay_from_rom(ppu_overlay, base)

  la a0, 0
  la_gp(a1, ppu_base.FrameLoop)
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

// NMI flag changed, set nmi_pending if newly enabled
  lbu t1, ppu_status (r0)
  and t0, cpu_t0, t1
  andi t0, 0b1000'0000
  beqz t0,+
  srl t0, 7-1
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

  ld t1, ppu_sp0_cycle (r0)
  sb r0, ppu_scroll_latch (r0)
// Check for sp0 hit
  bltz t1,+
  lbu cpu_t1, ppu_status (r0)
  ld t0, target_cycle (r0)
  dadd t0, cycle_balance
  dsub t0, t1
  bltz t0,+
  daddi t0, r0, -1
  ori cpu_t1, 0b0100'0000 // sp0 hit
  sd t0, ppu_sp0_cycle (r0)
+

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
