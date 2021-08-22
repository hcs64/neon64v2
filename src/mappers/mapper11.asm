// Mapper 11: Color Dreams

scope Mapper11: {
Init:
  addi sp, 8
  sw ra, -8(sp)

// 32K
  jal TLB.AllocateVaddr
  lui a0, 0x1'0000 >> 16  // align 64K to leave a 32k guard page unmapped

  ls_gp(sw a0, mapper11_prgrom_vaddr)
  ls_gp(sb a1, mapper11_prgrom_tlb_index)

// 0x8000-0x1'0000
  addi t0, a0, -0x8000
  la_gp(t1, Write)
  lli t2, 0
  lli t3, 0x80

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

// Initially map PRG ROM bank 0, CHR ROM bank 0
  j Write_alt
  lli cpu_t0, 0

Write:
// cpu_t0: data
// cpu_t1: address (unused)
  addi sp, 8
  sw ra, -8(sp)

Write_alt:
// TODO save cpu_t0 for save states

  and t3, cpu_t0, 3
  sll t3, 15  // 32k PRG ROM bank

  ls_gp(lw a1, prgrom_start_phys)
  ls_gp(lw a0, mapper11_prgrom_vaddr)
  ls_gp(lwu t1, prgrom_mask)
  ls_gp(lbu t2, mapper11_prgrom_tlb_index)

  and t3, t1
  add a1, t3

  jal TLB.Map32K
  mtc0 t2, Index

  srl t0, cpu_t0, 4
  sll t0, chrrom_page_shift
  ls_gp(lwu t2, chrrom_mask)
  ls_gp(lwu t1, chrrom_start)
  and t0, t2
  dadd t0, t1
  dsll32 t1, t0, 0
  or t0, t1
  sd t0, ppu_map + 0*4 (r0)
  sd t0, ppu_map + 2*4 (r0)
  sd t0, ppu_map + 4*4 (r0)
  sd t0, ppu_map + 6*4 (r0)

  lw ra, -8(sp)
  jr ra
  addi sp, -8
}

begin_bss()
align(4)
mapper11_prgrom_vaddr:;  dw 0

mapper11_prgrom_tlb_index:; db 0
align(4)
end_bss()
