// Mapper 19: Namco 129/163

constant namco163_prgrom_page_shift(13) // 8K
constant namco163_chrrom_page_shift(10) // 1K

scope Mapper19: {
Init:
  addi sp, 8
  sw ra, -8 (sp)

// Init TLB
// These 4 8K pages should be adjacent in virtual address and TLB index space,
// so only the first address and index is stored.

// 8K page for 0x8000-0xa000
  jal TLB.AllocateVaddr
  lli a0, 0x2000
  ls_gp(sw a0, namco163_prgrom_vaddr)
  ls_gp(sb a1, namco163_prgrom_tlb_index)

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
  ls_gp(lw t0, namco163_prgrom_vaddr)
  la_gp(t1, WriteCHRSelect) // Some of these will be overwritten below
  addi t0, -0x8000
  lli t2, 0
  lli t3, 0x80
-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

// Map other registers
  la_gp(t0, WriteIRQLow)
  la_gp(t1, WriteIRQHigh)
  la_gp(t2, WritePRG1)
  la_gp(t3, WritePRG2)
  la_gp(t4, WritePRG3)
  la_gp(a1, WriteRAMProtect)
  la_gp(a2, WriteNTSelect)
  lli a0, (8-1) * 4
-
  sw t0, cpu_write_map + 0x50 * 4 (a0)
  sw t1, cpu_write_map + 0x58 * 4 (a0)
  sw a2, cpu_write_map + 0xc0 * 4 (a0)
  sw a2, cpu_write_map + 0xc8 * 4 (a0)
  sw a2, cpu_write_map + 0xd0 * 4 (a0)
  sw a2, cpu_write_map + 0xd8 * 4 (a0)
  sw t2, cpu_write_map + 0xe0 * 4 (a0)
  sw t3, cpu_write_map + 0xe8 * 4 (a0)
  sw t4, cpu_write_map + 0xf0 * 4 (a0)
  sw a1, cpu_write_map + 0xf8 * 4 (a0)
  bnez a0,-
  addi a0, -4

// Map the fixed bank
  ls_gp(lbu a1, prgrom_page_count)
  sll a1, prgrom_page_shift - namco163_prgrom_page_shift // 16K pages to 8K pages
  subi a1, 1
  jal SetPRGBank
  lli a0, 3

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

WriteIRQLow:
// TODO do we need to account for how this changes?

// ack interrupt
  lbu t0, irq_pending (r0)
  andi t0, 0xff^intMapper
  sb t0, irq_pending (r0)

  jr ra
  ls_gp(sb cpu_t0, namco163_irq_low)

WriteIRQHigh:
// ack interrupt
  lbu t0, irq_pending (r0)
  andi t0, 0xff^intMapper
  sb t0, irq_pending (r0)

  andi t0, cpu_t0, 0x80
  beqz t0,+
  ls_gp(sb cpu_t0, namco163_irq_high)

  ls_gp(lbu t1, namco163_irq_low)
  andi a0, cpu_t0, 0x7f
  sll a0, 8
  or a0, t1
  neg a0
  addi a0, 0x7fff

  cpu_mul(a0, t0)

  la_gp(a1, IRQCallback)
  j Scheduler.ScheduleTaskFromNow // tail call
  lli a2, mapper_irq_task

+
  jr ra
  nop

IRQCallback:
// TODO should the counter be disabled when triggered?
  ls_gp(lbu t1, namco163_irq_high)
  lbu t0, irq_pending (r0)
  andi t1, 0x80
  beqz t1,+
  ori t0, intMapper
  sb t0, irq_pending (r0)
+
  j Scheduler.FinishTask
  nop

WritePRG1:
// cpu_t0: value
// cpu_t1: address
  andi a1, cpu_t0, 0b11'1111
  j SetPRGBank // tail call
  lli a0, 0

WritePRG2:
// TODO update banks if this enabled/disabled CHR-RAM
  ls_gp(sb cpu_t0, namco163_e800)
  andi a1, cpu_t0, 0b11'1111
  j SetPRGBank
  lli a0, 1

WritePRG3:
  andi a1, cpu_t0, 0b11'1111
  lli a0, 2

// fallthrough

SetPRGBank:
// a0: page index
// a1: bank index to load
  ls_gp(lbu t3, namco163_prgrom_tlb_index)
  ls_gp(lwu t1, prgrom_mask)
  add t3, a0
  ls_gp(lw t0, namco163_prgrom_vaddr)
  sll t2, a1, namco163_prgrom_page_shift
  ls_gp(lw a1, prgrom_start_phys)
  and t1, t2
  add a1, t1

  sll a0, namco163_prgrom_page_shift
  add a0, t0

// Tail call
  j TLB.Map8K
  mtc0 t3, Index

WriteCHRSelect:
// cpu_t0: value
// cpu_t1: address
  srl t1, cpu_t1, 11

  subi t1, 0x10
  //sll t1, namco163_chrrom_page_shift - 10 // PPU page size

  subi t3, cpu_t0, 0xe0
  ls_gp(lw t2, chrrom_mask)
  sll t0, cpu_t0, namco163_chrrom_page_shift
  and t0, t2
  bltz t3,+
  ls_gp(lw t2, chrrom_start)

// Check if CHR-RAM is enabled for this pattern table
  ls_gp(lbu t3, namco163_e800)
  srl t3, 6
  srl t4, t1, 2 // 4 1K pages per PT
  srlv t3, t4
  andi t3, 1
  bnez t3,+
  nop
// Use internal NT RAM as CHR-RAM
  andi t0, cpu_t0, 1 // bit 0 indicates which NT
  sll t0, 10 // 1K, NT size
  la_gp(t2, ppu_ram)
+
  add t0, t2
  sll t2, t1, 10 // PPU page size
  sub t0, t2

  sll t1, 2
  jr ra
  sw t0, ppu_map (t1)

WriteNTSelect:
// cpu_t0: value
// cpu_t1: address
  andi t2, cpu_t0, 1 // bit 0 indicates which NT
  sll t2, 10 // 1K, NT size
  la_gp(t0, ppu_ram)
  add t0, t2

  srl t1, cpu_t1, 11
  subi t1, 0x10
  sll t2, t1, 10 // PPU page size
  sub t0, t2

  sll t1, 2
  jr ra
  sw t0, ppu_map (t1)

WriteRAMProtect:
  jr ra
  nop

}

begin_bss()
align(8)
namco163_prgrom_vaddr:; dw 0

namco163_prgrom_tlb_index:; db 0
namco163_irq_high:; db 0
namco163_irq_low:; db 0
namco163_e800:; db 0
align(4)
end_bss()
