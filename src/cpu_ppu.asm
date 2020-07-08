// CPU interface with PPU (0x2000-0x2008)

//define LOG_PPU()
//define LOG_READ_PPU()

scope ppu_read_handler: {
// cpu_t1: address
// return value in cpu_t1

if {defined LOG_READ_PPU} {
  sw ra, cpu_rw_handler_ra (r0)

  jal PrintStr0
  la_gp(a0, ppu_read_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

  lw ra, cpu_rw_handler_ra (r0)
}
  andi t0, cpu_t1, 7
  sll t0, 2
  add t0, gp
  lw t0, jump_table - gp_base (t0)
  sw ra, cpu_rw_handler_ra (r0)
  jr t0
  la_gp(ra, done_restore_ra)

jump_table:
  dw reg0, reg1, PPU.ReadStatus, reg3
  dw reg4, reg5, reg6, PPU.ReadData

reg0:
reg1:
reg3:
reg4:
reg5:
reg6:
// TODO not implemented yet
  j done
  lli cpu_t1, 0

done_restore_ra:
  lw ra, cpu_rw_handler_ra (r0)
done:

if {defined LOG_READ_PPU} {
  sw ra, cpu_rw_handler_ra (r0)

  jal PrintStr0
  la_gp(a0, val_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, cycle_msg)

  ld a0, target_cycle (r0)
  jal PrintDec
  daddu a0, cycle_balance

  jal NewlineAndFlushDebug
  nop

  lw ra, cpu_rw_handler_ra (r0)
}

  jr ra
  nop
}

scope ppu_write_handler: {
// cpu_t0: value
// cpu_t1: address

if {defined LOG_PPU} {
  sw ra, cpu_rw_handler_ra (r0)

  jal PrintStr0
  la_gp(a0, ppu_write_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

  jal PrintStr0
  la_gp(a0, val_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, cycle_msg)

  ld a0, target_cycle (r0)
  jal PrintDec
  daddu a0, cycle_balance

  jal NewlineAndFlushDebug
  nop

  lw ra, cpu_rw_handler_ra (r0)
}

  andi t0, cpu_t1, 7
  sll t0, 2
  add t0, gp
  lw t0, jump_table - gp_base (t0)
  sw ra, cpu_rw_handler_ra (r0)
  jr t0
  la_gp(ra, done_restore_ra)

jump_table:
  dw PPU.WriteCtrl, reg1, reg2, reg3
  dw PPU.WriteOAM, PPU.WriteScroll, PPU.WriteAddr, PPU.WriteData

reg1:
  j done
  sb cpu_t0, ppu_mask (r0)

reg3:
  j done
  sb cpu_t0, oam_addr (r0)

// TODO
reg2:
  j done
  nop

done_restore_ra:
  lw ra, cpu_rw_handler_ra (r0)
done:

// TODO nothing implemented yet
  jr ra
  nop
}

if {defined LOG_PPU} {
ppu_write_msg:
  db "PPU write ", 0
}
if {defined LOG_READ_PPU} {
ppu_read_msg:
  db "PPU read  ", 0
}

align(4)
