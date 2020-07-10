//define LOG_MAPPER_31()

scope Mapper31: {
Init:
  addi sp, 16
  sw ra, -16 (sp)

// 0x8000-0xa000: 2x4K
  jal TLB.AllocateVaddr
  lli a0, 0x4000 // align 16k to lave a 8k guard page unmapped
  ls_gp(sw a0, mapper_31_vaddrs + 0*4)
  ls_gp(sb a1, mapper_31_tlb_indexes + 0)

// 0xa000-0xc000: 2x4K
  jal TLB.AllocateVaddr
  lli a0, 0x4000
  ls_gp(sw a0, mapper_31_vaddrs + 1*4)
  ls_gp(sb a1, mapper_31_tlb_indexes + 1)

// 0xc000-0xe000: 2x4K
  jal TLB.AllocateVaddr
  lli a0, 0x4000
  ls_gp(sw a0, mapper_31_vaddrs + 2*4)
  ls_gp(sb a1, mapper_31_tlb_indexes + 2)

// 0xe000-0x10000: 2x4K
  jal TLB.AllocateVaddr
  lli a0, 0x4000
  ls_gp(sw a0, mapper_31_vaddrs + 3*4)
  ls_gp(sb a1, mapper_31_tlb_indexes + 3)

// Map CPU address space
  ls_gp(lw t0, mapper_31_vaddrs + 0*4)
  ls_gp(lw t1, mapper_31_vaddrs + 1*4)
  ls_gp(lw t2, mapper_31_vaddrs + 2*4)
  addi t4, r0, -0x8000
  add t0, t4
  addi t4, -0x2000
  add t1, t4
  addi t4, -0x2000
  add t2, t4
  addi t4, -0x2000
  add t3, a0, t4

  lli t4, 0
  lli t8, 0x20  // 2x4K
-
  sw t0, cpu_read_map + 0x80*4 (t4)
  sw t1, cpu_read_map + 0xa0*4 (t4)
  sw t2, cpu_read_map + 0xc0*4 (t4)
  sw t3, cpu_read_map + 0xe0*4 (t4)
  addi t8, -1
  bnez t8,-
  addi t4, 4

// Mapper register is written at 0x5000-0x6000
  lli t0, 0
  la_gp(t1, Write)
  lli t2, 0x10
-
  sw t1, cpu_write_map + 0x50*4 (t0)
  addi t2, -1
  bnez t2,-
  addi t0, 4

// Set up initial banks
  ls_gp(sd r0, mapper_31_prgrom_banks)
  lli cpu_t0, 0xFF
  jal Write
  lli cpu_t1, 0x5FFF

  lli t0, 7-1
-
  sb t0, -8 (sp)

  lli cpu_t0, 0
  jal Write
  addi cpu_t1, t0, 0x5FF8

  lbu t0, -8 (sp)
  bnez t0,-
  addi t0, -1

  lw ra, -16 (sp)
  jr ra
  addi sp, -16

Write:
  andi t0, cpu_t1, 0b111
  add t1, t0, gp
  sb cpu_t0, mapper_31_prgrom_banks - gp_base (t1)

  andi t0, 0b110
  sll t1, t0, 2-1
  add t1, gp
  lw a0, mapper_31_vaddrs - gp_base (t1)
  srl t1, t0, 1
  add t1, gp
  lbu t3, mapper_31_tlb_indexes - gp_base (t1)
  add t0, gp
  lbu a1, mapper_31_prgrom_banks - gp_base + 0 (t0)
  lbu a2, mapper_31_prgrom_banks - gp_base + 1 (t0)
  ls_gp(lw t2, prgrom_start_phys)
  ls_gp(lwu t1, prgrom_mask)
  sll a1, 12  // 4K
  sll a2, 12
  and a1, t1
  and a2, t1
  add a1, t2
  add a2, t2

if {defined LOG_MAPPER_31} {
  addi sp, 24
  sw ra, -24 (sp)
  sw a0, -20 (sp)
  sw a1, -16 (sp)
  sw a2, -12 (sp)
  sw t3, -8 (sp)

  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, space)
  lw a0, -16 (sp)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, space)
  lw a0, -12 (sp)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, space)
  lw a0, -8 (sp)
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop

  lw ra, -24 (sp)
  lw a0, -20 (sp)
  lw a1, -16 (sp)
  lw a2, -12 (sp)
  lw t3, -8 (sp)
  addi sp, -24
}
// Tail call
  j TLB.Map4K_2
  mtc0 t3, Index
}

begin_bss()
align(8)
mapper_31_prgrom_banks:
  fill 8
mapper_31_vaddrs:
  fill 4*4
mapper_31_tlb_indexes:
  fill 4
end_bss()
