// Mapper 9: PxROM, MMC2

InitMapper9:
  addi sp, 8
  sw ra, -8 (sp)

  lli t0, 6-1
  add t1, gp, t0
-
  sb r0, mapper9_regs - gp_base (t1)
  addi t1, -1
  bnez t0,-
  addi t0, -1

// 0x8000, 8K
  jal TLB.AllocateVaddr
  lli a0, 0x4000  // align 16K
  ls_gp(sw a0, mapper9_prgrom_vaddr + 0*4)
  ls_gp(sb a1, mapper9_prgrom_tlb_idx + 0)

// 0xa000, 8K
  jal TLB.AllocateVaddr
  lli a0, 0x4000  // align 16K
  ls_gp(sw a0, mapper9_prgrom_vaddr + 1*4)
  ls_gp(sb a1, mapper9_prgrom_tlb_idx + 1)

// 0xc000, 16K
  jal TLB.AllocateVaddr
  lli a0, 0x8000  // align 32K
  ls_gp(sw a0, mapper9_prgrom_vaddr + 2*4)
  ls_gp(sb a1, mapper9_prgrom_tlb_idx + 2)

// 4 banks 0x8000, 0xa000, and 0xc000+0xe000 are together
  ls_gp(lw a2, mapper9_prgrom_vaddr + 0*4)
  ls_gp(lw a3, mapper9_prgrom_vaddr + 1*4)
  addi a2, -0x8000
  lli t0, 0xa000
  sub a3, t0
  lli t0, 0xc000
  sub t0, a0, t0
  la_gp(t1, WriteMapper9)
  lli t2, 0
  lli t3, 0x20

-
  sw a2, cpu_read_map + 0x80*4 (t2)
  sw a3, cpu_read_map + 0xa0*4 (t2)
  sw t0, cpu_read_map + 0xc0*4 (t2)
  sw t0, cpu_read_map + 0xe0*4 (t2)

// Registers starting from 0xa000
  sw t1, cpu_write_map + 0xa0*4 (t2)
  sw t1, cpu_write_map + 0xc0*4 (t2)
  sw t1, cpu_write_map + 0xe0*4 (t2)

  addi t3, -1
  bnez t3,-
  addi t2, 4

// 0xc000 and 0xe000 are fixed to the last pages
// a0,a1 still have the vaddr, index
  mtc0 a1, Index
  jal TLB.Map16K
  ls_gp(lw a1, prgrom_last_page_phys)

// 0xa000 is fixed to the 3rd from last page
  ls_gp(lw a1, prgrom_last_page_phys)
  ls_gp(lw a0, mapper9_prgrom_vaddr + 1*4)
  ls_gp(lbu t0, mapper9_prgrom_tlb_idx + 1)
  addi a1, -0x2000  // 8K
  jal TLB.Map8K
  mtc0 t0, Index

// Initial bank setup
  lli cpu_t0, 0
  jal WriteMapper9
  lli cpu_t1, 0xa000

  jal Mapper9Latch0
  lli t0, 0x0fd0

  jal Mapper9Latch1
  lli t0, 0xfd

  lw ra, -8 (sp)
  jr ra
  addi ra, -8


scope WriteMapper9: {
// cpu_t0: value
// cpu_t1: address
  srl t0, cpu_t1, 12
  subi t0, 0xa
  sll t1, t0, 2
  add t1, gp
  lw t1, jump_table - gp_base (t1)

  add t2, gp, t0
  jr t1
  sb cpu_t0, mapper9_regs - gp_base (t2)

jump_table:
  dw prgrom_select, chrrom_fd_0, chrrom_fe_0, chrrom_fd_1, chrrom_fe_1, mirroring

prgrom_select:
  ls_gp(lbu t0, mapper9_prgrom_tlb_idx + 0)
  ls_gp(lw t1, prgrom_start_phys)
  ls_gp(lw t2, prgrom_mask)
  ls_gp(lw a0, mapper9_prgrom_vaddr + 0*4)
  sll a1, cpu_t0, 13 // 8K
  and a1, t2
  add a1, t1

// Tail call
  j TLB.Map8K
  mtc0 t0, Index

mirroring:
  andi cpu_t0, 1
// Tail calls
  la_gp(a0, ppu_ram)
  bnez cpu_t0, HorizontalMirroring
  la_gp(a1, ppu_ram + 0x400)
  j VerticalMirroring
  nop

chrrom_fd_0:
chrrom_fe_0:
chrrom_fd_1:
chrrom_fe_1:
// TODO PPU catchup?
  jr ra
  nop
}

Mapper9Latch0:
// t0: Matching pattern addr, -8
  ls_gp(lw t1, chrrom_start)

  lli t2, 0x0fd0
  beq t0, t2,+
  ls_gp(lbu t2, mapper9_regs + 1)
  ls_gp(lbu t2, mapper9_regs + 2)
+
  ls_gp(lw t3, chrrom_mask)
  sll t2, 12 // 4K
  and t2, t3
  add t2, t1

  sw t2, ppu_map + 0*4 (r0)
  sw t2, ppu_map + 1*4 (r0)
  sw t2, ppu_map + 2*4 (r0)
  jr ra
  sw t2, ppu_map + 3*4 (r0)

Mapper9Latch1:
// t0: The tile idx
  ls_gp(lw t1, chrrom_start)

  lli t2, 0xfd
  beq t0, t2,+
  ls_gp(lbu t2, mapper9_regs + 3)
  ls_gp(lbu t2, mapper9_regs + 4)
+
  ls_gp(lw t3, chrrom_mask)
  sll t2, 12 // 4K
  and t2, t3
  add t2, t1
  addi t2, -0x1000

  sw t2, ppu_map + 4*4 (r0)
  sw t2, ppu_map + 5*4 (r0)
  sw t2, ppu_map + 6*4 (r0)
  jr ra
  sw t2, ppu_map + 7*4 (r0)

begin_bss()
mapper9_prgrom_vaddr:; dw 0,0,0

mapper9_latch0:; dh 0

mapper9_regs:; fill 6
mapper9_prgrom_tlb_idx:; db 0,0,0

align(4)

end_bss()
