arch n64.cpu
endian msb

define PROFILE_BARS()
//define PROFILE_RDP()

include "lib/n64.inc"
include "lib/n64_rsp.inc"
include "lib/n64_gfx.inc"
include "regs.inc"

if !{defined OUTPUT_FILE} {
define OUTPUT_FILE("neon64.n64")
}
output {OUTPUT_FILE}, create
macro close_output_file() {
  output "/dev/null"
}
macro reopen_output_file() {
  output "{OUTPUT_FILE}"
}

if !({defined NES_TIMING} || {defined PAL_NES}) {
define NTSC_NES()
}

// Pad for checksum
fill 0x10'1000
origin 0
if {defined NTSC_NES} {
N64_HEADER(Entrypoint, "Neon64 2.0-b.2")
} else if {defined PAL_NES} {
N64_HEADER(Entrypoint, "Neon64 2.0-b.2PALNES")
}
insert "lib/N64_BOOTCODE.BIN"

base 0x8000'1000
Entrypoint:
  j Start
  nop

include "mem.asm"

constant width(320)
constant height(240)
constant hscale_width(284)
constant vscale_height(240)

constant samplerate(44'160)
constant abuf_samples(samplerate/60/8)
if abuf_samples != abuf_samples/2*2 {
error "buffer must be an even number of samples"
}
constant cycles_per_sample(clock_rate/samplerate)
Start:
// PIF mumbo jumbo (disarm watchdog?)
// TODO is this supposed to be waiting for something first?
  lui a0, PIF_BASE
  lli t0, 8
  sw t0, PIF_RAM+$3C(a0)

  gp_init()

  la sp, call_stack

  jal InitExceptions
  nop

  jal TLB.Init
  nop

  jal InitDebug
  nop

// Load N64 header for debugging
// TODO convert this to use pi.asm?
  lui t0, PI_BASE

-;lw t1, PI_STATUS (t0)
  andi t1, %11 // busy
  bnez t1,-
  nop

  la t2, n64_header
  cache data_hit_invalidate, 0*DCACHE_LINE (t2)
  cache data_hit_invalidate, 1*DCACHE_LINE (t2)
  cache data_hit_invalidate, 2*DCACHE_LINE (t2)
  cache data_hit_invalidate, 3*DCACHE_LINE (t2)
  sw t2, PI_DRAM_ADDR (t0)
  la t1, 0x1000'0000
  sw t1, PI_CART_ADDR (t0)
  lli t1, 0x40-1
  sw t1, PI_WR_LEN (t0)

-;lw t1, PI_STATUS (t0)
  andi t1, %11 // busy
  bnez t1,-
  nop

  jal PrintStr0
  la_gp(a0, startup_message)

  jal FlushDebug
  nop

  jal RSP.Init
  nop

  jal VI.Init
  nop

  jal AI.Init
  nop

  jal Scheduler.Init
  nop

  jal PI.Init
  nop

  jal SI.Init
  nop

  jal InitIntCallbacks
  nop

  jal Menu.Init
  nop

  jal InitCPU
  nop

  jal PPU.Init
  nop

  jal APU.Init
  nop

  jal Joy.Init
  nop

  jal LoadROM
  nop

  jal ResetCPU
  nop

  jal Scheduler.Run
  mtc0 r0, Count

  j Scheduler.NoTasks
  nop

PrintHeaderInfo:
  addi sp, 8
  sw ra, -8 (sp)

  jal PrintStr0
  la_gp(a0, newline)

  la_gp(a0, n64_header + 0x20)
  jal PrintStr
  lli a1, 20

  jal PrintStr0
  la_gp(a0, crc_message)

  ls_gp(lw a0, n64_header + 0x10)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, space)

  ls_gp(lw a0, n64_header + 0x14)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, newline)

  lw ra, -8(sp)
  jr ra
  addi sp, -8

DisplayDebugAndHalt:
  jal PrintHeaderInfo
  nop

-
  ls_gp(lw a0, active_framebuffer)
  beqz a0,-
  addi a0, (10*width+margin)*2
  jal VI.PrintDebugToScreen
  nop

  jal NewlineAndFlushDebug
  nop

  ls_gp(lw a0, active_framebuffer)
  ls_gp(sw r0, active_framebuffer)
  ls_gp(sw a0, finished_framebuffer)

// Stop audio
  lui t0, AI_BASE
  sw r0, AI_CONTROL (t0)

  jal DisableTimerInterrupt
  nop

-;j -;nop


include "exception.asm"
include "tlb.asm"
include "vi.asm"
include "ai.asm"
include "rsp.asm"
include "si.asm"
include "pi.asm"
include "scheduler.asm"
include "intcb.asm"
include "frame.asm"

include "timing.asm"
include "cpu.asm"
include "cpu_ppu.asm"
include "cpu_io.asm"
include "ppu.asm"
include "apu.asm"

include "rom.asm"
include "menu.asm"
include "save.asm"
include "lib/debug_print.asm"

begin_bss()
align_dcache()
n64_header:
  fill 0x40
align_dcache()
end_bss()

align_icache()

print 0x8000'0000+32*0x400 - pc(), " bytes left in ICache\n"

include "ucode.asm"
include "dlist.asm"

align(8)
font:
insert "lib/font.bin"

startup_message:
  db "Welcome to Neon64!\n",0

crc_message:
  db "\nCRC ",0

copyright_message:
  db "\n\n"
  db "Copyright 2020      \n"
  db "Adam Gashlin (hcs)  \n"
  db "\n",0
license_message:
  fill 32, ' '
  db "Permission to use, copy, modify, and/or distribute this software for any "
  db "purpose with or without fee is hereby granted, provided that the above "
  db "copyright notice and this permission notice appear in all copies."
  fill 16, ' '
  db "THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES "
  db "WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF "
  db "MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR "
  db "ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES "
  db "WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN "
  db "ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF "
  db "OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE."
license_message_end:
  fill 30, ' '
  db 0

align(4)

if pc() > (low_page_ram_base | 0x8000'0000) {
  error "overflow into low page"
}

if bss_pc > last_backfill {
  error "underflow into bss"
}

if {defined ERR_EMBED1} {
align(8)
err_embed_rom1:
  insert "{ERR_EMBED1}"
}
if {defined ERR_EMBED2} {
align(8)
err_embed_rom2:
  insert "{ERR_EMBED2}"
}
