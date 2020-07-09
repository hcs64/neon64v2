Neon64 2.0 beta 2
=================

NES Emulation, On the N64, in the distant future...

Features
--------

- NTSC NES on NTSC N64
- CPU (official opcodes)
- PPU
- APU channels (2 square, triangle, noise, DMC)
- Battery backed RAM save to SRAM
- iNES mappers #s 0,1,2,3,4,7,9,10,30,31,71
- Controller 1 (D-pad + analog)

There's a lot missing, but it's already worlds better than 1.2.

Running
-------

The easiest way is to use a dev cart that supports using an NES emulator for
.nes files:

- 64drive: Drop neon64bu.rom into the root directory.
- EverDrive-64: Rename neon64bu.rom to emu.nes and put it in the ED64 directory.

Anything that loads the NES ROM at the "emulation standard" (0x200000) will work.

The Neon64 ROM is only as long as it needs to be to be checksummed consistently,
so it will also look for a NES ROM at 0x101000 so it can be directly appended.
From a Windows command line:

copy /b neon64bu.rom + game.nes game.n64

on Linux, macOS, etc:

cat neon64bu.rom game.nes > game.n64

I've included a separate version with PAL NES timing, this is usable but janky.

Controls
--------

A, B, Start and the D-pad on controller 1 are mapped in the obvious way. Select
is the Z button. The analog stick is roughly like the D-pad, it may be easier to
use with games allowing diagonal movement.

To access the menu, hold the L and R shoulder buttons. Navigate with the D-pad
or Z, select an option with A or Start. Hold L and R again to dismiss the menu.

Saving
------

For games with battery-backed RAM, you can save from the menu.

Saving uses dedicated 768Kbit SRAM. This is supported by newer 64drive firmware,
tested with 1.14e.

Saves should be compatible with Visor's "Neon64 with Savestates" 0.3c, though
savestates are not yet supported.

Architecture
------------

I split up the 6502 CPU ops to reduce code size; all N64 CPU code fits in
ICache. All ucode fits in IMEM together.

The CPU runs the main PPU loop. It passes the bytes read to the RSP, which
converts the background to a 4bpp texture and arranges sprites in an 8bpp
texture.

The RDP renders each frame, layering sprites and background, with tricky
palettes to use the same texture for BG and FG sprites.

The RSP synthesizes audio, driven by alists from the CPU. When the PCM buffer
runs low, the AI interrupt can request an immediate flush to stretch the alist.

The CPU has a cooperative scheduler, using an emulated cycle timer to trade off
between the CPU and PPU. This works mainly with daddi+bgezl.

The RSP has a separate coop scheduler. When a task yields it can run code on the
CPU via the RSP break interrupt.

I use the TLB to swap and mirror banks (PC is a native pointer), write protect
CHR ROM, place data at addresses below 32K (for free indexing), and mirror all
RDRAM (so bit 31 can be used as a flag).

On most games only around 50% of frame time is used.

Version history
---------------

2020-07-07 - beta 2
  - Add mappers 30, 31, 71
  - Source release

2020-07-04 - beta 1
  - Initial beta release

Everybody
---------

Thanks to:
* blargg for many docs and tests
* Marat Fayzullin for teaching a generation about emulation
* krom for great source and discussion
* MarathonMan et al for cen64 (very helpful for debugging!)
* marshallh for 64drive (the best N64 dev tool!)
* Near, ARM9, et al for bass
* Visor for a lot of good patches to 1.2
* Eisi for adding MMC4 support in 1.2
* bootgod et al for NesCartDB

Many thanks to contributors to the NesDev wiki and ultra64.ca.

Greets to the #n64dev and N64brew sceners, LaC, Pinchy, Zoinkity, jrra,
mikeryan, ppcasm, arbin, DragonMinded, level42, fraser, fin, CrashOverride,
et al!

Hello to my HCS Forum friends, bxaimc, knurek, FastElbja, manakoAT, kode54,
bnnm, Josh W, Mouser_X, and unknownfile if you're still out there!

Black Lives Matter.

Colophon
--------

A Halley's Comet Software production.

Bug reports welcome!

Git: https://github.com/hcs64/neon64v2
Forum: https://hcs64.com/mboard/forum.php
Email: agashlin@gmail.com 

-hcs 2020-07-07
