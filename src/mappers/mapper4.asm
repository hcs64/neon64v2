// Mapper 4: MMC3, TxROM

//define LOG_MMC3()

constant mmc3_prgrom_page_shift(13) // 8K
constant mmc3_chrrom_page_shift(10) // 1K

scope Mapper4: {
Init:
  addi sp, 8
  sw ra, -8 (sp)

// Init vars
  ls_gp(sd r0, mmc3_bank_data)
// mmc3_bank_select handled below
  ls_gp(sb r0, mmc3_scanline_counter)
  ls_gp(sb r0, mmc3_scanline_latch)
  ls_gp(sb r0, mmc3_irq_enabled)

  la_gp(t0, MMC3JumpTableData)
  la_gp(t1, mmc3_jump_table)
  lli t2, 8-1
-
  lw t3, 0 (t0)
  addi t0, 4
  sw t3, 0 (t1)
  addi t1, 4
  bnez t2,-
  addi t2, -1

// Init TLB
// These 4 8K pages should be adjacent in virtual address and TLB index space,
// so only the first address and index is stored.

// 8K page for 0x8000-0xa000
  jal TLB.AllocateVaddr
  lli a0, 0x2000
  ls_gp(sw a0, mmc3_prgrom_vaddr)
  ls_gp(sb a1, mmc3_prgrom_tlb_index)

// 8K page for 0xa000-0xc000
  jal TLB.AllocateVaddr
  lli a0, 0x2000

// 8K page for 0xc000-0xe000
  jal TLB.AllocateVaddr
  lli a0, 0x2000

// 8K page for 0xe000-0x1'0000
  jal TLB.AllocateVaddr
  lli a0, 0x2000

// Map PRG
  ls_gp(lw t0, mmc3_prgrom_vaddr)
  la_gp(t1, Write)
  addi t0, -0x8000
  lli t2, 0
  lli t3, 0x80

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t1, cpu_write_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

// Initial PRG and CHR setup
// Both mode 1 so we can notice them change to 0 in MMC3BankSelect
  lli t0, 0xc0
  ls_gp(sb t0, mmc3_bank_select)

  jal MMC3BankSelect
  lli cpu_t0, 0

// Bank 7 doesn't change with modes, initialize it here
  la_gp(t0, MMC3Bank7)
  ls_gp(sw t0, mmc3_bank_vectors + 7 * 4)

  jal MMC3Bank7
  lli cpu_t0, 0

// Last PRG bank (0xe000-0x1'0000) is hardwired to last bank
  ls_gp(lw a0, prgrom_page_count)
  sll cpu_t0, prgrom_page_shift - mmc3_prgrom_page_shift // 16K pages to 8K pages
  lli a0, 3
  jal MMC3SetPRGBank
  addi cpu_t0, -1

// Default ROM header mirroring is ok for init

// Load our hooked PPU
  load_overlay_from_rom(ppu_overlay, mmc3)
  la a0, 0
  la_gp(a1, ppu_mmc3.FrameLoop)
  jal Scheduler.ScheduleTaskFromNow
  lli a2, ppu_task

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

Write:
// cpu_t0: value
// cpu_t1: address

if {defined LOG_MMC3} {
  addi sp, 8
  sw ra, -8(sp)

  jal PrintStr0
  la_gp(a0, mmc3_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, mmc3_arrow_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

  jal NewlineAndFlushDebug
  nop

  lw ra, -8(sp)
  addi sp, -8
}

  andi t0, cpu_t1, 0b0110'0000'0000'0000
  andi t1, cpu_t1, 1
  srl t0, 13-1
  or t0, t1
  sll t0, 2

  add t0, gp
  lw t0, mmc3_jump_table - gp_base (t0)
  jr t0
  nop

ScanlineCounter:
  ls_gp(lbu t0, mmc3_scanline_counter)
  ls_gp(lbu t2, mmc3_scanline_latch)
  bnez t0,+
  addi t0, -1

// Reload
  jr ra
  ls_gp(sb t2, mmc3_scanline_counter)

+
  bnez t0,+
  ls_gp(sb t0, mmc3_scanline_counter)
// Hit, trigger IRQ
  ls_gp(lbu t1, mmc3_irq_enabled)
  lbu t0, irq_pending (r0)
  beqz t1,+
  ori t0, intMapper
  sb t0, irq_pending (r0)
+
  jr ra
  nop

MMC3JumpTableData:
  dw MMC3BankSelect, MMC3Bank0_CHRMode0, MMC3Mirroring, MMC3PRGRAM, MMC3IRQLatch, MMC3IRQReload, MMC3IRQDisable, MMC3IRQEnable
align(8)
MMC3Banks_CHRMode0:
  dw MMC3Bank0_CHRMode0, MMC3Bank1_CHRMode0, MMC3Bank2_CHRMode0, MMC3Bank3_CHRMode0, MMC3Bank4_CHRMode0, MMC3Bank5_CHRMode0
MMC3Banks_CHRMode1:
  dw MMC3Bank0_CHRMode1, MMC3Bank1_CHRMode1, MMC3Bank2_CHRMode1, MMC3Bank3_CHRMode1, MMC3Bank4_CHRMode1, MMC3Bank5_CHRMode1
MMC3Banks_PRGMode:
  dw MMC3Bank6_PRGMode0, MMC3Bank6_PRGMode1

MMC3BankSelect:
  ls_gp(lbu t1, mmc3_bank_select)

// Update CHR ROM mode
// The bet is that modes will change much more rarely than banks
  xor t1, cpu_t0
  andi t2, t1, 0b1000'0000
  beqz t2, mmc3_chrrom_update_done
  andi t0, cpu_t0, 0b111

  addi sp, 24
  sw t0, -4(sp)
  sw t1, -8(sp)
  sw cpu_t0, -12(sp)
  sw ra, -16(sp)

  andi t0, cpu_t0, 0b1000'0000
  beqz t0,+
  la_gp(t0, MMC3Banks_CHRMode0)
  la_gp(t0, MMC3Banks_CHRMode1)
+
  la_gp(t1, mmc3_bank_vectors + 0*4)
  ld t2, 0 (t0)
  ld t3, 8 (t0)
  sd t2, 0 (t1)
  ld t2, 16 (t0)
  sd t3, 8 (t1)
  sd t2, 16 (t1)

evaluate rep_i(0)
while {rep_i} < 6 {
  ls_gp(lw t0, mmc3_bank_vectors + {rep_i}*4)
  jalr t0
  ls_gp(lbu cpu_t0, mmc3_bank_data + {rep_i})
evaluate rep_i({rep_i}+1)
}

  lw t0, -4(sp)
  lw t1, -8(sp)
  lw cpu_t0, -12(sp)
  lw ra, -16(sp)
  addi sp, -24
mmc3_chrrom_update_done:


// Update PRG ROM mode
  andi t2, t1, 0b0100'0000
  beqz t2, mmc3_prgrom_update_done
  sll t0, 2

  addi sp, 16
  sw t0, -4(sp)
  sw cpu_t0, -8(sp)
  sw ra, -12(sp)

  andi t0, cpu_t0, 0b0100'0000
  beqz t0,+
  la_gp(t0, MMC3Banks_PRGMode + 0)
  la_gp(t0, MMC3Banks_PRGMode + 4)
+
  la_gp(t1, mmc3_bank_vectors + 6 * 4)
  lw t0, 0 (t0)
  ls_gp(lbu cpu_t0, mmc3_bank_data + 6)
  jalr t0
  sw t0, 0 (t1)

  lw cpu_t0, -8(sp)

// Set TLB for fixed bank
  andi t0, cpu_t0, 0b0100'0000
  ls_gp(lbu cpu_t0, prgrom_page_count)

  beqz t0,+
  lli a0, 2 // 0xc000
  lli a0, 0 // 0x8000
+
  sll cpu_t0, prgrom_page_shift - mmc3_prgrom_page_shift // 16K pages to 8K pages
  jal MMC3SetPRGBank
  addi cpu_t0, -2

  lw t0, -4(sp)
  lw cpu_t0, -8(sp)
  lw ra, -12(sp)
  addi sp, -16
mmc3_prgrom_update_done:

// Put the bank data write handler in the jump table
  add t0, gp
  lw t0, mmc3_bank_vectors - gp_base (t0)
  ls_gp(sb cpu_t0, mmc3_bank_select)
  ls_gp(sw t0, mmc3_jump_table + 1 * 4)

  jr ra
  nop

macro mmc3_map_2k_chr(page_addr) {
    lw t1, ppu_catchup_cb (r0)
    // delay slot?
    beqz t1,+
    nop // delay slot?
    sw ra, cpu_rw_handler_ra (r0)
    jalr t1
    nop
    lw ra, cpu_rw_handler_ra (r0)
+

    ls_gp(lw t0, chrrom_start)
    ls_gp(lwu t2, chrrom_mask)
    andi t1, cpu_t0, 0b1111'1110 // low bit unused
    sll t1, mmc3_chrrom_page_shift
    and t1, t2
    add t0, t1
    addi t0, -{page_addr}

    sw t0, ppu_map + {page_addr}/0x400*4+0 (r0)
    sw t0, ppu_map + {page_addr}/0x400*4+4 (r0)
}
macro mmc3_map_1k_chr(page_addr) {
    lw t1, ppu_catchup_cb (r0)
    // delay slot?
    beqz t1,+
    nop // delay slot?
    sw ra, cpu_rw_handler_ra (r0)
    jalr t1
    nop
    lw ra, cpu_rw_handler_ra (r0)
+

    ls_gp(lw t0, chrrom_start)
    ls_gp(lwu t2, chrrom_mask)
    sll t1, cpu_t0, mmc3_chrrom_page_shift
    and t1, t2
    add t0, t1
    addi t0, -{page_addr}

    sw t0, ppu_map + {page_addr}/0x400*4+0 (r0)
}

MMC3Bank0_CHRMode0:
// cpu_t0: 2K CHR bank at 0x0000-0x0800
mmc3_map_2k_chr(0x0000)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 0)
MMC3Bank0_CHRMode1:
// cpu_t0: 2K CHR bank at 0x1000-0x1800
mmc3_map_2k_chr(0x1000)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 0)
MMC3Bank1_CHRMode0:
// cpu_t0: 2K CHR bank at 0x0800-0x1000
mmc3_map_2k_chr(0x0800)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 1)
MMC3Bank1_CHRMode1:
// cpu_t0: 2K CHR bank at 0x1800-0x2000
mmc3_map_2k_chr(0x1800)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 1)

