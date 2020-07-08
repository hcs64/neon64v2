// Mapper 30: UNROM 512

InitMapper30:
  addi sp, 8
  sw ra, -8 (sp)

  jal InitUxPRGROM
  la_gp(a0, WriteMapper30)

  jal WriteMapper30
  lli cpu_t0, 0

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

scope WriteMapper30: {
  addi sp, 8
  sw ra, -8 (sp)

// PRG ROM mapping 0x8000-0xc000
  andi t1, cpu_t0, 0b0001'1111
  ls_gp(sb t1, uxrom_prgrom_bank)
  ls_gp(lw t0, prgrom_mask)
  sll t1, prgrom_page_shift
  ls_gp(lw t2, prgrom_start_phys)
  and t1, t0
  add a1, t2, t1
// Page 0xc000-0x10000 is fixed to last page
  ls_gp(lw a2, prgrom_last_page_phys)

  ls_gp(lbu t0, uxrom_prgrom_tlb_index)
  ls_gp(lw a0, uxrom_prgrom_vaddr)

  jal TLB.Map16K_2
  mtc0 t0, Index

// CHR RAM mapping 0x0000-0x2000
+
  la t1, chrram
  andi t0, cpu_t0, 0b0110'0000
  ls_gp(sb t0, unrom512_chrram_bank)
  sll t0, chrrom_page_shift-5  // 8K
  add t0, t1
  lli t1, 8
  lli t2, 0
-
  sw t0, ppu_map (t2)
  addi t1, -1
  bnez t1,-
  addi t2, 4

// Mirroring
  ls_gp(lbu t0, flags6)
  lli t1, 0b1000
  andi t0, 0b1001
  beq t1, t0, one_screen
// Default are fine for all but one screen
  lw ra, -8 (sp)
  jr ra
  addi sp, -8

one_screen:
  la_gp(a0, ppu_ram)
  andi t0, cpu_t0, 0x80
  sll t0, 10-7  // 1K
  add a0, t0
// Tail call
  j SingleScreenMirroring
  addi sp, -8
}

begin_bss()
unrom512_chrram_bank:; db 0
align(4)
end_bss()
