// Save data

constant sram_save_cart_addr(sram_cart_addr + 0x8000 + 0x8000)
constant sram_save_header_size(8)
constant sram_save_footer_size(8)
constant sram_save_header_cart_addr(sram_save_cart_addr)
constant sram_save_data_cart_addr(sram_save_cart_addr + sram_save_header_size)
constant sram_save_footer_cart_addr(sram_save_data_cart_addr + nes_extra_ram_size)

// This only happens once at boot, before the scheduler gets going,
// so it is simpler to read synchronously.
scope LoadExtraRAMFromSRAM: {
  addi sp, 8
  sw ra, -8 (sp)

  jal PI.SetSRAMTiming
  nop

// Read header
  la a0, sram_save_header_cart_addr
  la a1, nes_extra_ram_save_verify
  cache data_hit_invalidate, 0 (a1)
  jal PI.ReadSync
  lli a2, sram_save_header_size

// Check header
  ls_gp(ld t0, sram_save_header)
  la t3, nes_extra_ram_save_verify
  ld t1, 0 (t3)
  bne t0, t1, end
  nop

// Read footer
  la a0, sram_save_footer_cart_addr
  la a1, nes_extra_ram_save_verify
  cache data_hit_invalidate, 0 (a1)
  jal PI.ReadSync
  lli a2, sram_save_footer_size

// Check footer
  ls_gp(ld t0, sram_save_footer)
  la t3, nes_extra_ram_save_verify
  ld t1, 0 (t3)
  bne t0, t1, end
  nop

// Read save data
  la t0, nes_extra_ram
  lli t1, nes_extra_ram_size/DCACHE_LINE
-
  cache data_hit_invalidate, 0 (t0)
  addi t1, -1
  bnez t1,-
  addi t0, DCACHE_LINE

  la a0, sram_save_data_cart_addr
  la a1, nes_extra_ram
  jal PI.ReadSync
  lli a2, nes_extra_ram_size

end:
  lw ra, -8 (sp)
  jr ra
  addi sp, -8
}

// This happens while the game is running, so it is broken into async steps.
scope SaveExtraRAMToSRAM: {
  addi sp, 8
  sw ra, -8 (sp)

// Make a copy
  lli t0, nes_extra_ram_size
  la t1, nes_extra_ram
  la t2, nes_extra_ram_save_copy
-
  ld t3, 0 (t1)
  ld t4, 8 (t1)
  addi t1, 16
  cache data_create_dirty_exclusive, 0 (t2)
  sd t3, 0 (t2)
  sd t4, 8 (t2)
  cache data_hit_write_back, 0 (t2)

  addi t0, -16
  bnez t0,-
  addi t2, 16

  jal PI.SetSRAMTiming
  nop

// Write header
  la a0, sram_save_header_cart_addr
  la_gp(a1, sram_save_header)
  lli a2, sram_save_header_size
  jal PI.WriteAsync
  la_gp(a3, write_footer)

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

write_footer:
// Write footer
  la a0, sram_save_footer_cart_addr
  la_gp(a1, sram_save_footer)
  lli a2, sram_save_footer_size
// Tail call
  j PI.WriteAsync
  la_gp(a3, read_header)

read_header:
// Read back header
  la a0, sram_save_header_cart_addr
  la a1, nes_extra_ram_save_verify
  cache data_hit_invalidate, 0 (a1)
  lli a2, sram_save_header_size
// Tail call
  j PI.ReadAsync
  la_gp(a3, write_data)

write_data:
// Check header
  ls_gp(ld t0, sram_save_header)
  la t3, nes_extra_ram_save_verify
  ld t1, 0 (t3)
// Tail call
  bne t0, t1, ShowSaveError
  nop

// Write save data
  la a0, sram_save_data_cart_addr
  la a1, nes_extra_ram_save_copy
  lli a2, nes_extra_ram_size
// Tail call
  j PI.WriteAsync
  la_gp(a3, read_data)

read_data:
// Read back save data
  la t0, nes_extra_ram_save_verify
  lli t1, nes_extra_ram_size/DCACHE_LINE
-
  cache data_hit_invalidate, 0 (t0)
  addi t1, -1
  bnez t1,-
  addi t0, DCACHE_LINE

  la a0, sram_save_data_cart_addr
  la a1, nes_extra_ram_save_verify
  lli a2, nes_extra_ram_size
// Tail call
  j PI.ReadAsync
  la_gp(a3, check_data)

check_data:
// Verify data
  la t0, nes_extra_ram_save_copy
  la t1, nes_extra_ram_save_verify
  lli t2, nes_extra_ram_size

-
  ld t3, 0 (t0)
  addi t0, 8
  ld t4, 0 (t1)
  addi t1, 8

// Tail call
  bne t3, t4, ShowSaveError
  addi t2, -8

  bnez t2,-
  nop

// Read footer
  la a0, sram_save_footer_cart_addr
  la a1, nes_extra_ram_save_verify
  cache data_hit_invalidate, 0 (a1)
  lli a2, sram_save_footer_size
// Tail call
  j PI.ReadAsync
  la_gp(a3, check_footer)

check_footer:
  ls_gp(ld t0, sram_save_footer)
  la t3, nes_extra_ram_save_verify
  ld t1, 0 (t3)
// Tail call
  bne t0, t1, ShowSaveError
  nop

// Tail call
  j ShowSaveSuccess
  nop
}

ShowSaveSuccess:
  addi sp, 8
  sw ra, -8 (sp)

  lli t0, 1
  ls_gp(sb t0, menu_enabled)

  jal Menu.StartBuild
  nop

  la_gp(t0, SaveSuccessHeader)
  ls_gp(sw t0, menu_header_proc)

  jal Menu.AddItem
  la_gp(a0, ok_menu_item)

  jal Menu.FinishBuild
  nop

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

ShowSaveError:
  addi sp, 8
  sw ra, -8 (sp)

  lli t0, 1
  ls_gp(sb t0, menu_enabled)

  jal Menu.StartBuild
  nop

  la_gp(t0, SaveErrorHeader)
  ls_gp(sw t0, menu_header_proc)

  jal Menu.AddItem
  la_gp(a0, ok_menu_item)

  jal Menu.FinishBuild
  nop

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

SaveErrorHeader:
// Tail call
  j PrintStr0
  la_gp(a0, save_error_msg)

SaveSuccessHeader:
// Tail call
  j PrintStr0
  la_gp(a0, save_success_header_msg)

save_success_header_msg:
  db " Save ok!       \n",0
save_error_msg:
  db " Save failed    \n",0

// This header/footer format follows Visor's "Neon64 with Savestates" 0.3c,
// though savestates themselves are not yet supported.
align_dcache()
sram_save_header:
  dw 0x79783B4A, 0x985626E0
sram_save_footer:
  dw 0x0BDFD303, 0x4579BC39
align_dcache()