MMC3Bank2_CHRMode0:
// cpu_t0: 1K CHR bank at 0x1000-0x1400
mmc3_map_1k_chr(0x1000)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 2)
MMC3Bank2_CHRMode1:
// cpu_t0: 1K CHR bank at 0x0000-0x0400
mmc3_map_1k_chr(0x0000)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 2)
MMC3Bank3_CHRMode0:
// cpu_t0: 1K CHR bank at 0x1400-0x1800
mmc3_map_1k_chr(0x1400)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 3)
MMC3Bank3_CHRMode1:
// cpu_t0: 1K CHR bank at 0x0400-0x0800
mmc3_map_1k_chr(0x0400)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 3)
MMC3Bank4_CHRMode0:
// cpu_t0: 1K CHR bank at 0x1800-0x1c00
mmc3_map_1k_chr(0x1800)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 4)
MMC3Bank4_CHRMode1:
// cpu_t0: 1K CHR bank at 0x0800-0x0c00
mmc3_map_1k_chr(0x0800)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 4)
MMC3Bank5_CHRMode0:
// cpu_t0: 1K CHR bank at 0x1c00-0x2000
mmc3_map_1k_chr(0x1c00)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 5)
MMC3Bank5_CHRMode1:
// cpu_t0: 1K CHR bank at 0x0c00-0x1000
mmc3_map_1k_chr(0x0c00)
  jr ra
  ls_gp(sb cpu_t0, mmc3_bank_data + 5)


