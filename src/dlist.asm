arch n64.rdp

constant margin(16)

macro render_dlist(idx) {

scope RenderDlist{idx}: {
constant tlut_bg_tile(0)
constant load_bg_tile(1)
constant load_sp_tile(2)
constant render_bg_tile(3)
constant render_sp_tile(4)
constant tlut_fg_tile(5)

constant pal_bg_tmem(0x800)
constant pal_fg_tmem(0x800+0x20*2*4)

  Sync_Pipe

  Set_Scissor 0<<2,0<<2, 0,0, (width-1)<<2,(height-1)<<2 // Set Scissor: XH 0.0,YH 0.0, Scissor Field Enable Off,Field Off, XL width.0,YL height.0
  Set_Other_Modes CYCLE_TYPE_FILL // Set Other Modes
SetColorImageCmd:
  Set_Color_Image IMAGE_DATA_FORMAT_RGBA,SIZE_OF_PIXEL_16B,width-1, framebuffer0 // Set Color Image: FORMAT RGBA,SIZE 16B,WIDTH, DRAM ADDRESS $00200000
constant SetColorImageAddr(SetColorImageCmd+4)

ClearCmd:
  Set_Fill_Color $00010001 // Set Fill Color: PACKED COLOR 16B R5G5B5A1 Pixels
constant ClearColor(ClearCmd+4)
  Fill_Rectangle (width-1)<<2,(height-1)<<2, 0<<2,0<<2 // Fill Rectangle: XL width.0,YL height.0, XH 0.0,YH 0.0

  Set_Scissor margin<<2,0<<2, 0,0, (margin+256-1)<<2,(240-1)<<2 // Set Scissor: Scissor Field Enable Off,Field Off

  Set_Other_Modes EN_TLUT|CVG_DEST_ZAP|ALPHA_COMPARE_EN|CYCLE_TYPE_COPY

  Set_Tile 0,0,0, pal_bg_tmem/8, tlut_bg_tile, 0, 0,0,0,0, 0,0,0,0
  Set_Tile 0,0,0, pal_fg_tmem/8, tlut_fg_tile, 0, 0,0,0,0, 0,0,0,0

  // Note: The line width must be 0 here when used with Load Block; it is used as the stride
  // to skip *between* lines, not the width of a line.
  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, 0/8, load_bg_tile,0, 0,0,0,0, 0,0,0,0
  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, 0/8, load_sp_tile,0, 0,0,0,0, 0,0,0,0

  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_4B,256/2/8, 0/8, render_bg_tile,0, 0,0,0,0, 0,0,0,0
  Set_Tile_Size 0,0,render_bg_tile,(256-1)<<2,(16-1)<<2

  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,256/8, 0/8, render_sp_tile,0, 0,0,0,0, 0,0,0,0
  Set_Tile_Size 0,0,render_sp_tile,(256-1)<<2,(8-1)<<2

  evaluate xh((margin+0)<<2)
  evaluate xl((margin+256-1)<<2)
  evaluate sl(0<<5)
  evaluate tl(0<<5)
  // 4x dsdx is needed for Copy mode with CI
  evaluate dsdx(4<<10)
  evaluate dtdy(1<<10)

  define y_block(0)
  while {y_block} < 15 {

    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_RGBA,SIZE_OF_PIXEL_16B,0, rgb_palette{idx}&0x7f'ffff
    Load_Tlut 0<<2,0<<2, tlut_bg_tile, 63<<2,0<<2 // Load Tlut: SL 0.0,TL 0.0, SH 63.0,TH 0.0

// Background Sprites
    evaluate dram_addr(conv_dst_sp_buffer{idx}+{y_block}*2*conv_dst_sp_size)
    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, {dram_addr}&0x7f'ffff
    Load_Block 0, 0, load_sp_tile, 256*8-1, 2048/(256/8)

    evaluate yh(({y_block}*16+0)<<2)
    evaluate yl(({y_block}*16+8-1)<<2)
    Texture_Rectangle {xl},{yl}, render_sp_tile, {xh},{yh}, {sl},{tl}, {dsdx},{dtdy}

    evaluate dram_addr(conv_dst_sp_buffer{idx}+({y_block}*2+1)*conv_dst_sp_size)
    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, {dram_addr}&0x7f'ffff
    Load_Block 0, 0, load_sp_tile, 256*8-1, 2048/(256/8)

    evaluate yh(({y_block}*16+8)<<2)
    evaluate yl(({y_block}*16+16-1)<<2)
    Texture_Rectangle {xl},{yl}, render_sp_tile, {xh},{yh}, {sl},{tl}, {dsdx},{dtdy}

// Background
    evaluate dram_addr(conv_dst_bg_buffer{idx}+{y_block}*2*conv_dst_bg_size)
    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, {dram_addr}&0x7f'ffff
    Load_Block 0, 0, load_bg_tile, 128*16-1, 2048/(256/2/8)

    evaluate yh(({y_block}*16+0)<<2)
    evaluate yl(({y_block}*16+16-1)<<2)

    Texture_Rectangle {xl},{yl}, render_bg_tile, {xh},{yh}, {sl},{tl}, {dsdx},{dtdy}

// Foreground sprites
    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_RGBA,SIZE_OF_PIXEL_16B,0, blank_palette{idx}&0x7f'ffff
    Load_Tlut 0<<2,0<<2, tlut_bg_tile, 31<<2,0<<2 // Load Tlut: SL 0.0,TL 0.0, Tile 0, SH 31.0,TH 0.0
    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_RGBA,SIZE_OF_PIXEL_16B,0, rgb_palette{idx}&0x7f'ffff
    Load_Tlut 0<<2,0<<2, tlut_fg_tile, 31<<2,0<<2 // Load Tlut: SL 32.0,TL 0.0, Tile 0, SH 63.0,TH 0.0

    evaluate dram_addr(conv_dst_sp_buffer{idx}+{y_block}*2*conv_dst_sp_size)
    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, {dram_addr}&0x7f'ffff
    Load_Block 0, 0, load_sp_tile, 256*8-1, 2048/(256/8)

    evaluate yh(({y_block}*16+0)<<2)
    evaluate yl(({y_block}*16+8-1)<<2)
    Texture_Rectangle {xl},{yl}, render_sp_tile, {xh},{yh}, {sl},{tl}, {dsdx},{dtdy}

    evaluate dram_addr(conv_dst_sp_buffer{idx}+({y_block}*2+1)*conv_dst_sp_size)
    Sync_Load
    Set_Texture_Image IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, {dram_addr}&0x7f'ffff
    Load_Block 0, 0, load_sp_tile, 256*8-1, 2048/(256/8)

    evaluate yh(({y_block}*16+8)<<2)
    evaluate yl(({y_block}*16+16-1)<<2)
    Texture_Rectangle {xl},{yl}, render_sp_tile, {xh},{yh}, {sl},{tl}, {dsdx},{dtdy}

    evaluate y_block({y_block} + 1)
  }

End:
  No_Op
  Sync_Full
EndSync:
  No_Op
}
}

