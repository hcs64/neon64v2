scope VI: {
Init:
  addi sp, 8
  sw ra, -8(sp)

// Clear screen before enabling VI
  la t0, framebuffer0
  ls_gp(sw t0, active_framebuffer)
  jal FillScreen
  lli a0, 0x0001

  lui t0, VI_BASE

  la t1, framebuffer0
  sw t1, VI_ORIGIN(t0)

// Setup VI

// 16-bit color (0), no AA, resampling only (8)
  lli t1, (%10 << 0)|(%10 << 8)
  sw t1, VI_STATUS(t0)
// width (pixels)
  lli t1, width
  sw t1, VI_WIDTH(t0)
// interrupt at start of vblank
  //lli t1, 121 //0x200
  lli t1, 0x200
  sw t1, VI_V_INTR(t0)
// hsync width (pixels)(0), color burst width (pixels)(8), vsync height (lines)(16), color burst start (pixels from hsync)(20)
  la t1, (50<<0)|(30<<8)|(5<<16)|(58<<20)
  sw t1, VI_TIMING(t0)
// v sync, lines per frame
  lli t1, 525
  sw t1, VI_V_SYNC(t0)
// h sync, 1/4 pixels per line
  lli t1, 0xc15
  sw t1, VI_H_SYNC(t0)
// h sync leap, same as h sync
  la t1, 0x0c15'0c15
  sw t1, VI_H_SYNC_LEAP(t0)
// start of active video (pixels)(16), end of active video (pixels)(0)
  la t1, (98<<16)|(738<<0)
  sw t1, VI_H_VIDEO(t0)
// start of active video (lines)(16), end of active video (lines)(0)
  la t1, (32<<16)|(512<<0)
  sw t1, VI_V_VIDEO(t0)
// color burst start (lines?)(16), color burst end (lines?)(0)
  la t1, (14<<16)|(516<<0)
  sw t1, VI_V_BURST(t0)
// h scale, 0 subpixel
  lli t1, hscale_width * 0x400 / 640
  sw t1, VI_X_SCALE(t0)
// v scale, 0 subpixel
  lli t1, vscale_height * 0x400 / 240
  sw t1, VI_Y_SCALE(t0)

  la t1, framebuffer1
  ls_gp(sw t1, active_framebuffer)
  ls_gp(sw r0, finished_framebuffer)

  jal FillScreen
  lli a0, 0x0001

  ls_gp(sb r0, vi_interrupt_wait)
  ls_gp(sb r0, dp_interrupt_wait)

// Clear pending interrupts
  sw r0, VI_V_CURRENT_LINE(t0)

  lui t0, MI_BASE
  lli t1, MI_CLEAR_DP_INT
  sw t1, MI_INIT_MODE(t0)

// Reset RDP
  lui t2, DPC_BASE
  lli t1, CLR_XBS|CLR_FRZ|CLR_FLS
  sw t1, DPC_STATUS (t2)

// Enable interrupts
  lli t1, MI_MASK_SET_VI|MI_MASK_SET_DP
  sw t1, MI_INTR_MASK(t0)

  lw ra, -8(sp)
  jr ra
  addi ra, -8

VI_Interrupt:
  ls_gp(sd t0, exception_regs + t0*8)

  ls_gp(lw t0, finished_framebuffer)
  beqz t0,+
  ls_gp(sw r0, finished_framebuffer)

  ls_gp(sd t1, exception_regs + t1*8)
  ls_gp(sd t2, exception_regs + t2*8)

  lui t1, VI_BASE
  lw t2, VI_ORIGIN(t1)
  sw t0, VI_ORIGIN(t1)

  lui t0, 0xa000
  or t2, t0
  ls_gp(sw t2, active_framebuffer)

  ls_gp(ld t1, exception_regs + t1*8)
  ls_gp(ld t2, exception_regs + t2*8)
+

  ls_gp(sb r0, vi_interrupt_wait)
  jr k1
  ls_gp(ld t0, exception_regs + t0*8)

DP_Interrupt:
  ls_gp(lw k0, active_framebuffer)
  ls_gp(sw r0, active_framebuffer)
  ls_gp(sb r0, dp_interrupt_wait)
  ls_gp(sw k0, finished_framebuffer)

if {defined PROFILE_RDP} {
  lui k0, DPC_BASE
  lw k0, DPC_CLOCK (k0)
  ls_gp(sw k0, frame_rdp_cycles)
}
  jr k1
  nop

// Returns framebuffer in a0, blocks until available
GetFramebuffer:
-
  ls_gp(lw a0, active_framebuffer)
  beqz a0,-
  nop

  jr ra
  nop

StopDP:
  // TODO, just set frozen?
  jr ra
  nop

// a0 = color
FillScreen:
  ls_gp(lw t0, active_framebuffer)
  dsll t2, a0, 16
  or t2, a0
  dsll32 t3, t2, 0
  or t2, t3

  li t3, width*height*2

-;sd t2, 0(t0)
  addi t0,8
  bgtz t3,-
  addi t3,-8

  jr ra
  nop

// a0 = framebuffer pos
scope PrintDebugToScreen: {
  lli t4, 32-1
  la a1, debug_buffer
  la a2, debug_buffer_cursor
  lw a2, 0 (a2)
  move a3, a0
  lli t8, 0xffff

char_loop:
  lbu t0, 0 (a1)
  lli t1, 0xff // invert video
  bne t0, t1,+
  lli t1, 0xa  // newline
  j char_loop_end
  xori t8, 0xfffe
+
  bnez t4,+
  addi t4, -1
// line wrap
  lli t0, 0xa
  addi a1, -1
+
  bne t0, t1,+
  sll t0, 3
  addi a3, (width*2)*8  // move down a line
  lli t4, 32-1
  j char_loop_end
  move a0, a3
+

  la t1, font
  add t0, t1
  ld t0, 0(t0)
  li t2, 7 // rows to do

-;li t3, 7 // pixels to do

-;bltz t0,+
  move t1, t8
  xori t1, 0xfffe
+;sh t1, 0(a0)
  addi a0, 2
  dsll t0, 1

  bnez t3,-
  addi t3, -1

  addi a0, (width*2)-(8*2) // move down a line

  bnez t2,--
  addi t2, -1

  addi a0, (8*2)-(8*width*2) // move forward a char
char_loop_end:
  addi a1, 1
  bne a1, a2, char_loop
  nop

  jr ra
  nop
}

}


begin_bss()
align(4)

finished_framebuffer:; dw 0
active_framebuffer:; dw 0

vi_interrupt_wait:; db 0
dp_interrupt_wait:; db 0

align(4)
end_bss()