MMC3SetPRGBank:
// cpu_t0: bank to load
// a0: page index (0-3)
if {defined LOG_MMC3} {
  addi sp, 16
  sw a0, -8(sp)
  sw ra, -16(sp)

  jal PrintStr0
  la_gp(a0, mmc3_prg_msg)

  lw a0, -8(sp)
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, mmc3_arrow_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop

  lw a0, -8(sp)
  lw ra, -16(sp)
  addi sp, -16
}
  ls_gp(lbu t3, mmc3_prgrom_tlb_index)
  ls_gp(lwu t1, prgrom_mask)
  add t3, a0
  ls_gp(lw t0, mmc3_prgrom_vaddr)
  sll t2, cpu_t0, mmc3_prgrom_page_shift
  ls_gp(lw a1, prgrom_start_phys)
  and t1, t2
  add a1, t1

  sll a0, mmc3_prgrom_page_shift
  add a0, t0

// Tail call
  j TLB.Map8K
  mtc0 t3, Index

MMC3Bank6_PRGMode0:
// cpu_t0: 8K bank at 0x8000-0xa000
  ls_gp(sb cpu_t0, mmc3_bank_data + 6)
// Tail call
  j MMC3SetPRGBank
  lli a0, 0

MMC3Bank6_PRGMode1:
// cpu_t0: 8K bank at 0xc000-0xe000
  ls_gp(sb cpu_t0, mmc3_bank_data + 6)
