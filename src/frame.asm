begin_bss()
last_frame_cpu_cycles:; dw 0
last_frame_ppu_cycles:; dw 0
last_frame_apu_cycles:; dw 0
if {defined PROFILE_RDP} {
frame_rdp_cycles:; dw 0
last_frame_rdp_cycles:; dw 0
} else {
frame_ppu_rsp_cycles:; dw 0
last_frame_ppu_rsp_cycles:; dw 0
frame_apu_rsp_cycles:; dw 0
last_frame_apu_rsp_cycles:; dw 0
}
last_frame_scheduler_cycles:; dw 0
frame_vblank_wait_cycles:; dw 0
last_frame_vblank_wait_cycles:; dw 0
if 1 != 1 {
frame_exception_cycles:; dw 0
last_frame_exception_cycles:; dw 0
}
frames_finished:; dw 0
conv_dst_idx:; db 0

end_bss()

StartFrame:
  sw r0, frame_cycles + int_cb_task*4 (r0)

// Account for everything in the previous frame
  lwu t1, frame_cycles + cpu_inst_task*4 (r0)
  lwu t0, frame_cycles + ppu_task*4 (r0)
  ls_gp(sw t1, last_frame_cpu_cycles)
  ls_gp(sw t0, last_frame_ppu_cycles)
  lwu t1, frame_cycles + apu_frame_task*4 (r0)
  lwu t2, frame_cycles + apu_dmc_task*4 (r0)
  add t1, t2
  lw t2, frame_scheduler_cycles (r0)
  ls_gp(sw t1, last_frame_apu_cycles)
  ls_gp(lw t1, frame_vblank_wait_cycles)
  ls_gp(sw t2, last_frame_scheduler_cycles)
  ls_gp(sw t1, last_frame_vblank_wait_cycles)

if !{defined PROFILE_RDP} {
  ls_gp(lw t1, frame_ppu_rsp_cycles)
  ls_gp(lw t2, frame_apu_rsp_cycles)
  ls_gp(sw t1, last_frame_ppu_rsp_cycles)
  ls_gp(sw t2, last_frame_apu_rsp_cycles)
}

if 1 != 1 {
  ls_gp(lw t2, frame_exception_cycles)
  ls_gp(sw r0, frame_exception_cycles)
  ls_gp(sw t2, last_frame_exception_cycles)
}

  sw r0, frame_cycles + cpu_inst_task*4 (r0)
  sw r0, frame_cycles + ppu_task*4 (r0)
  sw r0, frame_cycles + apu_frame_task*4 (r0)
  sw r0, frame_cycles + apu_dmc_task*4 (r0)
  sw r0, frame_scheduler_cycles (r0)

  jr ra
  nop

// Run from an RSP interrupt
ScheduleFinishFrame:
if !{defined PROFILE_RDP} {
  lui t0, SP_MEM_BASE
  lwu t1, SP_DMEM + dmem_cycle_counts + ppu_rsp_task * 4 (t0)
  sw r0, SP_DMEM + dmem_cycle_counts + ppu_rsp_task * 4 (t0)
  ls_gp(sw t1, frame_ppu_rsp_cycles)
  lwu t1, SP_DMEM + dmem_cycle_counts + apu_rsp_task * 4 (t0)
  sw r0, SP_DMEM + dmem_cycle_counts + apu_rsp_task * 4 (t0)
  ls_gp(sw t1, frame_apu_rsp_cycles)
}

  ls_gp(lw t0, frames_finished)
  addi t0, 1
  ls_gp(sw t0, frames_finished)

// Schedule to run in the interrupt task
  la_gp(t0, FinishFrame)
  ls_gp(sw t0, frame_callback)

  lli t0, 1
  jr ra
  sw t0, int_cb_needed (r0)

FinishFrame:
  addi sp, 8
  sw ra, -8 (sp)

  jal Joy.StartRead
  nop

  mfc0 t0, Count
