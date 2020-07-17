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

// Init dlist buffers
  la_gp(t0, dlists)
  lli t1, num_dlists
-
  sw r0, 0(t0)
  sw r0, 4(t0)
  addi t1, -1
  bnez t1,-
  addi t0, 8

  lli t1, -1
  ls_gp(sb t1, running_dlist_idx)

// Clear pending interrupts
  sw r0, VI_V_CURRENT_LINE(t0)

  lui t0, MI_BASE
  lli t1, MI_CLEAR_DP_INT
  sw t1, MI_INIT_MODE(t0)

// Reset RDP
  lui t2, DPC_BASE
  sw r0, DPC_START (t2)
  sw r0, DPC_END (t2)
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

// Spinning on DPC_STATUS (from the CPU, at least) seems to reliably hang
// the RDP, or something, so keep we'll track of whether something is
// running ourselves, via the DP interrupt.

// a2: idx
WaitForDlist:
  sll t0, a2, 3
  add t0, gp
-
  lw t1, dlists + 0 - gp_base (t0)
  bnez t1,-
  nop
  jr ra
  nop

// syscall QUEUE_DLIST_SYSCALL
// a0: start
// a1: end
// a2: idx
// returns 1 in v1 if successful

scope QueueDlist: {
  ls_gp(lb v1, running_dlist_idx)

  bgez v1,+
  nop

// Nothing running yet, start this one immediately.
// TODO does this need to check for busy/valid?
  lui k0, DPC_BASE
  //lli v1, SET_FRZ
  //sw v1, DPC_STATUS (k0)

  sw a0, DPC_START (k0)
  sw a1, DPC_END (k0)
  ls_gp(sb a2, running_dlist_idx)

  //lli v1, CLR_FRZ
  //sw v1, DPC_STATUS (k0)
  //lw r0, DPC_STATUS (k0)

  //sw a0, DPC_START (k0)
  //sw a1, DPC_END (k0)

  j done
  lli v1, 1

+
// Already running a dlist, queue this one if the slot is open
  sll k0, a2, 3
  add k0, gp
  lw v1, dlists + 0 - gp_base (k0)
  bnez v1, done
  lli v1, 0

  sw a0, dlists + 0 - gp_base (k0)
  sw a1, dlists + 4 - gp_base (k0)
  lli v1, 1

done:
  jr k1
  nop
}

scope DP_Interrupt: {
  ls_gp(sd t0, exception_regs + t0*8)
  ls_gp(sd t1, exception_regs + t1*8)
  ls_gp(sd t2, exception_regs + t2*8)

  ls_gp(lbu t0, running_dlist_idx)
  subi t1, t0, frame_dlist_idx
  bnez t1,+
// Expose the framebuffer if this was the frame dlist finishing
  ls_gp(lw k0, active_framebuffer)
  ls_gp(sw r0, active_framebuffer)
  ls_gp(sw k0, finished_framebuffer)
+

// Mark it free
  sll k0, t0, 3
  add k0, gp
  sw r0, dlists + 0 - gp_base (k0)

// Look for the next one to run
  lli t1, -1
  ls_gp(sb t1, running_dlist_idx)
  move t1, t0
-
  addi t1, 1
  lli t2, num_dlists
  beq t1, t2,+
  addi k0, 8
  lw t2, dlists + 0 - gp_base (k0)
  beqz t2,-
  nop

  j found
  nop

+
  lli t1, 0
  move k0, gp
-
  lw t2, dlists + 0 - gp_base (k0)
  beqz t2,+
  nop
found:
  ls_gp(sb t1, running_dlist_idx)
// Run it
  lui t1, DPC_BASE
  //lli t0, SET_FRZ
  //sw t0, DPC_STATUS (t1)
  lw t0, dlists + 4 - gp_base (k0)
  sw t2, DPC_START (t1)
  sw t0, DPC_END (t1)

  //lli k0, CLR_FRZ
  //sw k0, DPC_STATUS (t1)
  //lw r0, DPC_STATUS (t1)

  //sw t2, DPC_START (t1)
  //sw t0, DPC_END (t1)

  j done
  nop
+
  addi k0, 8
  bne t1, t0,-
  addi t1, 1

done:
  ls_gp(ld t0, exception_regs + t0*8)
  ls_gp(ld t1, exception_regs + t1*8)
  ls_gp(ld t2, exception_regs + t2*8)

if {defined PROFILE_RDP} {
  lui k0, DPC_BASE
  lw k0, DPC_CLOCK (k0)
  ls_gp(sw k0, frame_rdp_cycles)
}
  jr k1
  nop
}

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
// a1 = max chars
scope PrintDebugToScreen: {
  move t9, a1
  move t4, t9
  la a1, debug_buffer
  la a2, debug_buffer_cursor
  lw a2, 0 (a2)
  move a3, a0
  lli t8, 0xffff

  bne a1, a2, char_loop
  nop
  jr ra
  nop

char_loop:
  lbu t0, 0 (a1)
  lli t1, 0xff // invert video
  bne t0, t1,+
  lli t1, 0xa  // newline
  j char_loop_continue
  xori t8, 0xfffe
+
  bnez t4,+
  addi t4, -1
  lli t0, 0xa
  addi a1, -1
+
// line wrap
  bne t0, t1,+
  sll t0, 3
  addi a3, (width*2)*8  // move down a line
  move t4, t9
  j char_loop_continue
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
char_loop_continue:
  addi a1, 1
  bne a1, a2, char_loop
  nop

  jr ra
  nop
}