// Tail call
  j MMC3SetPRGBank
  lli a0, 2

MMC3Bank7:
// cpu_t0: 8K bank at 0xa000-0xc000
  ls_gp(sb cpu_t0, mmc3_bank_data + 7)
// Tail call
  j MMC3SetPRGBank
  lli a0, 1

MMC3Mirroring:
  ls_gp(lbu t0, flags6)
  la_gp(a0, ppu_ram + 0)
// Ignored if four-screen mirroring is set in header
  andi t0, 0b1000
  bnez t0,+
  la_gp(a1, ppu_ram + 0x400)
  andi t0, cpu_t0, 1
// Tail calls
  beqz t0, VerticalMirroring
  nop
  j HorizontalMirroring
  nop
+
  jr ra
  nop

MMC3PRGRAM:
// TODO
  jr ra
  nop

MMC3IRQLatch:
  jr ra
  ls_gp(sb cpu_t0, mmc3_scanline_latch)

MMC3IRQReload:
  jr ra
  ls_gp(sb r0, mmc3_scanline_counter)

MMC3IRQDisable:
// Disable IRQ and clear interrupt
  lbu t0, irq_pending (r0)
  ls_gp(sb r0, mmc3_irq_enabled)
  andi t0, 0xff^intMapper
  jr ra
  sb t0, irq_pending (r0)

MMC3IRQEnable:
// cpu_t1 is the address, lsb is 1, so this will serve to write nonzero
  jr ra
  ls_gp(sb cpu_t1, mmc3_irq_enabled)
}

begin_bss()
align(8)
mmc3_bank_data:;        fill 8

mmc3_bank_vectors:;     fill 8*4
mmc3_jump_table:;       fill 8*4
mmc3_prgrom_vaddr:;     dw 0

mmc3_prgrom_tlb_index:; db 0
mmc3_bank_select:;      db 0
mmc3_scanline_counter:; db 0
mmc3_scanline_latch:;   db 0
mmc3_irq_enabled:;      db 0
align(4)
end_bss()

if {defined LOG_MMC3} {
mmc3_msg:
  db "MMC3 write ",0
mmc3_prg_msg:
  db "MMC3 PRG ",0
mmc3_arrow_msg:
  db " -> ",0
}

align(4)
