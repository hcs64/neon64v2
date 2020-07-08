// Mapper 71: Codemasters

InitMapper71:
  addi sp, 8
  sw ra, -8 (sp)

  jal InitUxPRGROM
  la_gp(a0, WriteMapper71High)

// Update write handler for 0x8000-0xc000
  lli t2, 0
  lli t3, 0x40
  la_gp(t1, WriteMapper71Low)
-
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

// Tail call
  lw ra, -8 (sp)
  addi sp, -8

  j WriteMapper71High
  lli cpu_t0, 0

WriteMapper71Low:
// TODO, single-screen mirroring for Fire Hawk
  jr ra
  nop

WriteMapper71High:
  ls_gp(sb cpu_t0, uxrom_prgrom_bank)
  ls_gp(lw t2, prgrom_start_phys)
  ls_gp(lwu t0, prgrom_mask)
  sll t1, cpu_t0, prgrom_page_shift
  and t1, t0
  add a1, t2, t1
  ls_gp(lw a2, prgrom_last_page_phys)

  ls_gp(lbu t0, uxrom_prgrom_tlb_index)
  ls_gp(lw a0, uxrom_prgrom_vaddr)

// Tail call
  j TLB.Map16K_2
  mtc0 t0, Index