align(8)
render_dlist(0)
render_dlist(1)

if {defined PROFILE_BARS} {
scope ProfDlist: {
  Sync_Pipe
  Set_Scissor 0<<2,0<<2, 0,0, (width-1)<<2,(height-1)<<2
  Set_Other_Modes CYCLE_TYPE_FILL

constant frame_border(2)
constant frame_x(margin)
constant frame_y(240-28)
constant frame_w(256)
constant frame_h(16)
  Set_Fill_Color $0001'0001
  Fill_Rectangle (frame_x+frame_w-1)<<2,(frame_y+frame_h-1)<<2, frame_x<<2,frame_y<<2

  Sync_Pipe
  Set_Fill_Color $ffff'ffff
  Fill_Rectangle (frame_x+frame_border-1)<<2,(frame_y+frame_h+frame_border-1)<<2, frame_x<<2,(frame_y-frame_border)<<2
  Fill_Rectangle (frame_x+frame_w/2+frame_border-1)<<2,(frame_y+frame_h+frame_border-1)<<2, (frame_x+frame_w/2)<<2,(frame_y-frame_border)<<2
  Fill_Rectangle (frame_x+frame_w+frame_border-1)<<2,(frame_y+frame_h+frame_border-1)<<2, (frame_x+frame_w)<<2,(frame_y-frame_border)<<2

constant rsp_x(frame_x)
constant rsp_y(frame_y+4)
constant rsp_w(256)
constant rsp_h(4)

constant cpu_x(frame_x)
constant cpu_y(rsp_y+rsp_h)
constant cpu_w(256)
constant cpu_h(4)

  Sync_Pipe
// VBlank wait: Dark green
// Drawn first so the others can overwrite it in case the totals are off
  Set_Fill_Color $03c1'03c1
VBLRect:
  Fill_Rectangle (cpu_x+cpu_w-1)<<2,(cpu_y+cpu_h-1)<<2, cpu_x<<2,cpu_y<<2

  Sync_Pipe
// CPU: Green
  Set_Fill_Color $07c1'07c1
CPURect:
  Fill_Rectangle (cpu_x+cpu_w-1)<<2,(cpu_y+cpu_h-1)<<2, cpu_x<<2,cpu_y<<2

  Sync_Pipe
// APU: Grey
  Set_Fill_Color $7bdf'7bdf
APURect:
  Fill_Rectangle (cpu_x+cpu_w-1)<<2,(cpu_y+cpu_h-1)<<2, cpu_x<<2,cpu_y<<2
if !{defined PROFILE_RDP} {
RSP_APU_Rect:
  Fill_Rectangle (rsp_x+rsp_w-1)<<2,(rsp_y+rsp_h-1)<<2, rsp_x<<2,rsp_y<<2
}

  Sync_Pipe
// PPU: Red
  Set_Fill_Color $f801'f801
PPURect:
  Fill_Rectangle (cpu_x+cpu_w-1)<<2,(cpu_y+cpu_h-1)<<2, cpu_x<<2,cpu_y<<2
if !{defined PROFILE_RDP} {
RSP_PPU_Rect:
  Fill_Rectangle (rsp_x+rsp_w-1)<<2,(rsp_y+rsp_h-1)<<2, rsp_x<<2,rsp_y<<2
}

  Sync_Pipe
// Scheduler: Blue
  Set_Fill_Color $28ff'28ff
SchedulerRect:
  Fill_Rectangle (cpu_x+cpu_w-1)<<2,(cpu_y+cpu_h-1)<<2, cpu_x<<2,cpu_y<<2

  Sync_Pipe
// Frame finish: Yellow
  Set_Fill_Color $ffc1'ffc1
FrameFinishRect:
  Fill_Rectangle (cpu_x+cpu_w-1)<<2,(cpu_y+cpu_h-1)<<2, cpu_x<<2,cpu_y<<2

if 1 != 1 {
  Sync_Pipe
// Exceptions: White
  Set_Fill_Color $ffff'ffff
ExceptionsRect:
  Fill_Rectangle (cpu_x+cpu_w-1)<<2,(cpu_y+cpu_h-1)<<2, cpu_x<<2,cpu_y<<2
}

if {defined PROFILE_RDP} {
  Sync_Pipe
// RDP: Red
  Set_Fill_Color $f801'f801
RDPRect:
  Fill_Rectangle (rsp_x+rsp_w-1)<<2,(rsp_y+rsp_h-1)<<2, rsp_x<<2,rsp_y<<2
}

End:
  No_Op
  Sync_Full
EndSync:
  No_Op
}
}

