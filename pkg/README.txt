Neon64 2.0 WIP
=================

NES Emulation, On the N64, in the distant future...

Features
--------

- NTSC and PAL NES on NTSC N64
- CPU (official opcodes)
- PPU
- APU channels (2 square, triangle, noise, DMC)
- Battery backed RAM save to SRAM
- iNES mappers #s 0,1,2,3,4,7,9,10,11,30,31,34,66,71
- Controllers 1 and 2  (D-pad + analog)

There's a lot missing, but it's already worlds better than 1.2.

Running
-------

The easiest way is to use a dev cart that supports using an NES emulator for
.nes files:

- 64drive: Drop neon64bu.rom into the root directory.
- EverDrive-64: Rename neon64bu.rom to emu.nes and put it in the ED64 directory.

Anything that loads the NES ROM at the "emulation standard" (0x200000) will work.

Alternatively, Neon64 will also look for a directly appeneded NES ROM at 0x101000.
From a Windows command line:

copy /b neon64bu.rom + game.nes game.n64

on Linux, macOS, etc:

cat neon64bu.rom game.nes > game.n64

Controls
--------

A, B, Start and the D-pad on controllers 1 and 2 are mapped in the obvious way.
Select is the Z button. The analog stick is roughly like the D-pad, it may be
easier to use with games allowing diagonal movement.

To access the menu, hold the L and R shoulder buttons. Navigate with the D-pad
or Z, select an option with A or Start. Hold L and R again to dismiss the menu.

Saving
------

For games with battery-backed RAM, you can save from the menu.

Saving uses dedicated 768Kbit SRAM. This is supported by newer 64drive firmware,
tested with 1.14e.

Saves should be compatible with Visor's "Neon64 with Savestates" 0.3c, though
savestates are not yet supported.

Version history
---------------

2022-04-06 - beta 4
New:
  - Controller 2!
  - Mapper 11 (various Color Dreams), thanks to sp1187!
  - Mapper 34 (Deadly Towers), thanks to ddp34!
  - Mapper 66 (Doraemon, etc)
  - Detect PAL from NES 2.0 header
  - Unofficial opcodes (Deadly Towers, Aladdin, Streemerz, etc)
Fixed:
  - Controller detection issues #3 and #5
  - More accurate PCM playback on PAL (e.g. High Hopes demo)
  - More compatible video signal for compatibility with Retrotink (issue #8)
  - DMC looping (Bomberman II, issue #3)
  - Clock MMC3 IRQ counter (issue #4)
  - CPU bug in Qix
  - Initialize RAM to all 1s instead of 0s (Battletoads)
  - Delay immediate NMI by one instruction (Bomberman II attract mode)
  - Overall improved timing by delaying interrupts one instruction, though
    this is still not quite correct.
  - Remap PC when leaving a bank (Deadly Towers)

2020-07-27 - beta 3
  - Add mappers 9, 10 (MMC2, MMC4)
  - Added overlays, so mappers can modify the core PPU loop
  - Runtime PAL switch
  - Improved MMC3 IRQ timing
  - DMC and frame counter IRQ
  - Assorted timing adjustments
  - Support some mid-line changes (e.g. Marble Madness)
  - Fix MMC1 PRG mode 0 (e.g. Pirates!)
  - SUROM support (Dragon Warrior III and IV)

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
* tepples for helpful tests (and the Sprite Demo!)
* Quietust for the Scanline demo, a helpful minimal example
* Bero, Xodnizel, et al for FCE(U(X)), I've often referred to the source and debugger
* lukexor for tetanes, handy Rust emu to modify for testing

Many thanks to contributors to the NesDev wiki and ultra64.ca.

Greets to the #n64dev and N64brew sceners, LaC, Pinchy, Zoinkity, jrra,
mikeryan, ppcasm, arbin, DragonMinded, level42, fraser, fin, CrashOveride,
awygle, nico, anarko, et al!

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

-hcs 2022-04-06
