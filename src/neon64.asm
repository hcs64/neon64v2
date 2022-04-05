arch n64.cpu
endian msb

define PROFILE_BARS()
//define PROFILE_RDP()

include "lib/mips.inc"
include "lib/n64.inc"
include "lib/n64_rsp.inc"
include "lib/n64_gfx.inc"
include "regs.inc"

if !({defined NTSC_NES} || {defined PAL_NES}) {
define NTSC_NES()
}

include "loader_mem.inc"

if !{defined OUTPUT_FILE} {
define OUTPUT_FILE("neon64.n64")
}
output {OUTPUT_FILE}, create
macro close_output_file() {
  output "/dev/null"
}
macro reopen_output_file() {
  output {OUTPUT_FILE}
}

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

base RESIDENT_BASE

if origin() != 0 {
  error "entrypoint must be at start of output"
}

Entrypoint:
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
  la t1, rom_cart_addr
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

  jal InitIntCallbacks
  nop

  jal PI.Init
  nop

  jal SI.Init
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

SwitchModel:
  lli t0, 1
  ls_gp(sb t0, rsp_shutdown_requested)

// wait for halt
  lui t1, SP_BASE
-
  lw t0, SP_STATUS (t1)
  andi t0, RSP_HLT
  beqz t0,-
  nop

  mtc0 r0, Status

if {defined NTSC_NES} {
  j PAL_LOADER
  nop
} else if {defined PAL_NES} {
  j NTSC_LOADER
  nop
}



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

// Wait until no framebuffer actively being drawn
-
  ls_gp(lw a0, active_framebuffer)
  beqz a0,+
// If no dlist is running the active framebuffer will never be finished, skip waiting
  ls_gp(lw a0, running_dlist_idx)
  bgez a0,-
  nop
+

  la a0, framebuffer0 + (16*width+22)*2
  jal VI.PrintDebugToScreen
  lli a1, 30

  jal NewlineAndFlushDebug
  nop

  la a0, framebuffer0
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
include "overlay.asm"
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

emit_overlay_index()

begin_bss()
align_dcache()
n64_header:
  fill 0x40
align_dcache()
end_bss()

align_icache()

print 0x8000'0000+16*0x400 - pc(), " bytes left in ICache\n"

include "ucode.asm"
include "dlist.asm"

align(8)
font:
insert "lib/font.bin"
rdpfont:
insert "lib/rdpfont.bin"

startup_message:
  db "Welcome to Neon64!\n",0

crc_message:
  db "\nCRC ",0

copyright_message:
  db "\n\n"
  db "Copyright 2020-2022 \n"
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

if pc() > bss_base {
  error "overflow into bss"
}

if bss_pc > last_backfill {
  error "underflow into bss"
}

align(8)

base pc() - base() + rom_cart_addr + ROM_OFFSET

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

emit_overlays()