align(DCACHE_LINE)

scope TextStaticDlist: {
constant render_font_b0_tile(0)
constant render_font_b1_tile(1)
constant render_font_b2_tile(2)
constant render_font_b3_tile(3)
constant load_font_tile(4)
constant tlut_tile(5)
constant font_tmem(0)
constant tlut_tmem(0x800)
constant pal_b0(0)
constant pal_b1(1)
constant pal_b2(2)
constant pal_b3(3)
constant pal_inv_b0(4)
constant pal_inv_b1(5)
constant pal_inv_b2(6)
constant pal_inv_b3(7)

evaluate dsdx(4<<10)
evaluate dtdy(1<<10)

  Sync_Pipe

  Set_Other_Modes EN_TLUT|CVG_DEST_ZAP|ALPHA_COMPARE_EN|CYCLE_TYPE_COPY

  Sync_Tile
  Set_Tile 0,0,0, tlut_tmem/8, tlut_tile, 0, 0,0,0,0, 0,0,0,0

evaluate rep_i(0)

  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, font_tmem/8, load_font_tile,0, 0,0,0,0, 0,0,0,0
while {rep_i} < 4 {
  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_4B,256*8/4/2/8, font_tmem/8, render_font_b{rep_i}_tile,pal_b{rep_i}, 0,0,0,0, 0,0,0,0
  Set_Tile_Size 0,0,render_font_b{rep_i}_tile,(256*8/4-1)<<2,(8-1)<<2
evaluate rep_i({rep_i}+1)
}

  Sync_Load
  Set_Texture_Image IMAGE_DATA_FORMAT_RGBA,SIZE_OF_PIXEL_16B,0, TextStaticDlist.Palette&0x7f'ffff
  Load_Tlut 0<<2,0<<2, tlut_tile, 127<<2,0<<2 // Load Tlut: SL 0.0,TL 0.0, SH 127.0,TH 0.0

  Sync_Load
  Set_Texture_Image IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_8B,0, rdpfont&0x7f'ffff
  Load_Block 0, 0, load_font_tile, (256/4*8*8/2)-1, 2048/(256/4*8/2/8)

align(16)
End:
SyncFull:
  Sync_Full

SetNormal:
  Sync_Tile
evaluate rep_i(0)
while {rep_i} < 4 {
  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_4B,256*8/4/2/8, font_tmem/8, render_font_b{rep_i}_tile,pal_b{rep_i}, 0,0,0,0, 0,0,0,0
evaluate rep_i({rep_i}+1)
}
SetNormalEnd:

SetInverse:
  Sync_Tile
evaluate rep_i(0)
while {rep_i} < 4 {
  Set_Tile IMAGE_DATA_FORMAT_COLOR_INDX,SIZE_OF_PIXEL_4B,256*8/4/2/8, font_tmem/8, render_font_b{rep_i}_tile,pal_inv_b{rep_i}, 0,0,0,0, 0,0,0,0
evaluate rep_i({rep_i}+1)
}
SetInverseEnd:

TextureRectangleTemplate:
  Texture_Rectangle 0,0, 0, 0,0, 0,0, {dsdx},{dtdy}

AboutBackdropRect:
  Set_Fill_Color $0001'0001
  Fill_Rectangle (margin+31*8)<<2,(13*8)<<2, (margin+8)<<2,(3*8)<<2
AboutBackdropRectEnd:

align(8)
Palette:
// 0-4: Each palette selects a 1bpp plane
evaluate rep_j(0)
while {rep_j} < 4 {
  evaluate rep_i(0)
  while {rep_i} < 16 {
    if {rep_i} & (1<<{rep_j}) == 0 {
      dh 0x0001
    } else {
      dh 0xffff
    }
    evaluate rep_i({rep_i}+1)
  }
  evaluate rep_j({rep_j}+1)
}

// 4-8: Invert video
evaluate rep_j(0)
while {rep_j} < 4 {
  evaluate rep_i(0)
  while {rep_i} < 16 {
    if {rep_i} & (1<<{rep_j}) == 0 {
      dh 0xffff
    } else {
      dh 0x0001
    }
    evaluate rep_i({rep_i}+1)
  }
  evaluate rep_j({rep_j}+1)
}
}

arch n64.cpu
