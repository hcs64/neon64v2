// Mapper 69: Sunsoft FME-7, A, B

constant sunsoft_prgrom_page_shift(13) // 8K
constant sunsoft_chrrom_page_shift(10) // 1K

scope Mapper69: {
Init:
  addi sp, 8
  sw ra, -8 (sp)

// Init TLB
// These 5 8K pages should be adjacent in virtual address and TLB index space,
// so only the first address and index is stored.

// 8K page for 0x6000-0x8000
  jal TLB.AllocateVaddr
  lli a0, 0x2000
  ls_gp(sw a0, sunsoft_prgrom_vaddr)
  ls_gp(sb a1, sunsoft_prgrom_tlb_index)

// 8K page for 0x8000-0xa000
  jal TLB.AllocateVaddr
  lli a0, 0x2000

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
  ls_gp(lw t0, sunsoft_prgrom_vaddr)
  la_gp(t1, WriteCommand)
  la_gp(t4, WriteParameter)
  la_gp(a0, WriteAudio)
  addi t0, -0x6000
  lli t2, 0
  lli t3, 0x20
-
  sw t0, cpu_read_map + 0x60 * 4 (t2)
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t0, cpu_read_map + 0xa0 * 4 (t2)
  sw t0, cpu_read_map + 0xc0 * 4 (t2)
  sw t0, cpu_read_map + 0xe0 * 4 (t2)

  sw t0, cpu_write_map + 0x60 * 4 (t2)
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  sw t4, cpu_write_map + 0xa0 * 4 (t2)
  sw a0, cpu_write_map + 0xc0 * 4 (t2)
  sw a0, cpu_write_map + 0xe0 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

// Init the pages to 0
  lli a1, 0
  jal SetPRGROMBank
  lli a0, 0

  lli a1, 0
  jal SetPRGROMBank
  lli a0, 1

  lli a1, 0
  jal SetPRGROMBank
  lli a0, 2

  lli a1, 0
  jal SetPRGROMBank
  lli a0, 3

// Map the fixed bank
  ls_gp(lbu a1, prgrom_page_count)
  sll a1, prgrom_page_shift - sunsoft_prgrom_page_shift // 16K pages to 8K pages
  addi a1, -1
  jal SetPRGROMBank
  lli a0, 4

  ls_gp(sb r0, sunsoft_irq_control)
  ls_gp(sb r0, sunsoft_irq_count)

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

WriteCommand:
  andi t0, cpu_t0, 0xf
  jr ra
  ls_gp(sb t0, sunsoft_command)

WriteParameter:
  ls_gp(lbu t0, sunsoft_command)
// delay slot?
  sll t1, t0, 2
  add t1, gp
  lw t1, command_jump_table - gp_base (t1)
// delay slot?
  jr t1
  nop

WriteAudio:
// unimplemented
  jr ra
  nop

CmdIRQLow:
  ls_gp(lbu t0, sunsoft_irq_control)
  j ScheduleIRQ
  ls_gp(sb cpu_t0, sunsoft_irq_count+1)

CmdIRQHigh:
  ls_gp(lbu t0, sunsoft_irq_control)
  j ScheduleIRQ
  ls_gp(sb cpu_t0, sunsoft_irq_count+0)

CmdIRQControl:
// ack interrupt
  lbu t0, irq_pending (r0)
  ls_gp(sb cpu_t0, sunsoft_irq_control)
  andi t0, 0xff^intMapper
  sb t0, irq_pending (r0)

  move t0, cpu_t0
// fall through

// t0: control
ScheduleIRQ:
  ls_gp(lhu a0, sunsoft_irq_count)
  andi t3, t0, 0x80 // decrement enable -- TODO: track when this gets cleared?
  bnez t3,+
  nop

  daddi t0, r0, -1 // never
  jr ra
  sd t0, task_times + mapper_irq_task * 8 (r0)
+

  cpu_mul(a0, t0)

  la_gp(a1, IRQCallback)
  j Scheduler.ScheduleTaskFromNow // tail call
  lli a2, mapper_irq_task

IRQCallback:
  ls_gp(lbu t0, sunsoft_irq_control)
  ls_gp(sh r0, sunsoft_irq_count)
  andi t0, 1 // IRQ enable
  lbu t1, irq_pending (r0)
  beqz t0,+

  ori t1, intMapper
  sb t1, irq_pending (r0)
+
// TODO: reschedule? assume for now that the timer will be reset manually
  j Scheduler.FinishTask // tail call
  nop


CmdPRGBank0:
// cpu_t0: value
// t0: command (8)
  andi t1, cpu_t0, 0b0100'0000
  beqz t1, CmdPRGBank13
// delay slot
  ls_gp(lbu t3, sunsoft_prgrom_tlb_index)
  ls_gp(lw a0, sunsoft_prgrom_vaddr)
  la a1, nes_extra_ram & 0x1fff'ffff

// Tail call
  j TLB.Map8K
  mtc0 t3, Index

CmdPRGBank13:
// cpu_t0: value
// t0: command (9-0xb)
  andi a1, cpu_t0, 0b11'1111
  subi a0, t0, 8

// fallthrough

SetPRGROMBank:
// a0: page index
// a1: bank index to load
  ls_gp(lbu t3, sunsoft_prgrom_tlb_index)
  ls_gp(lwu t1, prgrom_mask)
  add t3, a0
  sll t2, a1, sunsoft_prgrom_page_shift
  ls_gp(lw a1, prgrom_start_phys)
  and t2, t1
  add a1, t2

  ls_gp(lw t0, sunsoft_prgrom_vaddr)
  sll a0, sunsoft_prgrom_page_shift
  add a0, t0

// TODO: This should be forced read-only for bank 0
// Tail call
  j TLB.Map8K
  mtc0 t3, Index

CmdCHRBank:
// cpu_t0: value (CHR ROM bank)
// t0: command (PPU page 0-7)
  sll t1, t0, sunsoft_chrrom_page_shift
  ls_gp(lw t3, chrrom_mask)
  ls_gp(lw t4, chrrom_start)
  sll t2, cpu_t0, sunsoft_chrrom_page_shift
  and t2, t3
  add t2, t4
  sub t2, t1
  sll t0, 2
  jr ra
  sw t2, ppu_map (t0)

CmdMirror:
// cpu_t0: value (mode)
  andi t0, cpu_t0, 0b11
  sll t0, 2
  add t0, gp
  lw t0, mirror_mode_jump_table - gp_base (t0)
  la_gp(a0, ppu_ram + 0)
  jr t0 // tail call
  la_gp(a1, ppu_ram + 0x400)

mirror_mode_jump_table:
  dw VerticalMirroring, HorizontalMirroring, SingleScreenMirroring, single_1

single_1:
  j SingleScreenMirroring
  move a0, a1

command_jump_table:
  dw CmdCHRBank, CmdCHRBank, CmdCHRBank, CmdCHRBank, CmdCHRBank, CmdCHRBank, CmdCHRBank, CmdCHRBank
  dw CmdPRGBank0, CmdPRGBank13, CmdPRGBank13, CmdPRGBank13
  dw CmdMirror, CmdIRQControl, CmdIRQLow, CmdIRQHigh
}

begin_bss()
align(8)
sunsoft_prgrom_vaddr:; dw 0

sunsoft_irq_count:; dh 0

sunsoft_prgrom_tlb_index:; db 0
sunsoft_command:; db 0
sunsoft_irq_control:; db 0
align(4)
end_bss()
