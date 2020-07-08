# Neon64 2.0 source notes

## Building

This project uses [ARM9's fork of the bass assembler](https://github.com/ARM9/bass), which is linked as a git submodule for easy setup. On a system with git, Make, and a C compiler, you can build Neon64 by running:

    make

This will fetch bass, build the tools (bass and chksum64), and build the NTSC NES version as neon64bu.rom.

To build the PAL NES version (neon64bu_pal.rom), run `make pal`, or `make all` to do both. `make pkg` builds the release .zip.

## Overview

The scheduler runs the show after all the inits in `neon64.asm`. Profile bars show time on the RSP (top) and CPU (bottom) relative to a 60 FPS frame.

### Scheduling

When it runs a task, the scheduler sets two variables: `target_cycle` is the emulated cycle when the next task should run, and `cycle_balance` is the current time relative to `target_cycle`, starting negative and counting up to expiration at 0. Global shared state is up to date as of `target_cycle + cycle_balance`, and the task can assume that the shared state won't change or be observed by other tasks until `target_cycle`. The task updates `cycle_balance` via `dadd`/`daddi`, and yields with `bgezal` when expired. The scheduler records the final `target_cycle + cycle_balance` time for this task, and runs the task which is now earliest.

`cycle_balance` can go positive if the task runs past the target cycle, when not dealing with global shared state. (Unfortunately the 6502 doesn't get to do this often, it is always on the lookout for interrupts. A better design would schedule these separately.)

There are currently 5 tasks: CPU (6502), PPU, APU frame, APU DMC, and interrupt callback (`intcb`). `intcb` is for interrupt handlers that are not suitable to run in an exception, mostly they are for continuations of an asynchronous process, like the several steps of writing and verifying save data. If this task has any work, an interrupt handler will scheduler it to run at cycle 0, so it has priority after the next yield.

The RSP has a simple round-robin cooperative scheduler in ucode, the tasks do some chunk of work and yield, possibly running a completion vector in a `break` interrupt on the CPU. Tasks can indicate if they have no work; the RSP will not resume automatically if all tasks are idle. There is a priority signal from the CPU to run a specific task next, used for the APU flush, but I don't know if this does much good. PPU and APU each have an RSP task, I'd like to add a task that generates the dlist and manages the RDP, as well.

In the profile bars, CPU scheduler time is blue; RSP scheduler time isn't tracked.

### CPU (6502)

The CPU executes out of an opcode table, which has two MIPS instructions for all 6502 opcodes, see `opcodes.asm`. This is often enough to specify an instruction: An addressing mode is the target of a `j`, and the address of the execution stage is loaded in the delay slot.

The CPU address space is mapped by read and write pointers for every 256 byte page. If bit 31 is clear, this is memory, which can be accessed directly through the TLB. If bit 31 is set it points to a side effect handler.

The most common thing the 6502 does is read bytes at the current PC, so PC is a native pointer, in register `cpu_mpc`. It gets converted back (by subtracting `cpu_mpc_base`) as needed. When the PC increments normally, the pointer can just be incremented, unless it passes into another bank. To trap this, after each TLB page there is unmapped guard space. This is rare enough that I've never seen it happen, so I haven't implemented recovery yet; if needed the exception handler could remap PC.

The N and Z flags are used somewhat less often than they are set, so I defer updating them; operations that would set NZ save the relevant value in `cpu_nz_val`. There is a weird case where N and Z are both set (possible with `PLA` or `RTI`), so this needs to be 16 bits; the evaluation uses a lookup table so this usually has no overhead. I'm not sure if this is a great idea in its current form, I haven't profiled without it.

In the profile bars, CPU task time is bright green.

### PPU

The CPU-side PPU task is `FrameLoop` in `ppu.asm`, broadly: Fetch sprites, fetch background, repeat. The PPU yields for sprite 0 hit and vblank, and between hblank and visible pixels, when per-line changes are likely to occur.

Profiling in an earlier version showed that the hottest loop was checking all 64 sprites on each of 240 lines, so instead sprite evaluation scans OAM once per frame. Each line has a list of up to 8 sprites that occur on that line. Tile fetches are done before the background fetches for each line.

The background fetch is a Duff's device-ish loop, each iteration deals with all tiles using the same attribute byte. Flow enters the loop depending on the alignment of the X scroll, and exits when 33 tiles have been fetched. This has the potential to be extended to support mid-line changes, I have an implementation that works with Marble Madness but it's too buggy to release yet.

The CPU fetches the pattern and attribute bytes, then passes these off to the RSP. The bytes collect in 64-bit shift registers, written out uncached when full; the VR4300's write buffer can help absorb the latency of a few big uncached writes, without wasting DCache on something the CPU never reads again. When the CPU has finished 8 lines, it writes out some additional data and then updates a write cursor in RSP DMEM, letting the ucode know it can DMA in the block. This isn't a fully functional FIFO; the CPU won't start writing again until the ucode has finished the frame. The structure of this "conv" buffer is in `mem.asm`.

ucode converts background tiles from separate bitplane 2bpp to interleaved 4bpp, and has a loop to shift up to 7 pixels for fine X scroll. This also copies the palette for each frame, and sets the fill color in the dlist to the true background color. There is only support for one palette per frame, currently.

ucode converts sprite tiles to 8bpp and blits them into a single texture for each line in reverse index order, this handles sprite occlusion. A bit in each pixel indicates priority relative to the background, and by using half-empty palettes the RDP can render both BG and FG sprites from the same texture.

The PPU ucode relies heavily on RSP vector ops: Multiply and accumulate to "shift" and "OR" 8 pixels at once, `sfv` and transpose to interleave, and unaligned 8 byte load/store to blit into the sprite texture.

When the RSP has DMAd the textures out to RDRAM, it issues a `break`, which interrupts the CPU and schedules a frame task. The frame task waits for a free framebuffer, waits for the RDP to finish, and executes the dlist. Ideally this would instead be run by the RSP, using the XBUS so a dlist needs never touch RDRAM. The frame task does things like controller polling and profile reporting, as well, which don't fit nicely elsewhere.

When the dlist ends with a Full Sync, the RDP interrupt stores the framebuffer pointer for use at the next VI interrupt.

The PPU has mappings for each 1k page in the PPU address space. CHR ROM access uses a write-protected TLB page to avoid checking for permission at write time, the exception handler attempts to skip the offending instruction.

In the profile bars, PPU task time is red. The dark green bar starting from the right is vblank wait time, this is a good measure of idle time for the frame. Yellow is time the frame task wasn't waiting on vblank, this is mostly when drawing the menus. Define `PROFILE_RDP` to show RDP instead of RSP time.

### APU

The APU has two main drivers: First, the NES has a frame counter, which changes APU state automatically about 4 times per frame. Second, the 6502 can write to APU registers. Before allowing either of these to change the APU state, the CPU writes out an alist with the previous state and how long it lasted, this is `Render` in `apu.asm`. Also, the DMC reads samples on its own timer, these are buffered until the next alist.

Audio synthesis runs on the RSP, where the APU ucode deals with constant frequency and amplitude waves. Because most of the complex behavior is clocked by the slow frame counter, most of the state and logic stays on the CPU, sort of a sequencer/synthesizer division of labor. The ucode tracks phase for the waves across alists and buffers, which can be reset for some of the channels.

Every 44160Hz PCM sample is the simple sum of two point samples at twice that rate, an amount of "oversampling" configured at build time. At a fairly high sample rate this sounds mostly OK. Mixing uses lookup tables, following [blargg](http://www.slack.net/~ant/nes-emu/apu_ref.txt).

The CPU sends alists to the RSP through a FIFO, with read and write cursors in DMEM; the ucode reads in an alist when it detects the FIFO is not empty. The RSP also has a FIFO of PCM audio buffers (abufs), it `break`s to interrupt the CPU when DMA completes, to play the abuf if the AI isn't already full. The alist and abuf FIFOs can't be completely full, so that `read == write` always means empty, and to avoid overwriting the abufs currently managed by the AI.

There is also pull from the AI side. When the AI-not-full interrupt hits, the handler gets an abuf from the FIFO. If the FIFO is empty, the handler requests a flush, which tells the ucode to finish an abuf without waiting for an alist which covers those samples. This allows the audio to stretch if the emulation falls behind, commonly because a lot of timings are rounded down; this is preferable to the alternative where the buffer fills up and we have to figure out what samples to drop. Dropping samples isn't implemented (except for DMC), instead everything will slow down to the audio rate, though I haven't tested this in the steady state.

In the profile bars, APU task time is grey. This usually doesn't show up much on the CPU, in part because writing to registers is charged to the 6502 CPU.

## File-by-file

- `neon64.asm`: Entry point. Builds the N64 ROM header, includes files, calls inits. Also some debugging output.

- `ucode.asm`: DMEM layout, IMEM entry point, includes other ucode files. All ucode is resident simultaneously (so far).

- `mem.asm`: RDRAM Memory layout.

    Most things in the assembly fill the bottom of RAM. Some large allocations fill back from the end of MB 0, to avoid taking up `gp`-relative address space. MB 1 is reserved for the NES ROM (without iNES header). MB 2 is for (video) frame and audio buffers. MB 3 is for FIFO buffers used to send data to the RSP: alists and conv buffers. Static TLB layout is at the end.

    The "low page" (0x2000) is a TLB page that doesn't require a base register to address, this is handy for free indexing. bass doesn't have support for segments, so I use `begin_low_page()` and `end_low_page()` to wrap allocations; labels, `db`, `dw`, `align()`, etc. work here, but their data is not written to the output. This makes it easy to intermingle memory layout with the code that uses it, while keeping them in a separate address space.  See also the `bss` and `gp` notes below.

    NOTE: `begin_low_page()` and `end_low_page()` don't properly track addresses if used in a scope, so don't!

- `regs.inc`: A register file is a tiny address space!

    A few registers are reserved for the 6502 CPU and PPU, so they can keep state in registers across yield; I protect these by not defining their common name. This isn't effective on the PPU in this version, but it will come in handy with mid-scanline processing. Registers that are dedicated on the CPU are free on the RSP under names like `sp_*`. Any regs that are not dedicated will be clobbered on yield.

- `tlb.asm`: TLB init, static and dynamic (add-only) TLB page allocation. New pages are added by CPU init and mappers to swap and mirror banks in CPU address space.

- `lib/gp_rel.inc`

    I've reserved `gp` to point somewhere between code and bss so it can address both. The `ls_gp()` macro uses `gp`-relative addressing to do a load or store in one instr, and `la_gp()` loads a full address with `addi r, gp, X`. This checks the range, too; bass won't warn on out-of-range immediates.

- `lib/bss.inc`: `begin_bss()` and `end_bss()` are the same as `{begin/end}_low_page()`, but `bss_base` is set up so that it can be reached by the `{ls/la}_gp()` macros. Unlike a traditional `.bss` segment, this is not actually zeroed on init, though it probably should be.

    NOTE: These macros don't work properly in a scope!

- `exception.asm`: VR4300 COP0 exception inits and vector. The exception vector acknowledges interrupts and passes control off to the various handlers. It handles one exception (TLB modifiction, for write protect) and displays an error for the rest. Includes support for debugging hangs (via the timer interrupt) and memory access (via the watch exception).

### Scheduling

- `scheduler.asm`: Cooperative scheduler for the CPU, using emulated cycle counts to sequence tasks.
- `ucode_scheduler.asm`: Cooperative round robin scheduler for the RSP.
- `intcb.asm`: The interrupt callback task, multiplexes the frame task with SI and PI callbacks, to avoid wasting scheduler time on many top-level tasks. This task either wants to run immediately (cycle 0) or never (cycle -1).
- `frame.asm`: Frame task, the glue holding together the refresh loop. Controller polling, VI and RDP wait, RDP execution, menu rendering, profiling.

### Hardware interfacing

- `lib/n64.inc`, `lib/n64_gfx.inc`, `lib/n64_rsp.inc`: RCP definitions and convenience macros.

    These are from krom's [N64 Bare Metal](https://github.com/PeterLemon/N64) repo, full of many excellent examples and tests for every aspect of the N64. I've added a few things, notably MIPS cache ops.

- `dlist.asm`: Static RDP display lists for NES rendering and profile bars, to keep it simple there is one for each framebuffer
- `ai.asm`: Audio init and scheduling.
- `pi.asm`: Cartridge bus DMA, used for NES ROM load and save to SRAM, sync or async
- `rsp.asm`: RSP init, runs completion vectors on interrupt and restarts (unless idle), restarts on incoming request if idle.
- `si.asm`: Controller access, async
- `vi.asm`: Video init and scheduling, simple double buffer, RDP interrupt handler, simple text blitting

### Emulation

- `timing.asm`: All model-dependent timing info, currently NTSC or PAL, selectable at build time.

#### CPU

- `cpu.asm`: 6502 memory layout and init, instruction fetch (`FetchOpcode`), interrupts, and the building blocks of the opcodes.
- `opcodes.asm`: Two-instruction entries for all (official) opcodes, mostly jumps into addressing modes in `cpu.asm`, distinguished by the instruction in the delay slot.
- `cpu_io.asm`, `cpu_ppu.asm`: Read and write handlers for I/O (joypad), APU, and PPU, mostly jump tables and calls into `apu.asm` and `ppu.asm`. Async controller polling is in `cpu_io.asm`, started by the frame loop (this probably should be in `frame.asm` instead).

#### PPU

- `ppu.asm`: PPU task, which builds conv buffers to send to the ucode. Register read/write handlers.
- `ppu_tables.asm`: RGB palette LUT, bit reversal for horizontal sprite flip
- `ucode_ppu.asm`: PPU ucode task, tile conversion and sprite blitting
- `ucode_tables.asm`: Mostly constants to be loaded into VU registers for tile conversion. Also APU sequencer and mixer tables.

#### APU

- `apu.asm`: APU frame task, which runs on the frame counter (1/4 frame) clock, and APU DMC task, which runs at 1/8th the DMC rate. Register read/write handlers. These all write alists as needed.
- `ucode_apu.asm`: APU ucode task, audio synthesis

#### Cartridge

- `rom.asm`: NES ROM loading, sets defaults for mapper 0 and provides routines for building mappers.
- `mappers/*`: A file for each supported class of cart hardware. CPU and PPU memory map init (TLB and hooks), register handlers.

### Etc

- `lib/debug_print.asm`: String copies and integer formatting. Supports outputting to an IS Viewer debug port, I've used this with cen64's `-is-viewer` option.
- `profile_bars.asm`: This unconscionable code sets the corners of rectangles in the profile bar dlist.
- `menu.asm`: A simple menu UI, written directly to the framebuffer.
- `save.asm`: SRAM save and associated UI (error and success messages)
- `N64_BOOTCODE.BIN`: Required (with a 6102 CIC) to pass the IPL checksum, loads the first 1MB into RDRAM at boot.
- `font.bin`: 8x8 1bpp font
