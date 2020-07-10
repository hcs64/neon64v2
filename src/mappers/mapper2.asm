// Mapper 2: UxROM

//define LOG_MAPPER2()

scope Mapper2: {
Init:
  addi sp, 8
  sw ra, -8 (sp)

  jal InitUxPRGROM
  la_gp(a0, Write)

  jal Write
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

Write:
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
}
align(4)
