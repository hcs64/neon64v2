arch n64.cpu
endian msb

include "lib/mips.inc"
include "lib/n64.inc"
include "regs.inc"
include "loader_mem.inc"

// Pad for checksum
fill 0x10'1000
origin 0
N64_HEADER(NTSC_LOADER, "Neon64 2.0-beta.4")
insert "lib/N64_BOOTCODE.BIN"

base NTSC_LOADER
  jal CommonInit
  nop
// Tail call
  j StartNTSC
  nop

fill PAL_LOADER - pc()
  jal CommonInit
  nop
// Tail call
  j StartPAL
  nop

CommonInit:
// PIF mumbo jumbo (disarm watchdog?)
// TODO is this supposed to be waiting for something first?
  lui a0, PIF_BASE
  lli t0, 8
  sw t0, PIF_RAM+$3C(a0)

  mtc0 r0, Status

// TODO PI init, shutdown various other RCP, exception stuff?

  jr ra
  nop

macro start_vector(model) {
Start{model}:
  la a0, rom_cart_addr + {model}_ROM_OFFSET
  la a1, RESIDENT_BASE
  la a2, {model}_length
  jal PI.ReadSyncInvalidateIDCache
  nop

  jr a1
  nop
}

start_vector(NTSC)
start_vector(PAL)

include "pi_basics.asm"

origin NTSC_ROM_OFFSET
base 0
insert "{NTSC_BIN}"
align_icache()
constant NTSC_length(pc())

origin PAL_ROM_OFFSET
base 0
insert "{PAL_BIN}"
align_icache()
constant PAL_length(pc())
