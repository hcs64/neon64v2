// TODO This is only used on ROM load so could be swapped out. All mappers should probably be overlays.

constant max_rom_size(0x10'0000)
constant prgrom_page_shift(14)  // 16K
constant chrrom_page_shift(13)  // 8K

LoadROM:
  addi sp, 8
  sw ra, -8(sp)

// Read ROM header at emulation standard address
  la a0, rom_cart_addr + 0x20'0000
  jal LoadNESHeader
  la_gp(a3,+)

// Read ROM header at end of checksummed region
  la a0, rom_cart_addr + 0x10'1000
  jal LoadNESHeader
  la_gp(a3,+)

if {defined ERR_EMBED1} && {defined ERR_EMBED2} {
scope {
// No ROM found, display error message in a menu atop an embedded ROM
  jal Menu.StartBuild
  nop

  la_gp(t0, MissingHeaderHeader)
  ls_gp(sw t0, menu_header_proc)

  jal Menu.AddItem
  la_gp(a0, ok_menu_item)

  la_gp(t0, MissingHeaderFooter)
  ls_gp(sw t0, menu_footer_proc)

  jal Menu.FinishBuild
  nop

// Randomly choose a ROM, 3/4 chance of #1
  mfc0 t0, Count
  andi t0, 0b11
  la a0, rom_cart_addr + (err_embed_rom1 - 0x8000'0000)
  bnez t0, _3_4
  la_gp(ra, still_fail)
  la a0, rom_cart_addr + (err_embed_rom2 - 0x8000'0000)
_3_4:
  j LoadNESHeader
  la_gp(a3, yes_indeed)
yes_indeed:
  lli t0, 1
  j +
  ls_gp(sb t0, menu_enabled)

MissingHeaderHeader:
// Tail call
  j PrintStr0
  la_gp(a0, missing_header)

MissingHeaderFooter:
// Tail call
  j PrintHeaderInfo
  nop

still_fail:
}
}

  jal PrintStr0
  la_gp(a0, missing_header)

  j DisplayDebugAndHalt
  nop
+
  addi a0, 16
  ls_gp(sw a0, nes_rom_cart_addr)

// Save start of PRG ROM (physical, for TLB)
  la t0, nes_rom & 0x1fff'ffff
  ls_gp(sw t0, prgrom_start_phys)

// Save last page of PRG ROM
  ls_gp(lbu a0, prgrom_page_count)
  sll t1, a0, prgrom_page_shift
  add t0, t1
  addi t0, -0x4000  // 16K
  ls_gp(sw t0, prgrom_last_page_phys)

// Save start of CHR ROM
  la t0, (nes_rom & 0x7f'ffff) + tlb_ro_rdram
  add t0, t1

// Init address masks
// If the page count is not 2^k, this will map junk onto some pages,
// but this seems unlikely to matter (or even happen at all).
  jal RoundUpPowerOf2
  ls_gp(sw t0, chrrom_start)

  sll a0, prgrom_page_shift
  addi a0, -1
  ls_gp(sw a0, prgrom_mask)

  ls_gp(lbu a0, chrrom_page_count)
  bnez a0,+
  nop
// default to 8K CHR RAM
  la t0, chrram
  lli a0, 0x2000-1
  j ++
  ls_gp(sw t0, chrrom_start)
+
  jal RoundUpPowerOf2
  nop
  sll a0, chrrom_page_shift
  addi a0, -1
+
  ls_gp(sw a0, chrrom_mask)

// Default CHR ROM/RAM mapping 0x0000-0x2000 (8K)
  ls_gp(lw t0, chrrom_start)
  lli t1, 8
  lli t2, 0
-
  sw t0, ppu_map (t2)
  addi t1, -1
  bnez t1,-
  addi t2, 4

// Default mirroring from header
  la_gp(a0, ppu_ram + 0)
  ls_gp(lbu t3, flags6)
  la_gp(a1, ppu_ram + 0x400)
  andi t2, t3, 0b1000
  beqz t2,+
  andi t3, 1
  la a2, four_screen_ram
  addi a3, a2, 0x400
  jal FourScreenMirroring
  la_gp(ra,++)
+
  bnez t3, VerticalMirroring
  la_gp(ra,+)

  jal HorizontalMirroring
  nop
+

// Handle mapper
  ls_gp(lbu t0, flags6)
  ls_gp(lbu t1, flags7)

  srl t0, 4 // low mapper
  andi t1, 0xf0 // high mapper
  or t0, t1

  la_gp(ra, mapper_ok)

// Defaults are tailored to mapper 0, just set up TLB
  beqz t0, MapPrgRom16_32
  lli t2, 1
  beq t0, t2, InitMapper1
  lli t2, 2
  beq t0, t2, InitMapper2
  lli t2, 3
  beq t0, t2, InitMapper3
  lli t2, 4
  beq t0, t2, InitMapper4
  lli t2, 7
  beq t0, t2, InitMapper7
  lli t2, 9
  beq t0, t2, InitMapper9
  lli t2, 30
  beq t0, t2, InitMapper30
  lli t2, 31
  beq t0, t2, InitMapper31
  lli t2, 71
  beq t0, t2, InitMapper71
// HACK pretend 206 is 4
  lli t2, 206
  beq t0, t2, InitMapper4
  nop

// Unsupported mapper
  addi sp, 8
  sw t0, -8(sp)

  jal PrintStr0
  la_gp(a0, unsupported_mapper)

  lw a0, -8(sp)
  jal PrintDec
  addi sp, -8

  j DisplayDebugAndHalt
  nop
// fallthrough

mapper_ok:

// Invalidate data cache
// TODO it'd be much faster to just index invalidate all of dcache
  la t2, nes_rom
  la t1, max_rom_size / DCACHE_LINE
-;cache data_hit_invalidate, 0(t2)
  addi t1, -1
  bnez t1,-
  addi t2, DCACHE_LINE

// Read largest possible ROM
// TODO use actual size from mapper
// TODO layout to avoid cache aliasing with hot data
  ls_gp(lw a0, nes_rom_cart_addr)
  la a1, nes_rom
  la a2, max_rom_size
  jal PI.ReadSync
  nop

// Load persistent memory
  ls_gp(lbu t0, flags6)
  andi t0, 0b10 // persistent memory present
  beqz t0,+
  nop
  jal LoadExtraRAMFromSRAM
  nop
+
  
  lw ra, -8(sp)
  jr ra
  addi sp, -8

// a0: cart ROM address
// a3: success return vector (ra for failure)
LoadNESHeader:
  addi sp, 8
  sw ra, -8(sp)

  la_gp(a1, nes_header)
  cache data_hit_invalidate, 0(a1)
  jal PI.ReadSync
  lli a2, 16

// Check magic
  ls_gp(lwu t3, iNES)
  lwu t1, 0(a1)
  bne t1, t3,+
  lw ra, -8(sp)
  move ra, a3
+
  jr ra
  addi sp, -8

// a0 = pointer
SingleScreenMirroring:
  addi t0, a0, -0x2000
  addi t1, a0, -0x2400
  addi t2, a0, -0x2800
  j finish_mirroring
  addi t3, a0, -0x2c00

// a0 = page 0
// a1 = page 1
// a2 = page 2
// a3 = page 3
FourScreenMirroring:
  addi t0, a0, -0x2000
  addi t1, a1, -0x2400
  addi t2, a2, -0x2800
  j finish_mirroring
  addi t3, a3, -0x2c00

// a0 = low page pointer
// a1 = high page pointer
HorizontalMirroring:
  addi t0, a0, -0x2000
  addi t1, a0, -0x2400
  addi t2, a1, -0x2800
  j finish_mirroring
  addi t3, a1, -0x2c00

// a0 = low page pointer
// a1 = high page pointer
VerticalMirroring:
  addi t0, a0, -0x2000
  addi t1, a1, -0x2400
  addi t2, a0, -0x2800
  addi t3, a1, -0x2c00
finish_mirroring:
  sw t0, ppu_map + 8*4 (r0)
  sw t1, ppu_map + 9*4 (r0)
  sw t2, ppu_map + 10*4 (r0)
  sw t3, ppu_map + 11*4 (r0)

// Mirror to 0x3000-0x4000 (some of this will be shadowed by palette RAM)
  addi t0, -0x1000
  addi t1, -0x1000
  addi t2, -0x1000
  addi t3, -0x1000
  sw t0, ppu_map + 12*4 (r0)
  sw t1, ppu_map + 13*4 (r0)
  sw t2, ppu_map + 14*4 (r0)
  jr ra
  sw t3, ppu_map + 15*4 (r0)

// In a0: value to round (> 0)
// Out a0: rounded to lowest power of 2 at least as large
RoundUpPowerOf2:
  lli t0, 1

-
  sub t1, a0, t0
  bgtz t1,-
  sll t0, 1

  jr ra
  srl a0, t0, 1

scope MapPrgRom16_32: {
  addi sp, 8
  sw ra, -8(sp)

// 1 or 2 16kb PRG ROM pages
  ls_gp(lbu t0, prgrom_page_count)

  beqz t0, bad_page_count
  subi t1, t0, 2
  bgtz t1, bad_page_count
  nop

  beqz t1, prg32
  nop

// 1x16k, mirrored
// TODO: couldn't this just be TLB.Map16K_2?

  jal TLB.AllocateVaddr
  lli a0, 0x8000  // align 32K to leave a 32K guard unmapped

// 0x8000-0xc000 and 0xc000-0x1'0000
  addiu t0, a0, -0x8000
  addiu t1, t0, -0x4000
  lli t2, 0
  lli t3, 0x40

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  sw t1, cpu_read_map + 0xc0 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

  ls_gp(lw a1, prgrom_start_phys)
  j TLB.Map16K
  la_gp(ra, end)

prg32:
// 1x32K
  jal TLB.AllocateVaddr
  lui a0, 0x1'0000 >> 16  // align 64k to leave a 32k guard page unmapped

// 0x8000-0x1'0000
  addiu t0, a0, -0x8000
  lli t2, 0
  lli t3, 0x80

-
  sw t0, cpu_read_map + 0x80 * 4 (t2)
  addi t3, -1
  bnez t3,-
  addi t2, 4

  jal TLB.Map32K
  ls_gp(lw a1, prgrom_start_phys)

end:
  lw ra, -8(sp)
  jr ra
  addi sp, -8

bad_page_count:
  jal PrintStr0
  la_gp(a0, mapper_limits)

  jal PrintDec
  ls_gp(lbu a0, nes_header + 4)

  j DisplayDebugAndHalt
  nop

mapper_limits:
  db "Wrong PRG-ROM page count: ",0

align(4)
}

begin_bss()
align_dcache()
nes_header:; fill 4
prgrom_page_count:; db 0
chrrom_page_count:; db 0
flags6:; db 0
flags7:; db 0
  fill 8
align_dcache()

nes_rom_cart_addr:; dw 0
prgrom_start_phys:; dw 0
prgrom_last_page_phys:; dw 0
chrrom_start:; dw 0
prgrom_mask:; dw 0
chrrom_mask:; dw 0

end_bss()

// TODO we may want to overlay the mappers to save cache
align_icache()
include "mappers/mapper1.asm"
include "mappers/mapper2.asm"
include "mappers/mapper3.asm"
include "mappers/mapper4.asm"
include "mappers/mapper7.asm"
include "mappers/mapper9.asm"
include "mappers/mapper30.asm"
include "mappers/mapper31.asm"
include "mappers/mapper71.asm"

iNES:
  db "NES",0x1a
missing_header:
  db "NES header not found\n",0
unsupported_mapper:
  db "Unsupported mapper: ",0

align(4)
