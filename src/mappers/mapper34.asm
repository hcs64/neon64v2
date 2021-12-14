// Mapper 34: BNROM
// TODO: support NINA-001

scope Mapper34: {
Init:
  addi sp, 8
  sw ra, -8(sp)

// 32K
  jal TLB.AllocateVaddr
  lui a0, 0x1'0000 >> 16  // align 64K to leave a 32k guard page unmapped

  ls_gp(sw a0, mapper34_prgrom_vaddr)
  ls_gp(sb a1, mapper34_prgrom_tlb_index)

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

// Hard wired CHR mapping 0x0000-0x2000 (8K)
  ls_gp(lw t0, chrrom_start)
  lli t1, 8
  lli t2, 0
-
  sw t0, ppu_map (t2)
  addi t1, -1
  bnez t1,-
  addi t2, 4

  lw ra, -8(sp)
  addi sp, -8

// Initially map PRG ROM bank 0, fall through to Write
  lli cpu_t0, 0

Write:
  sll t0, cpu_t0, 15  // choose from 4 32k PRG ROM banks

  ls_gp(lw a1, prgrom_start_phys)
  ls_gp(lw a0, mapper34_prgrom_vaddr)
  ls_gp(lwu t1, prgrom_mask)
  ls_gp(lbu t2, mapper34_prgrom_tlb_index)

  and t0, t1
  add a1, t0

  // tail call
  j TLB.Map32K
  mtc0 t2, Index
}

begin_bss()
align(4)
mapper34_prgrom_vaddr:;  dw 0

mapper34_prgrom_tlb_index:; db 0
align(4)
end_bss()