// Get a fresh framebuffer
  jal VI.GetFramebuffer
  ls_gp(sw t0, frame_vblank_wait_cycles)

  mfc0 t0, Count
  ls_gp(lwu t1, frame_vblank_wait_cycles)
  subu t0, t1
  ls_gp(sw t0, frame_vblank_wait_cycles)

macro start_dp_render(idx) {
evaluate other_idx({idx}^1)
scope {#} {
  ls_gp(sb t0, conv_dst_idx)

// Write framebuffer addr into the dlist
// TODO with two dlists this is probably no longer necessary, but given
// that the framebuffers and conv_dsts/dlists are treated separately it's
// liable to get confused.
  la t1, RenderDlist{idx}.SetColorImageAddr|0xa000'0000
  sw a0, 0(t1)

// Wait for RDP free
  lui t0, DPC_BASE
-
  lli t1, 1
  ls_gp(sb t1, dp_interrupt_wait)
  lw t1, DPC_STATUS (t0)
  andi t1, RDP_CMS|RDP_CME // start/end valid
  beqz t1,+
  nop
-
  bnez t1,-
  ls_gp(lbu t1, dp_interrupt_wait)
  j --
  nop
+

  ls_gp(lbu t0, switch_model_requested)
  bnez t0, SwitchModel
  nop

if {defined PROFILE_RDP} {
  ls_gp(lwu t0, frame_rdp_cycles)
  lui t1, DPC_BASE
  lli t2, CLR_CLK
  sw t2, DPC_STATUS (t1)
  ls_gp(sw t0, last_frame_rdp_cycles)
}

// Render!

  lui t0, DPC_BASE
  la t1, RenderDlist{idx} & 0x7f'ffff
if {defined PROFILE_BARS} {
  ls_gp(lbu t3, profile_bars_enabled)
  beqz t3, need_to_sync
  la_hi(t2, RenderDlist{idx}.End & 0x7f'ffff)
  j end
  la_lo(t2, RenderDlist{idx}.End & 0x7f'ffff)
need_to_sync:
}
  la t2, RenderDlist{idx}.EndSync & 0x7f'ffff
end:
  sw t1, DPC_START (t0)
  sw t2, DPC_END (t0)
}
}

  ls_gp(lbu t0, conv_dst_idx)
  bnez t0, render_dlist_1
  xori t0, 1
start_dp_render(0)
  j rendered_dlist
  nop
render_dlist_1:
start_dp_render(1)
rendered_dlist:

  jal Menu.Display
  nop
if {defined PROFILE_BARS} {
include "profile_bars.asm"
}

  jal StartFrame
  nop

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

scope Joy {
Init:
  lli t0, 0xffff
  ls_gp(sw r0, joy1)
  ls_gp(sw r0, si_completion_vector)

  ls_gp(sb t0, joy1_shift)
  ls_gp(sb r0, joy_strobe)

// Clear pending SI interrupt
  lui t0, SI_BASE
  sw r0, SI_STATUS (t0)

// Enable SI interrupt
  lui t0, MI_BASE
  lli t1, MI_MASK_SET_SI
  sw t1, MI_INTR_MASK (t0)

  jr ra
  nop

StartRead:
// Don't start again if it's already in flight
  ls_gp(lw t0, si_completion_vector)
  bnez t0,+
  ls_gp(lw t0, si_callback)
  bnez t0,+
  la_gp(t0, ReadBack)
// Tail call
  j SI.StartReadControllers
  ls_gp(sw t0, si_completion_vector)
+
  jr ra
  nop

ReadBack:
  la_gp(t0, Process)
// Tail call
  j SI.ReadBackControllers
  ls_gp(sw t0, si_completion_vector)

Process:
  ls_gp(lbu t1, menu_enabled)
  ls_gp(lwu t0, read_con_buf + 4)
  beqz t1,+
  move t2, t0
  lli t2, 0
+
  ls_gp(sw t2, joy1)

// Tail call
  j Menu.ProcessButtons
  move a0, t0
}