// This does not perform the final render, it only assembles the dlist
// a0, a1: X, Y pixel coordinates
scope PrintDebugToScreenRDP: {
Start:
  addi sp, 8
  sw ra, -8(sp)

  lli a2, text_dlist_idx
  jal VI.WaitForDlist
  nop

  lw ra, -8(sp)
  addi sp, -8

  la a3, text_dlist

// copy setup
// TODO this only needs to be done once
  la t0, TextStaticDlist
  lli t1, (TextStaticDlist.End-TextStaticDlist)/16

-
  ld t2, 0(t0)
  ld t3, 8(t0)
  sd t2, 0(a3)
  sd t3, 8(a3)
  addi a3, 16
  addi t1, -1
  bnez t1,-
  addi t0, 16

  ls_gp(sw a3, text_dlist_ptr)

Continue:
  move s8, a0
  ls_gp(lw a3, text_dlist_ptr)

// write characters
  lli t3, 0 // normal (not inverse) mode
  la t9, debug_buffer
  ls_gp(lw t8, debug_buffer_cursor)

  beq t9, t8, char_loop_end
  nop

char_loop:
  lbu t2, 0 (t9)
  lli t1, 0xff // invert video
  bne t2, t1, no_invert
  lli t1, 0xa  // newline

// Change palettes for inverse video
// FIXME this isn't accounted for in the size of text_dlist
  la t0, TextStaticDlist.SetNormal
  lli t1, (TextStaticDlist.SetNormalEnd-TextStaticDlist.SetNormal)/8
  bnez t3,+
  xori t3, 1
  la t0, TextStaticDlist.SetInverse
+
-
  ld t2, 0(t0)
  sd t2, 0(a3)
  addi a3, 8
  addi t1, -1
  bnez t1,-
  addi t0, 8

  j char_loop_continue
  nop

no_invert:
  subi t4, a0, width - 32 - 8
  bltz t4,+
  nop
  lli t2, 0xa
  addi t9, -1
+
// line wrap
  bne t2, t1,+
  nop
  move a0, s8
  j char_loop_continue
  addi a1, 8
+

// write rects
  ls_gp(ld t0, TextStaticDlist.TextureRectangleTemplate)
  dsll t1, a0, 2+12 // XH=x<<2
  or t0, t1
  dsll t1, a1, 2+0 // YH=y<<2
  or t0, t1
  addi t1, a0, 7
  dsll32 t1, 2+44 // XL=(x+7)<<2
  or t0, t1
  addi t1, a1, 7
  dsll32 t1, 2+32-32 // YL=(x+7)<<2
  or t0, t1
  andi t1, t2, 0b11
  addi t1, TextStaticDlist.render_font_b0_tile
  dsll t1, 24 // Tile = render_font_b0_tile + char&0b11
  or t0, t1
  sd t0, 0(a3)

  ls_gp(ld t0, TextStaticDlist.TextureRectangleTemplate+8)
  srl t1, t2, 2
  dsll32 t1, 3+5+48-32  // S=(char>>2)*8<<5
  or t0, t1
  sd t0, 8(a3)
  addi a3, 16

  addi a0, 8
char_loop_continue:
  addi t9, 1
  bne t9, t8, char_loop
  nop

char_loop_end:
  jr ra
  ls_gp(sw a3, text_dlist_ptr)

Render:
  ls_gp(lw a3, text_dlist_ptr)
// write NOP
  sd r0, 0(a3)
  addi a3, 8
// write sync
  ls_gp(ld t0, TextStaticDlist.SyncFull)
  addi a3, 8
  sd t0, -8(a3)
// write another NOP
  sd r0, 0(a3)
  addi a3, 8

// run RDP
  la a0, text_dlist
  ls_gp(sw a0, text_dlist_ptr)
  move a1, a3
  lli a2, text_dlist_idx

-
  syscall QUEUE_DLIST_SYSCALL
  nop
  beqz v1,-
  nop

  jr ra
  nop
}

}

begin_bss()
align(4)

finished_framebuffer:; dw 0
active_framebuffer:; dw 0
text_dlist_ptr:; dw 0

constant frame_dlist_idx(0)
constant prof_dlist_idx(1)
constant text_dlist_idx(2)
constant num_dlists(3)

dlists:
  fill num_dlists*8

vi_interrupt_wait:; db 0
running_dlist_idx:; db 0

align(4)
end_bss()
