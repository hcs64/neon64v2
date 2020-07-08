// Mapper 2: UxROM
// Shared with others (30, 71)

//define LOG_MAPPER2()

// a0: write handler
InitUxPRGROM:
  addi sp, 16
  sw a0, -8 (sp)
  sw ra, -16 (sp)

  ls_gp(sb r0, uxrom_prgrom_bank)

// 2x16K
  jal TLB.AllocateVaddr
  lui a0, 0x1'0000 >> 16  // align 64k to leave a 32k guard page unmapped

  ls_gp(sw a0, uxrom_prgrom_vaddr)
  ls_gp(sb a1, uxrom_prgrom_tlb_index)

// 0x8000-0x1'0000
  addi t0, a0, -0x8000
  lw t1, -8 (sp)
  lli t2, 0
  lli t3, 0x80

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

  lw ra, -16 (sp)
  jr ra
  addi sp, -16

InitMapper2:
  addi sp, 8
  sw ra, -8 (sp)

  jal InitUxPRGROM
  la_gp(a0, WriteMapper2)

  jal WriteMapper2
  lli cpu_t0, 0

// Hard wired CHR ROM mapping 0x0000-0x2000 (8K)
  ls_gp(lw t0, chrrom_start)
  lli t1, 8
  lli t2, 0
-
  sw t0, ppu_map (t2)
  addi t1, -1
  bnez t1,-
  addi t2, 4

// Default mirroring is sufficient
  lw ra, -8(sp)
  jr ra
  addi sp, -8

WriteMapper2:
// cpu_t0: data
// cpu_t1: address (unused)
if {defined LOG_MAPPER2} {
  addi sp, 8
  sw ra, -8(sp)

  jal PrintStr0
  la_gp(a0, map2_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop

  lw ra, -8(sp)
  addi sp, -8
}
  ls_gp(sb cpu_t0, uxrom_prgrom_bank)
  ls_gp(lwu t0, prgrom_mask)
  sll t1, cpu_t0, prgrom_page_shift
  ls_gp(lw t2, prgrom_start_phys)
  and t1, t0
  add a1, t2, t1
  ls_gp(lw a2, prgrom_last_page_phys)

  ls_gp(lbu t0, uxrom_prgrom_tlb_index)
  ls_gp(lw a0, uxrom_prgrom_vaddr)

// Tail call
  j TLB.Map16K_2
  mtc0 t0, Index

if {defined LOG_MAPPER2} {
map2_msg:
  db "Mapper 2 write ",0
}
align(4)

begin_bss()
align(4)
uxrom_prgrom_vaddr:;  dw 0

uxrom_prgrom_bank:; db 0
uxrom_prgrom_tlb_index:; db 0
end_bss()
