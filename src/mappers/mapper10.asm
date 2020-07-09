// Mapper 10: FxROM, MMC4

InitMapper10:
  addi sp, 8
  sw ra, -8 (sp)

  lli t0, 6-1
  add t1, gp, t0
-
  sb r0, mapper10_regs - gp_base (t1)
  addi t1, -1
  bnez t0,-
  addi t0, -1

// 2x16K
  jal TLB.AllocateVaddr
  lui a0, 0x1'0000 >> 16  // align 64k to leave a 32k guard page unmapped

  ls_gp(sw a0, mapper10_prgrom_vaddr)
  ls_gp(sb a1, mapper10_prgrom_tlb_idx)


// 0x8000-0x1'0000
  la_gp(t1, WriteMapper10)
  addi a0, -0x8000
  lli t2, 0
  lli t3, 0x80

-
  subi t4, t2, 0x20*4
  bltz t4,+
  sw a0, cpu_read_map + 0x80*4 (t2)

// Registers starting from 0xa000
  sw t1, cpu_write_map + 0x80*4 (t2)
+

  addi t3, -1
  bnez t3,-
  addi t2, 4

// Initial bank setup
  lli cpu_t0, 0
  jal WriteMapper10
  lli cpu_t1, 0xa000

  lli t0, 0xfd
  jal Mapper10Latch
  lli t1, 0x0000

  lli t0, 0xfd
  jal Mapper10Latch
  lli t1, 0x1000

  lw ra, -8 (sp)
  jr ra
  addi ra, -8


scope WriteMapper10: {
// cpu_t0: value
// cpu_t1: address
  srl t0, cpu_t1, 12
  subi t0, 0xa
  sll t1, t0, 2
  add t1, gp
  lw t1, jump_table - gp_base (t1)

  jr t1
  add t2, gp, t0

jump_table:
  dw prgrom_select, chrrom_fd_0, chrrom_fe_0, chrrom_fd_1, chrrom_fe_1, mirroring

prgrom_select:
  ls_gp(lbu t0, mapper10_prgrom_tlb_idx)
  ls_gp(lw t1, prgrom_start_phys)
  ls_gp(lw t2, prgrom_mask)
  ls_gp(lw a2, prgrom_last_page_phys)
  ls_gp(lw a0, mapper10_prgrom_vaddr)
  sll a1, cpu_t0, 14 // 16K
  and a1, t2
  add a1, t1

// Tail call
  j TLB.Map16K_2
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
  lw t1, ppu_catchup_cb (r0)
  beqz t1,+
  sw ra, cpu_rw_handler_ra (r0)
// Catch up
  jalr t1
  nop

// Recompute register address for store
  srl t0, cpu_t1, 12
  subi t0, 0xa
  add t2, gp, t0

  lw ra, cpu_rw_handler_ra (r0)
+
  sb cpu_t0, mapper10_regs - gp_base (t2)

// Determine if the active mapping needs to change
  srl t1, cpu_t1, 12
  subi t1, 0xb
  srl t0, t1, 1
  add t0, gp
  lbu t0, mapper10_latch - gp_base (t0)
  andi t2, t1, 1
  addi t2, 0xfd
  bne t0, t2,+
  nop
  andi t1, 0b10
  jal Mapper10Latch
  sll t1, 12-1

  lw ra, cpu_rw_handler_ra (r0)
+

  jr ra
  nop
}

Mapper10Latch:
// t0: The tile idx
// t1: Pattern table base (+fine y)
  andi t4, t1, 0x1000

  srl t3, t4, 12-1
  add t3, gp
  lli t2, 0xfd
  beq t0, t2,+
  lbu t2, mapper10_regs + 1 - gp_base (t3)
  lbu t2, mapper10_regs + 2 - gp_base (t3)
+
  ls_gp(lw t1, chrrom_start)
  ls_gp(lw t3, chrrom_mask)
  sll t2, 12 // 4K
  and t2, t3
  add t2, t1
  sub t2, t4

  srl t3, t4, 12
  add t3, gp
  sb t0, mapper10_latch - gp_base (t3)

  srl t4, 12-(2+2) // *4*4

  sw t2, ppu_map + 0*4 (t4)
  sw t2, ppu_map + 1*4 (t4)
  sw t2, ppu_map + 2*4 (t4)
  jr ra
  sw t2, ppu_map + 3*4 (t4)

begin_bss()
mapper10_prgrom_vaddr:; dw 0

mapper10_regs:; fill 6
mapper10_latch:; db 0,0
mapper10_prgrom_tlb_idx:; db 0

align(4)

end_bss()
