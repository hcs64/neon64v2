// Mapper 7: AxROM

InitMapper7:
  addi sp, 8
  sw ra, -8(sp)

// 32K
  jal TLB.AllocateVaddr
  lui a0, 0x1'0000 >> 16  // align 64K to leave a 32k guard page unmapped

  ls_gp(sw a0, mapper7_prgrom_vaddr)
  ls_gp(sb a1, mapper7_prgrom_tlb_index)

// 0x8000-0x1'0000
  addi t0, a0, -0x8000
  la_gp(t1, WriteMapper7)
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

// Initially map PRG ROM bank 0, Nametable 0
  j WriteMapper7_alt
  lli cpu_t0, 0

WriteMapper7:
// cpu_t0: data
// cpu_t1: address (unused)
  addi sp, 8
  sw ra, -8(sp)

WriteMapper7_alt:
  sll t0, cpu_t0, 15  // 32k PRG ROM bank

  ls_gp(lw a1, prgrom_start_phys)
  ls_gp(lw a0, mapper7_prgrom_vaddr)
  ls_gp(lwu t1, prgrom_mask)
  ls_gp(lbu t2, mapper7_prgrom_tlb_index)
  
  and t0, t1
  add a1, t0

  jal TLB.Map32K
  mtc0 t2, Index

// Mirroring
  andi a0, cpu_t0, 0b1'0000 // Nametable select
  la_gp(t0, ppu_ram)
  sll a0, 10-4 // 1K
  add a0, t0

// Tail call
  lw ra, -8(sp)
  j SingleScreenMirroring
  addi sp, -8

begin_bss()
align(4)
mapper7_prgrom_vaddr:;  dw 0

mapper7_prgrom_tlb_index:; db 0
align(4)
end_bss()
