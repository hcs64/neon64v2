// Mapper 1: MMC1, SxROM

//define LOG_MMC1()

// Since bss doesn't work in a scope, unfortunately it's necessary to prefix
// all variables in order to have multiple variants.

scope Mapper1_{MMC1_VARIANT}: {
Init:
  addi sp, 8
  sw ra, -8(sp)

// Init vars
  ls_gp(sd r0, {MMC1_VARIANT}_last_write_cycle)
  lli t0, 0b1'0000
  ls_gp(sb t0, {MMC1_VARIANT}_shift)
  la t0, 0x1f000000 // mode 3
  ls_gp(sw t0, {MMC1_VARIANT}_regs)

// Init TLB
// Allocate 32K, this will be used either as 2 16K pages or 1 32K page
  jal TLB.AllocateVaddr
  lui a0, 0x1'0000  >> 16 // align 64K to leave a 32K guard unmapped

  ls_gp(sw a0, {MMC1_VARIANT}_prgrom_vaddr)
  ls_gp(sb a1, {MMC1_VARIANT}_prgrom_tlb_index)
if {MMC1_VARIANT} == MMC1_SUROM {
  ls_gp(sb r0, {MMC1_VARIANT}_prg_hi)
}

// Map PRG
  ls_gp(lw t0, {MMC1_VARIANT}_prgrom_vaddr)
  la t1, Write
  addi t0, -0x8000
  lli t2, 0
  lli t3, 0x80

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

// Initialize reg jump table
  la t2, update_ctrl
  ls_gp(sw t2, {MMC1_VARIANT}_write_reg_jump_table+0*4)

// Set up with initial register values
  ls_gp(lbu t0, {MMC1_VARIANT}_regs+0)
  la t1,+
  jr t2
  sw t1, cpu_rw_handler_ra (r0)
+

// TODO: Switchable 32KB PRG RAM
  lw ra, -8(sp)
  jr ra
  addi sp, -8

align(8)
MMC1PrgModes:
  dw MMC1PrgMode01, MMC1PrgMode01, MMC1PrgMode2, MMC1PrgMode3

MMC1PrgMode01:
// 32K
  ls_gp(lbu t0, {MMC1_VARIANT}_regs+3)
  ls_gp(lbu t1, {MMC1_VARIANT}_prgrom_tlb_index)
  ls_gp(lw a0, {MMC1_VARIANT}_prgrom_vaddr)
  mtc0 t1, Index

  ls_gp(lw t1, prgrom_start_phys)
  andi a1, t0, 0b0'1110
  ls_gp(lwu t2, prgrom_mask)
  sll a1, 14 // 16K
if {MMC1_VARIANT} == MMC1_SUROM {
// High bit for 512K SUROM
  ls_gp(lbu t4, {MMC1_VARIANT}_prg_hi)
  andi t4, 0b1'0000
  sll t4, 18-4 // 256K
  or a1, t4
}
  and a1, t2

// Tail call, will return to our ra
  j TLB.Map32K
  add a1, t1

MMC1PrgMode2:
// Fixed low 16K at first PRG ROM bank
  ls_gp(lw a1, prgrom_start_phys)

// Switch high 16K
  ls_gp(lbu a2, {MMC1_VARIANT}_regs+3)
  ls_gp(lbu t1, {MMC1_VARIANT}_prgrom_tlb_index)
  ls_gp(lw a0, {MMC1_VARIANT}_prgrom_vaddr)
  mtc0 t1, Index

  andi a2, 0b0'1111
// TODO high PRG ROM bit in reg 1
  ls_gp(lwu t2, prgrom_mask)
  sll a2, 14 // 16K
if {MMC1_VARIANT} == MMC1_SUROM {
// High bit for 512K SUROM
  ls_gp(lbu t4, {MMC1_VARIANT}_prg_hi)
  andi t4, 0b1'0000
  sll t4, 18-4 // 256K
  or a2, t4
// Also swap fixed bank
  add a1, t4
}
  and a2, t2

// Tail call, will return to our ra
  j TLB.Map16K_2
  add a2, a1

MMC1PrgMode3:
// Fixed high 16K at last PRG ROM bank
  ls_gp(lw a2, prgrom_last_page_phys)

// Switch low 16K
  ls_gp(lbu a1, {MMC1_VARIANT}_regs+3)
  ls_gp(lbu t1, {MMC1_VARIANT}_prgrom_tlb_index)
  ls_gp(lw a0, {MMC1_VARIANT}_prgrom_vaddr)
  mtc0 t1, Index

  ls_gp(lw t2, prgrom_start_phys)
  andi a1, 0b0'1111
  ls_gp(lwu t3, prgrom_mask)
  sll a1, 14 // 16K
if {MMC1_VARIANT} == MMC1_SUROM {
// High bit for 512K SUROM
  ls_gp(lbu t4, {MMC1_VARIANT}_prg_hi)
  andi t4, 0b1'0000
  sll t4, 18-4 // 256K
  or a1, t4

// Also swap fixed bank
  lui t0, 0x4'0000>>16
  xor t4, t0
  sub a2, t4
}
  and a1, t3

// Tail call, will return to our ra
  j TLB.Map16K_2
  add a1, t2

align(8)
MMC1ChrModes:
  dw MMC1Chr0Mode0, MMC1Chr1Mode0, MMC1Chr0Mode1, MMC1Chr1Mode1

MMC1Chr0Mode0:
// 8K bank
  ls_gp(lbu t3, {MMC1_VARIANT}_regs+1)
  ls_gp(lwu t1, chrrom_start)
  ls_gp(lwu t2, chrrom_mask)

  andi t0, t3, 0b1'1110 // ignore low bit
  sll t0, 12  // 4K
  and t0, t2
  dadd t0, t1
  dsll32 t1, t0, 0
  or t0, t1
  sd t0, ppu_map + 0*4 (r0)
  sd t0, ppu_map + 2*4 (r0)
  sd t0, ppu_map + 4*4 (r0)
if {MMC1_VARIANT} == MMC1_SUROM {
  ls_gp(lw t4, {MMC1_VARIANT}_write_reg_jump_table+3*4)
  ls_gp(sb t3, {MMC1_VARIANT}_prg_hi)
// Tail call
  jr t4
} else {
  jr ra
}
  sd t0, ppu_map + 6*4 (r0)

MMC1Chr0Mode1:
// low 4K bank
  ls_gp(lbu t3, {MMC1_VARIANT}_regs+1)
  ls_gp(lw t0, chrrom_start)
  ls_gp(lwu t2, chrrom_mask)
  sll t1, t3, 12  // 4K
  and t1, t2
  add t1, t0
  sw t1, ppu_map + 0*4 (r0)
  sw t1, ppu_map + 1*4 (r0)
  sw t1, ppu_map + 2*4 (r0)
if {MMC1_VARIANT} == MMC1_SUROM {
  ls_gp(lw t4, {MMC1_VARIANT}_write_reg_jump_table+3*4)
  ls_gp(sb t3, {MMC1_VARIANT}_prg_hi)
// Tail call
  jr t4
} else {
  jr ra
}
  sw t1, ppu_map + 3*4 (r0)

MMC1Chr1Mode0:
// Ignored in 8K mode
  jr ra
  nop

MMC1Chr1Mode1:
// high 4K bank
  ls_gp(lbu t3, {MMC1_VARIANT}_regs+2)
  ls_gp(lw t0, chrrom_start)
  ls_gp(lwu t2, chrrom_mask)
  sll t1, t3, 12  // 4K
  and t1, t2
  add t1, t0
  addi t1, -0x1000
  sw t1, ppu_map + 4*4 (r0)
  sw t1, ppu_map + 5*4 (r0)
  sw t1, ppu_map + 6*4 (r0)
if {MMC1_VARIANT} == MMC1_SUROM {
  ls_gp(lw t4, {MMC1_VARIANT}_write_reg_jump_table+3*4)
  ls_gp(sb t3, {MMC1_VARIANT}_prg_hi)
// Tail call
  jr t4
} else {
  jr ra
}
  sw t1, ppu_map + 7*4 (r0)

Write:
// cpu_t0: value
// cpu_t1: address
  sw ra, cpu_rw_handler_ra (r0)

// Ignore second consecutive write
  ld t0, target_cycle (r0)
  ls_gp(ld t1, {MMC1_VARIANT}_last_write_cycle)
  dadd t0, cycle_balance
  dsub t2, t0, t1
  daddi t2, -cpu_div
  blez t2, done
  ls_gp(sd t0, {MMC1_VARIANT}_last_write_cycle)

  ls_gp(lbu t0, {MMC1_VARIANT}_shift)
  andi t1, cpu_t0, 0x80
  beqz t1, not_reset
  andi t2, t0, 1

// High bit set, just reset shift register
  lli t0, 0b1'0000
  j done
  ls_gp(sb t0, {MMC1_VARIANT}_shift)

not_reset:
  andi t1, cpu_t0, 1
  sll t1, 4
  srl t0, 1
  or t0, t1
  beqz t2, done
  ls_gp(sb t0, {MMC1_VARIANT}_shift)

// Shift full
// Reset shift reg
  lli t1, 0b1'0000
  ls_gp(sb t1, {MMC1_VARIANT}_shift)

if {defined LOG_MMC1} {
  addi sp, 16
  sd ra, -8(sp)
  sd t0, -16(sp)

  jal PrintStr0
  la_gp(a0, {MMC1_VARIANT}_msg)

  ld a0, -16(sp)
  lli a1, 2
  jal PrintHex
  andi a0, 0b1'1111

  jal PrintStr0
  la_gp(a0, {MMC1_VARIANT}_arrow_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

if {MMC1_VARIANT} == MMC1_SUROM {
  ls_gp(lbu a0, {MMC1_VARIANT}_prg_hi)
  jal PrintHex
  lli a1, 2
}

  jal NewlineAndFlushDebug
  nop

  ld ra, -8(sp)
  ld t0, -16(sp)
  addi sp, -16
}

// Take action depending on address bits 14,13
  srl t2, cpu_t1, 13
  andi t2, 0b11
  sll t1, t2, 2
  add t1, gp
  add t2, gp
  lw t3, {MMC1_VARIANT}_write_reg_jump_table - gp_base (t1)
  andi t0, 0b1'1111
  sb t0, {MMC1_VARIANT}_regs - gp_base (t2)
  jr t3
  la_gp(ra, done)

// This gets called from Init as well
// t0 = new ctrl
// Unlike the other reg writes, this ignores ra and always goes to done
update_ctrl:
// TODO check if mode really changed?
// Set up modes to handle register writes
  andi t1, t0, 0b0'1100
  andi t2, t0, 0b1'0000
  add t1, gp
  lw t1, MMC1PrgModes - gp_base (t1)
  srl t2, 4-3
  add t2, gp
  ld t2, MMC1ChrModes - gp_base (t2)
  ls_gp(sw t1, {MMC1_VARIANT}_write_reg_jump_table+3*4)
// Redo reg 3 (PRG page) write
  jalr t1
  ls_gp(sd t2, {MMC1_VARIANT}_write_reg_jump_table+1*4)

// NT/AT Mirroring
  ls_gp(lbu t0, {MMC1_VARIANT}_regs+0)
  la_gp(a0, ppu_ram + 0)
  andi t0, 0b11
  sll t0, 2
  add t0, gp
  lw t0, mirror_mode_jump_table - gp_base (t0)
  la_gp(a1, ppu_ram + 0x400)
  jr t0
  la_gp(ra, mirror_done)

mirror_mode_jump_table:
  dw SingleScreenMirroring, single_1, VerticalMirroring, HorizontalMirroring

single_1:
  j SingleScreenMirroring
  move a0, a1

mirror_done:
// Redo reg 1 and 2 (CHR page) writes
  ls_gp(lw t0, {MMC1_VARIANT}_write_reg_jump_table+1*4)
  jalr t0
  nop
  ls_gp(lw t0, {MMC1_VARIANT}_write_reg_jump_table+2*4)
  jr t0
  la_gp(ra, done)

done:
  lw ra, cpu_rw_handler_ra (r0)
  jr ra
  nop
}

begin_bss()
align(8)
{MMC1_VARIANT}_last_write_cycle:; dd 0

{MMC1_VARIANT}_prgrom_vaddr:;     dw 0
{MMC1_VARIANT}_prg_mode_vector:;  dw 0
{MMC1_VARIANT}_regs:;             dw 0

align(8)
// intentionally misalign so {MMC1_VARIANT}_write_reg_jump_table+1*4 is 8 byte aligned
  dw 0
{MMC1_VARIANT}_write_reg_jump_table:; fill 4*4

{MMC1_VARIANT}_prgrom_tlb_index:; db 0
{MMC1_VARIANT}_shift:;            db 0
if {MMC1_VARIANT} == MMC1_SUROM {
{MMC1_VARIANT}_prg_hi:;           db 0
}

align(4)
end_bss()

if {defined LOG_MMC1} {
{MMC1_VARIANT}_msg:
  db "MMC1 write ",0
{MMC1_VARIANT}_arrow_msg:
  db " -> ",0
}

align(4)
