// Mapper 5: MMC5, ExROM

//define LOG_MMC5()

constant mmc5_mode_3_chrrom_page_shift(10) // 1K

// A minimal implementation:
// - PRG mode 2 and 3
// - no WRAM
// - CHR mode 3
// - no sound

scope Mapper5: {
Init:
  addi sp, 8
  sw ra, -8 (sp)

// Init vars
  ls_gp(sd r0, mmc5_chr_5120_7)
  ls_gp(sw r0, mmc5_prg_5113_6)
  lli t0, 0xff
  ls_gp(sb t0, mmc5_prg_5117)
  ls_gp(sb r0, mmc5_irq_enabled)
  ls_gp(sb r0, mmc5_in_frame)
  ls_gp(sb r0, mmc5_extended_ram_mode)

// Init TLB
// These 4 8K pages should be adjacent in virtual address and TLB index space,
// so only the first address and index is stored.

// 8K page for 0x8000-0xa000
  jal TLB.AllocateVaddr
  lli a0, 0x2000
  ls_gp(sw a0, mmc5_prgrom_vaddr)
  ls_gp(sb a1, mmc5_prgrom_tlb_index)

// 8K page for 0xa000-0xc000
  jal TLB.AllocateVaddr
  lli a0, 0x2000

// 8K page for 0xc000-0xe000
  jal TLB.AllocateVaddr
  lli a0, 0x2000

// 8K page for 0xe000-0x1'0000
  jal TLB.AllocateVaddr
  lli a0, 0x2000

// Map PRG
  ls_gp(lw t0, mmc5_prgrom_vaddr)
  addi t0, -0x8000
  lli t2, 0
  lli t3, 0x80

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  addi t3,-1
  bnez t3,-
  addi t2, 4

// Map config register page
// TODO 0x50
  la_gp(t1, Write51Mode3)
  sw t1, cpu_write_map + 0x51 * 4 (r0)
  la_gp(t1, Write52)
  sw t1, cpu_write_map + 0x52 * 4 (r0)
  la_gp(t1, Read52)
  sw t1, cpu_read_map + 0x52 * 4 (r0)

// Map extended RAM into CPU at 0x5c00-0x6000
  la t0, (four_screen_ram & rdram_mask) + tlb_rdram - 0x5c00
  lli t1, (4-1) * 4
-
  sw t0, cpu_read_map + 0x5c * 4 (t1)
  sw t0, cpu_write_map + 0x5c * 4 (t1)
  bnez t1,-
  addi t1, -4

// Initial PRG setup
  jal PRG_Mode23_E
  lli cpu_t0, 0xff

// Initial BG CHR setup
  ls_gp(lw t0, chrrom_start)
  ls_gp(sw t0, mmc5_pattern_map + 0*4)
  ls_gp(sw t0, mmc5_pattern_map + 1*4)
  ls_gp(sw t0, mmc5_pattern_map + 2*4)
  ls_gp(sw t0, mmc5_pattern_map + 3*4)
  addi t0, -0x1000
  ls_gp(sw t0, mmc5_pattern_map + 4*4)
  ls_gp(sw t0, mmc5_pattern_map + 5*4)
  ls_gp(sw t0, mmc5_pattern_map + 6*4)
  ls_gp(sw t0, mmc5_pattern_map + 7*4)

// Load our hooked PPU
  load_overlay_from_rom(ppu_overlay, mmc5)
  la a0, 0
  la_gp(a1, ppu_mmc5.FrameLoop)
  jal Scheduler.ScheduleTaskFromNow
  lli a2, ppu_task

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

Write51Mode2:
if {defined LOG_MMC5} {
  addi sp, 8
  sw ra, -8(sp)

  jal PrintStr0
  la_gp(a0, mmc5_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, mmc5_arrow_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

  jal NewlineAndFlushDebug
  nop

  lw ra, -8(sp)
  addi sp, -8
}
  lli t1, 0x5113
  beq cpu_t1, t1, PRG_Mode23_6
  lli t1, 0x5115
  beq cpu_t1, t1, PRG_Mode2_8_A
  lli t1, 0x5116
  beq cpu_t1, t1, PRG_Mode23_C
  lli t1, 0x5117
  beq cpu_t1, t1, PRG_Mode23_E
  nop
  j Write51Common // tail call
  nop

Write51Mode3:
// cpu_t0: value
// cpu_t1: address
if {defined LOG_MMC5} {
  addi sp, 8
  sw ra, -8(sp)

  jal PrintStr0
  la_gp(a0, mmc5_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, mmc5_arrow_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

  jal NewlineAndFlushDebug
  nop

  lw ra, -8(sp)
  addi sp, -8
}
  lli t1, 0x5113
  beq cpu_t1, t1, PRG_Mode23_6
  lli t1, 0x5114
  beq cpu_t1, t1, PRG_Mode3_8
  lli t1, 0x5115
  beq cpu_t1, t1, PRG_Mode3_A
  lli t1, 0x5116
  beq cpu_t1, t1, PRG_Mode23_C
  lli t1, 0x5117
  beq cpu_t1, t1, PRG_Mode23_E
  nop

Write51Common:
  lli t1, 0x5100
  beq cpu_t1, t1, PRG_Mode
  nop

// The rest of these registers affect rendering, catchup the PPU
  lw t1, ppu_catchup_cb (r0)
  // delay slot?
  beqz t1,+
  nop // delay slot?
  sw ra, cpu_rw_handler_ra (r0)
  jalr t1
  nop
  lw ra, cpu_rw_handler_ra (r0)
+

  subi a0, cpu_t1, 0x5120
  bltz a0,+
  subi t1, cpu_t1, 0x5128
  bltz t1, CHR_Sprite_Mode3_Bank
  subi t1, cpu_t1, 0x512c
  bltz t1, CHR_BG_Mode3_Bank
+
  lli t1, 0x5105
  beq cpu_t1, t1, Nametable
  lli t1, 0x5101
  beq cpu_t1, t1, CHR_Mode
  lli t1, 0x5104
  bne cpu_t1, t1,+
  nop
// TODO maybe should affect 0x5c00 access?
  andi t0, cpu_t0, 0b11
  ls_gp(sb t0, mmc5_extended_ram_mode)
+

// unimplemented, syscall?
  jr ra
  nop

PRG_Mode:
  andi t0, cpu_t0, 0b11
  lli t1, 2
  beq t0,t1,PRG_Switch_Mode2
  lli t1, 3
  beq t0,t1,PRG_Switch_Mode3
  nop

  jal PrintStr0
  la_gp(a0, mmc5_unimplemented_prg_msg)

  jal PrintDec
  andi a0, cpu_t0, 0b11

  j DisplayDebugAndHalt
  nop

PRG_Switch_Mode2:
  la_gp(t1, Write51Mode2)
// TODO remap existing banks?
  jr ra
  sw t1, cpu_write_map + 0x51 * 4 (r0)
PRG_Switch_Mode3:
// TODO remap existing banks?
  la_gp(t1, Write51Mode3)
  jr ra
  sw t1, cpu_write_map + 0x51 * 4 (r0)

CHR_Mode:
  andi t0, cpu_t0, 0b11
  lli t1, 3
  beq t0,t1,+
  nop

  jal PrintStr0
  la_gp(a0, mmc5_unimplemented_chr_msg)

  andi a0, cpu_t0, 0b11
  jal PrintHex
  lli a1, 1

  j DisplayDebugAndHalt
  nop
+
  jr ra
  nop

name_table_pages:
  dw ppu_ram
  dw ppu_ram + 0x400
  dw four_screen_ram // rough approximation of internal extended RAM
  dw four_screen_ram + 0x400 // TODO fill mode

Nametable:
  sll t1, cpu_t0, 2

  andi t2, t1, 0b1100
  add t2, gp
  lw t2, name_table_pages - gp_base (t2)
  srl t1, 2
  subi t2, 0x2000
  sw t2, ppu_map + 8*4 (r0)

  andi t2, t1, 0b1100
  add t2, gp
  lw t2, name_table_pages - gp_base (t2)
  srl t1, 2
  subi t2, 0x2400
  sw t2, ppu_map + 9*4 (r0)

  andi t2, t1, 0b1100
  add t2, gp
  lw t2, name_table_pages - gp_base (t2)
  srl t1, 2
  subi t2, 0x2800
  sw t2, ppu_map + 10*4 (r0)

  andi t2, t1, 0b1100
  add t2, gp
  lw t2, name_table_pages - gp_base (t2)
  subi t2, 0x2c00
  sw t2, ppu_map + 11*4 (r0)

  jr ra
  nop

PRG_Mode23_6:
// TODO
  jr ra
  nop

PRG_Mode2_8_A:
  addi sp, 8
  sw ra, -8 (sp)

  andi a1, cpu_t0, 0b1111'1110
  jal MMC5Set8KPRGBank
  lli a0, 0

  lw ra, -8 (sp)
  addi sp, -8

  ori a1, cpu_t0, 1
  j MMC5Set8KPRGBank // tail call
  lli a0, 1

PRG_Mode3_8:
  move a1, cpu_t0
  j MMC5Set8KPRGBank // tail call
  lli a0, 0

PRG_Mode3_A:
  move a1, cpu_t0
  j MMC5Set8KPRGBank // tail call
  lli a0, 1

PRG_Mode23_C:
  move a1, cpu_t0
  j MMC5Set8KPRGBank // tail call
  lli a0, 2

PRG_Mode23_E:
  move a1, cpu_t0
  j MMC5Set8KPRGBank // tail call
  lli a0, 3

CHR_Sprite_Mode3_Bank:
// a0: 1K pattern page index
// cpu_t0: 1K bank to use
  ls_gp(lw t0, chrrom_start)
  ls_gp(lwu t2, chrrom_mask)
  sll t3, a0, 2
  sll a0, 10 // 1K page
  sub t0, a0
  sll t1, cpu_t0, mmc5_mode_3_chrrom_page_shift
  and t1, t2
  add t0, t1
  jr ra
  sw t0, ppu_map (t3)

CHR_BG_Mode3_Bank:
// a0: 1K pattern page index (8: 0x0000-0x0400 + 0x1000-0x1400, etc)
// cpu_t0: 1K bank to use
// TODO set a flag for PPU I/O?
//  lbu t1, ppu_ctrl (r0)
  ls_gp(lw t0, chrrom_start)
//  andi t1, 0b10'0000
//  bnez  t1,+
  ls_gp(lwu t2, chrrom_mask)
//  // writes here are ignored in 8x8 mode
//  jr ra
//+
  subi a0, 8
  sll t3, a0, 2
  add t3, gp
  sll a0, 10 // 1K page
  sub t0, a0
  sll t1, cpu_t0, mmc5_mode_3_chrrom_page_shift
  and t1, t2
  add t0, t1
  sw t0, mmc5_pattern_map - gp_base (t3)
// technically only need the above, but store the offset mirror to simplify the PPU task
// TODO: need to be able to disable this when switching out of 8x16 mode?
  subi t0, 0x1000
  jr ra
  sw t0, mmc5_pattern_map - gp_base + 0x1000/0x400*4 (t3)

MMC5Set8KPRGBank:
// a0: 8K page index (0: 0x8000-0xa000, 1: 0xa000-0xc000, etc)
// a1: 8K bank to use
// TODO set a flag for PPU I/O?
  ls_gp(lbu t3, mmc5_prgrom_tlb_index)
  ls_gp(lwu t1, prgrom_mask)
  add t3, a0
  ls_gp(lw t0, mmc5_prgrom_vaddr)
  sll t2, a1, 13 // 8K
  ls_gp(lw a1, prgrom_start_phys)
  and t1, t2
  add a1, t1

  sll a0, 13 // 8K
  add a0, t0

// Tail call
  j TLB.Map8K
  mtc0 t3, Index

Read52:
// cpu_t1: address
// return value in cpu_t1
  lli t1, 0x5204
  beq cpu_t1, t1, ReadIRQ
  nop

  jr ra
  lli cpu_t1, 0 // TODO open bus?

ReadIRQ:
  lbu t0, irq_pending (r0)
  andi t1, t0, 0xff^intMapper
  sb t1, irq_pending (r0)
  andi t0, intMapper
  beqz t0,+
  ls_gp(lbu cpu_t1, mmc5_in_frame)
  ori cpu_t1, 0b1000'0000 // IRQ pending
+
  jr ra
  nop

Write52:
// cpu_t0: value
// cpu_t1: address
  lli t1, 0x5203
  beq cpu_t1, t1, WriteScanlineCompare
  lli t1, 0x5204
  beq cpu_t1, t1, WriteIRQ
  nop

  jr ra
  nop

ScanlineCounter:
  lbu t1, ppu_mask (r0)
  ls_gp(lbu t0, mmc5_in_frame)
  andi t1, 0b0001'1000
  bnez t1,+
  ls_gp(lbu t2, mmc5_irq_enabled)

// rendering disabled, clear in-frame
  j Scheduler.FinishTask
  ls_gp(sb r0, mmc5_in_frame)
+

  bnez t0,+
  ls_gp(lbu t1, mmc5_irq_scanline)

// in-frame becomes true:
// init scanline counter, set in-frame, clear pending IRQ
  lbu t1, irq_pending (r0)
  lli t0, 0b0100'0000
  ls_gp(sb t0, mmc5_in_frame)
  andi t1, 0xff^intMapper
  sb t1, irq_pending (r0)
  j Scheduler.FinishTask
  ls_gp(sb r0, mmc5_cur_scanline)
+

  ls_gp(lbu t0, mmc5_cur_scanline)
  andi t2, 0b1000'0000
  addi t0, 1
  beqz t2,+
  ls_gp(sb t0, mmc5_cur_scanline)
  bne t0, t1,+
  lbu t0, irq_pending (r0)
  ori t0, intMapper
  sb t0, irq_pending (r0)
+

  j Scheduler.FinishTask
  nop

ClearInFrameAndIRQ:
// clear in-frame, clear pending IRQ
  lbu t0, irq_pending (r0)
  ls_gp(sb r0, mmc5_in_frame)
  andi t0, 0xff^intMapper
  jr ra
  sb t0, irq_pending (r0)

WriteScanlineCompare:
  jr ra
  ls_gp(sb cpu_t0, mmc5_irq_scanline)

WriteIRQ:
  jr ra
  ls_gp(sb cpu_t0, mmc5_irq_enabled)
}

begin_bss()
align(8)
mmc5_chr_5120_7:; dd 0
mmc5_prg_5113_6:; dw 0


mmc5_pattern_map:; dw 0,0,0,0,0,0,0,0

mmc5_prgrom_vaddr:; dw 0

mmc5_prgrom_tlb_index:; db 0
mmc5_prg_5117:; db 0
mmc5_cur_scanline:; db 0
mmc5_irq_scanline:; db 0
mmc5_irq_enabled:; db 0
mmc5_in_frame:; db 0
mmc5_extended_ram_mode:; db 0

align(4)
end_bss()

if {defined LOG_MMC5} {
mmc5_msg:
  db "MMC5 write: ",0
mmc5_arrow_msg:
  db " -> ",0
}

mmc5_unimplemented_prg_msg:
  db "Unsupported MMC5 PRG mode: ",0
mmc5_unimplemented_chr_msg:
  db "Unsupported MMC5 CHR mode: ",0

align(4)
