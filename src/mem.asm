// Memory layout

// MB 1
constant nes_rom(0x8010'0000)

// MB 0
// Allocate back from the end of the first MB
constant nes_extra_ram_size(0x2000)
constant nes_extra_ram(nes_rom - nes_extra_ram_size)
constant nes_extra_ram_save_copy(nes_extra_ram - nes_extra_ram_size)
constant nes_extra_ram_save_verify(nes_extra_ram_save_copy - nes_extra_ram_size)
constant nes_mmc5_ram1(nes_extra_ram_save_verify - nes_extra_ram_size)
constant nes_mmc5_ram2(nes_mmc5_ram1 - nes_extra_ram_size)
constant nes_mmc5_ram3(nes_mmc5_ram2 - nes_extra_ram_size)
constant nes_mmc5_ram4(nes_mmc5_ram3 - nes_extra_ram_size)
constant nes_mmc5_ram5(nes_mmc5_ram4 - nes_extra_ram_size)
constant nes_mmc5_ram6(nes_mmc5_ram5 - nes_extra_ram_size)
constant nes_mmc5_ram7(nes_mmc5_ram6 - nes_extra_ram_size)
constant chrram(nes_mmc5_ram7 - 0x8000)
constant four_screen_ram(chrram - 0x800)
constant last_backfill(four_screen_ram)

// Low page is 2 4k pages in physical memory
constant tlb_page_size(0x1000)
constant low_page_end((last_backfill-0x8000'0000)/0x2000*0x2000)
constant low_page_ram_base(low_page_end-tlb_page_size*2)
constant low_page_base(0x2000)
variable low_page_pc(low_page_base)

constant bss_base(0x8000'e000)
include "lib/bss.inc"

begin_bss()

align(8)
call_stack:
  fill 8*24

end_bss()

// MB 2
constant framebuffer0(0xa020'0000)
constant framebuffer1(0xa024'0000)

constant num_abufs(10)
// 4 bytes (2 channel 16-bit) per sample
constant abuf_size((abuf_samples * 4 + 7)/8*8)
constant audiobuffer(0xa028'0000)

constant text_dlist(audiobuffer + abuf_size * num_abufs)
constant two_end(text_dlist + (TextStaticDlist.End-TextStaticDlist) + 16*(debug_buffer_size+2))

if two_end > 0xa030'0000 {
error "out of space in 2nd MB"
}

// MB 3
constant rgb_palette0(0x8030'0000)
constant blank_palette0(rgb_palette0+0x20*2)
constant rgb_palette1(blank_palette0+0x20*2)
constant blank_palette1(rgb_palette1+0x20*2)
constant frame_rgb_palette(blank_palette1+0x20*2)

// Layout of RDRAM<->RSP conversion buffers
evaluate conv_src_pc(0)
macro conv_src(name, evaluate size) {
constant {name}({conv_src_pc})
global evaluate conv_src_pc({conv_src_pc} + {size})
}

conv_src(src_bg_pat, 32*2*8)
conv_src(src_bg32_pat, 2*8)
conv_src(src_sp_pat, 8*2*8)
conv_src(src_bg_atr, 32*8)
conv_src(src_bg32_atr, 8)
conv_src(src_sp_atr, 8*8)
conv_src(src_bg_x, 8)
conv_src(src_sp_x, 8*8)
conv_src(src_sp_pri, 8)
conv_src(src_mask, 1)

constant conv_src_size(({conv_src_pc}+15)/16*16)

constant conv_dst_bg_size(32*4*8)
constant conv_dst_sp_size(32*8*8)

constant num_conv_buffers(240/8)
constant conv_src_buffer(((frame_rgb_palette & 0x1fff'ffff) | 0xa000'0000) + 0x20*2)
constant conv_dst_bg_buffer0(conv_src_buffer + conv_src_size * num_conv_buffers)
constant conv_dst_sp_buffer0(conv_dst_bg_buffer0 + conv_dst_bg_size * num_conv_buffers)
constant conv_dst_bg_buffer1(conv_dst_sp_buffer0 + conv_dst_sp_size * num_conv_buffers)
constant conv_dst_sp_buffer1(conv_dst_bg_buffer1 + conv_dst_bg_size * num_conv_buffers)

evaluate alist_pc(0)
macro alist_res(name, evaluate size) {
constant {name}({alist_pc})
global evaluate alist_pc({alist_pc} + {size})
}

alist_res(alist_SampleDelta, 4)

alist_res(alist_P1Timer, 2)
alist_res(alist_P2Timer, 2)
alist_res(alist_TriTimer, 2)
alist_res(alist_NoiseTimer, 2)
alist_res(alist_DMCTimer, 2)

alist_res(alist_P1Env, 1)
alist_res(alist_P2Env, 1)
alist_res(alist_NoiseEnv, 1)

alist_res(alist_P1Duty, 1)
alist_res(alist_P2Duty, 1)
alist_res(alist_Flags, 1)

alist_res(alist_DMCLoad, 1)
alist_res(alist_DMCSampleCount, 1)
alist_res(alist_DMCSamples, 10)

constant alist_entry_size(32)
constant alist_entry_size_shift(5)

if alist_entry_size != (({alist_pc}+DCACHE_LINE-1)/DCACHE_LINE*DCACHE_LINE) {
  error "recalculate alist_entry_size"
}
constant num_alists(16)

constant alist_buffer(conv_dst_sp_buffer1 + conv_dst_sp_size * num_conv_buffers)
constant three_end(alist_buffer + alist_entry_size * num_alists)

if three_end > 0xa040'0000 {
error "out of space in 3rd MB"
}

constant gp_base(0x8000'8000)
include "lib/gp_rel.inc"

macro begin_low_page() {
  pushvar base
  pushvar origin
  close_output_file()
  base low_page_pc
}

// XXX Does not work in a scope!
macro end_low_page() {
  if pc() > low_page_end {
    error "out of space in low page"
  }

  global variable low_page_pc(pc())
  reopen_output_file()
  pullvar origin
  pullvar base
}

begin_low_page()
align_dcache()

// 1 dw per 256 byte page
// These are the address of the data in N64 address space, minus the NES address.
// An address is negative if the range has a handler, non-negative if it can be
// used to load/store directly (through the TLB).
cpu_read_map:;  fill 4*0x100
cpu_write_map:; fill 4*0x100

if pc()-0x800 & 0xfff != 0 {
  print pc(), "\n"
  error "nes_ram-0x800 must be 4K aligned"
}
nes_ram:; fill 0x800
end_low_page()

// Global static TLB mappings
// 0x0040'0000-0x0048'0000 - Initially all entries are set to invalid 8K pages here

// Index 1: 0x0080'0000-0x0100'0000 - All RDRAM (8MB)
constant tlb_rdram(0x0080'0000)
constant rdram_mask(0x7f'ffff)

// Index 2: 0x0100'0000'0x0180'0000 - All RDRAM (8MB), write protected
constant tlb_ro_rdram(0x0100'0000)

// 0x0180'2000- free for mappers, etc
constant tlb_free(0x0180'2000)
