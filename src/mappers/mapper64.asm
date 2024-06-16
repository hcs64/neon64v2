// Mapper 64: RAMBO-1

scope Mapper64 {
Init:
  addi sp, 8
  sw ra, -8(sp)

  ls_gp(sb r0, rambo_bank_select)
  ls_gp(sd r0, rambo_bank_regs)
  ls_gp(sd r0, rambo_bank_regs + 8)
  ls_gp(sb r0, rambo_irq_enabled)
  ls_gp(sb r0, rambo_irq_counter)
  ls_gp(sb r0, rambo_irq_mode)

// Init TLB
// These 4 8K pages should be adjacent in virtual address and TLB index space,
// so only the first address and index is stored.

// 8K page for 0x8000-0xa000
  jal TLB.AllocateVaddr
  lli a0, 0x2000
  ls_gp(sw a0, rambo_prgrom_vaddr)
  ls_gp(sb a1, rambo_prgrom_tlb_index)

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
  ls_gp(lw t0, rambo_prgrom_vaddr)
  la_gp(t1, WriteMapping)
  la_gp(t4, WriteMirroring)
  la_gp(a0, WriteIRQ_C)
  la_gp(a1, WriteIRQ_E)
  addi t0, -0x8000
  lli t2, 0
  lli t3, 0x20

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t0, cpu_read_map + 0xa0 * 4 (t2)
  sw t0, cpu_read_map + 0xc0 * 4 (t2)
  sw t0, cpu_read_map + 0xe0 * 4 (t2)
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  sw t4, cpu_write_map + 0xa0 * 4 (t2)
  sw a0, cpu_write_map + 0xc0 * 4 (t2)
  sw a1, cpu_write_map + 0xe0 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

// init banks
  lli a0, 0
  jal SetPRGBank
  lli cpu_t0, 0

  lli a0, 1
  jal SetPRGBank
  lli cpu_t0, 0

  lli a0, 2
  jal SetPRGBank
  lli cpu_t0, 0

// hardwire last bank
  ls_gp(lw a0, prgrom_page_count)
  sll cpu_t0, a0, 1 // 16K pages to 8K pages
  lli a0, 3
  jal SetPRGBank
  addi cpu_t0, -1

// Load our hooked PPU
  load_overlay_from_rom(ppu_overlay, rambo)
  la a0, 0
  la_gp(a1, ppu_rambo.FrameLoop)
  jal Scheduler.ScheduleTaskFromNow
  lli a2, ppu_task

  lw ra, -8(sp)
  jr ra
  addi sp, -8

WriteMapping:
  andi t1, cpu_t1, 1
  bnez t1, MappingOdd
  ls_gp(lbu t1, rambo_bank_select)
// Even address, bank select
// TODO handle CHR bank mode changing?
  jr ra
  ls_gp(sb cpu_t0, rambo_bank_select)

MappingOdd:
// t1: bank select
  andi t0, t1, 0b1111
  sll t2, t0, 2
  add t2, gp
  lw t2, BankTable - gp_base (t2)
  add t3, t0, gp
  jr t2
  sb cpu_t0, rambo_bank_regs - gp_base (t3)

BankTable:
  dw Reg0, Reg1, Reg2, Reg3, Reg4, Reg5, Reg6, Reg7
  dw Reg8, Reg9, RegA, RegB, RegC, RegD, RegE, RegF

Reg8:
Reg9:
  lw t2, ppu_catchup_cb (r0)
  beqz t2,+
  nop
  sw ra, cpu_rw_handler_ra (r0)
  jalr t2
  nop

  ls_gp(lbu t1, rambo_bank_select)
  lw ra, cpu_rw_handler_ra (r0)
  andi t0, t1, 0b1111
+

  andi t1, 0b0010'0000 // 1K mode
  beqz t1, RegNop
  andi t0, 1
  sll t0, 11
  j after_R01_shift
  ori t0, 0x400

Reg0:
Reg1:
  lw t2, ppu_catchup_cb (r0)
  beqz t2,+
  nop
  sw ra, cpu_rw_handler_ra (r0)
  jalr t2
  nop

  ls_gp(lbu t1, rambo_bank_select)
  lw ra, cpu_rw_handler_ra (r0)
  andi t0, t1, 0b1111
+

  sll t0, 11
after_R01_shift:

  andi t4, t1, 0b0010'0000 // 1K mode
  andi t1, 0b1000'0000 // A12 inversion
  sll t1, 12-7
  add t1, t0

  bnez t4,+
  move t0, cpu_t0
  andi t0, 0b1111'1110
+
  sll t0, 10

  ls_gp(lwu t2, chrrom_mask)
  ls_gp(lw t3, chrrom_start)
  and t0, t2
  add t0, t3
  sub t0, t1

  srl t1, 10-2
  bnez t4,+
  sw t0, ppu_map (t1)
  sw t0, ppu_map + 4 (t1)
+
  jr ra
  nop

Reg2:
Reg3:
Reg4:
Reg5:
  lw t2, ppu_catchup_cb (r0)
  beqz t2,+
  nop
  sw ra, cpu_rw_handler_ra (r0)
  jalr t2
  nop

  ls_gp(lbu t1, rambo_bank_select)
  lw ra, cpu_rw_handler_ra (r0)
  andi t0, t1, 0b1111
+

  subi t0, 2
  sll t0, 10

  andi t1, 0b1000'0000 // A12 inversion
  xori t1, 0b1000'0000
  sll t1, 12-7
  add t1, t0

  ls_gp(lwu t2, chrrom_mask)
  ls_gp(lw t3, chrrom_start)
  sll t0, cpu_t0, 10 // 1K
  and t0, t2
  add t0, t3
  sub t0, t1

  srl t1, 10-2
  jr ra
  sw t0, ppu_map (t1)

Reg6:
  andi a0, t1, 0b0100'0000
// Tail call
  j SetPRGBank
  srl a0, 6-1 // 0 or 2

Reg7:
// Tail call
  j SetPRGBank
  lli a0, 1

RegF:
  andi a0, t1, 0b0100'0000
  srl a0, 6-1 // 0 or 2
// Tail call
  j SetPRGBank
  xori a0, 2 // 2 or 0

RegNop:
RegA:
RegB:
RegC:
RegD:
RegE:
  jr ra
  nop

WriteMirroring:
  andi t1, cpu_t1, 1
  bnez t1, RegNop
  la_gp(a0, ppu_ram + 0)
  la_gp(a1, ppu_ram + 0x400)
  andi t0, cpu_t0, 1
// Tail call
  bnez t0, HorizontalMirroring
  nop
// Tail call
  j VerticalMirroring
  nop

WriteIRQ_C:
  andi t1, cpu_t1, 1
  bnez t1, IrqMode
  nop
// TODO should writing latch affect anything?
  jr ra
  ls_gp(sb cpu_t0, rambo_irq_latch)
IrqMode:
  andi t0, cpu_t0, 1
  ls_gp(sb t0, rambo_irq_mode)
  beqz t0,+
  ls_gp(sb r0, rambo_irq_counter)

// TODO cycle counter

+
  jr ra
  nop

WriteIRQ_E:
  andi t1, cpu_t1, 1
  bnez t1, IrqEnable
  nop
IrqAck:
  lbu t1, irq_pending (r0)
  ls_gp(sb r0, rambo_irq_enabled)
  andi t1, 0xff^intMapper
  jr ra
  sb t1, irq_pending (r0)
IrqEnable:
  lli t0, 1
  jr ra
  ls_gp(sb t0, rambo_irq_enabled)

SetPRGBank:
// cpu_t0: 8K bank to load
// a0: page index (0-3)
  ls_gp(lbu t3, rambo_prgrom_tlb_index)
  ls_gp(lwu t1, prgrom_mask)
  add t3, a0
  ls_gp(lw t0, rambo_prgrom_vaddr)
  sll t2, cpu_t0, 13 // 8K
  ls_gp(lw a1, prgrom_start_phys)
  and t1, t2
  add a1, t1

  sll a0, 13 // 8K
  add a0, t0

// Tail call
  j TLB.Map8K
  mtc0 t3, Index

ScanlineCounter:
  ls_gp(lbu t0, rambo_irq_counter)
  ls_gp(lbu t1, rambo_irq_latch)

  bnez t0,+
  addi t0, -1
// at zero, reload
  ori t1, 1 // ?
  jr ra
  ls_gp(sb t1, rambo_irq_counter)
+

  bnez t0,+
  ls_gp(sb t0, rambo_irq_counter)
// hit zero
// IRQ if enabled
  ls_gp(lbu t1, rambo_irq_enabled)
  lbu t2, irq_pending (r0)
  beqz t1,+
  ori t2, intMapper
  sb t2, irq_pending (r0)
+
// still counting
  jr ra
  nop
}

begin_bss()
align(8)
rambo_bank_regs:;       dd 0,0

rambo_prgrom_vaddr:;    dw 0


rambo_prgrom_tlb_index:;    db 0
rambo_bank_select:;         db 0
rambo_irq_enabled:;         db 0
rambo_irq_mode:;            db 0
rambo_irq_counter:;         db 0
rambo_irq_latch:;           db 0

align(4)
end_bss()


