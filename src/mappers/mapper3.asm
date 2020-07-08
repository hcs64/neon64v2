// Mapper 3: CNROM

InitMapper3:
  addi sp, 8
  sw ra, -8(sp)

  jal MapPrgRom16_32
  nop

// 0x8000-0x1'0000
  la_gp(t1, WriteMapper3)
  lli t2, 0
  lli t3, 0x80

-
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

  jal WriteMapper3_after_shift
  lli t0, 0

  lw ra, -8(sp)
  jr ra
  addi sp, -8

WriteMapper3:
// cpu_t0: data
// cpu_t1: address (unused)

  sll t0, cpu_t0, chrrom_page_shift
WriteMapper3_after_shift:
// 8K bank
  ls_gp(lwu t2, chrrom_mask)
  ls_gp(lwu t1, chrrom_start)
  and t0, t2
  dadd t0, t1
  dsll32 t1, t0, 0
  or t0, t1
  sd t0, ppu_map + 0*4 (r0)
  sd t0, ppu_map + 2*4 (r0)
  sd t0, ppu_map + 4*4 (r0)
  jr ra
  sd t0, ppu_map + 6*4 (r0)
