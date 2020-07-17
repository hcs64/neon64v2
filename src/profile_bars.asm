// Profiling bars
  ls_gp(lbu t0, profile_bars_enabled)
  beqz t0, skip_profile_bars
  nop

if {defined PROFILE_RDP} {
// RDP
  ls_gp(lwu t2, last_frame_rdp_cycles)
  la t3, 62'500'000/60
  dsll t2, 8
  ddiv t2, t3
  la t1, 0xa000'0000 | ProfDlist.RDPRect
// Fill in XL
  la t0, (Fill_Rectangle_Cmd << 24)|((ProfDlist.rsp_y+ProfDlist.rsp_h-1) << 2)
  mflo t4
  addi t2, t4, ProfDlist.rsp_x-1
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 0 (t1)
} else {
// RSP PPU
  ls_gp(lwu t2, last_frame_ppu_rsp_cycles)
  la t3, 62'500'000/60
  dsll t2, 8
  ddiv t2, t3
  la t1, 0xa000'0000 | ProfDlist.RSP_PPU_Rect
// Fill in XL
  la t0, (Fill_Rectangle_Cmd << 24)|((ProfDlist.rsp_y+ProfDlist.rsp_h-1) << 2)
  mflo t4
  addi t2, t4, ProfDlist.rsp_x-1
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 0 (t1)

// RSP APU stacked on RSP PPU
  ls_gp(lwu t2, last_frame_apu_rsp_cycles)
  la t3, 62'500'000/60
  dsll t2, 8
  ddiv t2, t3
// Fill in XH
  la t0, ProfDlist.rsp_y<<2
  la t1, 0xa000'0000 | ProfDlist.RSP_APU_Rect
  addi t2, t4, ProfDlist.rsp_x
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 4 (t1)
// Fill in XL
  la t0, (Fill_Rectangle_Cmd << 24)|((ProfDlist.rsp_y+ProfDlist.rsp_h-1) << 2)
  mflo t2
  add t4, t2
  addi t2, t4, ProfDlist.rsp_x-1
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 0 (t1)
}

// CPU
  ls_gp(lwu t2, last_frame_cpu_cycles)
  lli t0, 0
  la t3, 93'750'000/2/60
  sub t2, t0
  dsll t2, 8
  ddiv t2, t3
  la t1, 0xa000'0000 | ProfDlist.CPURect
// Fill in XL
  la t0, (Fill_Rectangle_Cmd << 24)|((ProfDlist.cpu_y+ProfDlist.cpu_h-1) << 2)
  mflo t4
  addi t2, t4, ProfDlist.cpu_x-1
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 0 (t1)

macro stack_count_profile_bar(rect) {
  la t3, 93'750'000/2/60
  dsll t2, 8
  ddiv t2, t3
// Fill in XH
  la t0, ProfDlist.cpu_y<<2
  la t1, 0xa000'0000 | {rect}
  addi t2, t4, ProfDlist.cpu_x
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 4 (t1)
// Fill in XL
  la t0, (Fill_Rectangle_Cmd << 24)|((ProfDlist.cpu_y+ProfDlist.cpu_h-1) << 2)
  mflo t2
  add t4, t2
  addi t2, t4, ProfDlist.cpu_x-1
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 0 (t1)
}

// Stack PPU
  ls_gp(lwu t2, last_frame_ppu_cycles)
stack_count_profile_bar(ProfDlist.PPURect)
// Stack APU
  ls_gp(lwu t2, last_frame_apu_cycles)
stack_count_profile_bar(ProfDlist.APURect)
// Stack Scheduler
  ls_gp(lwu t2, last_frame_scheduler_cycles)
stack_count_profile_bar(ProfDlist.SchedulerRect)
// Frame Finishing (including this), assorted exception callbacks
  lwu t2, frame_cycles + int_cb_task * 4 (r0)
  ls_gp(lwu t0, last_frame_vblank_wait_cycles)
  subu t2, t0
stack_count_profile_bar(ProfDlist.FrameFinishRect)
if 1 != 1 {
// Stack Exceptions
  ls_gp(lwu t2, last_frame_exception_cycles)
stack_count_profile_bar(ProfDlist.ExceptionsRect)
}

// Vblank wait
  ls_gp(lwu t2, last_frame_vblank_wait_cycles)
  la t3, 93'750'000/2/60
  dsll t2, 8
  ddiv t2, t3
// Fill in XH
  la t0, ProfDlist.cpu_y<<2
  la t1, 0xa000'0000 | ProfDlist.VBLRect
  mflo t2
  lli t3, ProfDlist.cpu_x+ProfDlist.cpu_w
  sub t2, t3, t2
  andi t2, 0x3ff
  sll t2, 14
  or t0, t2
  sw t0, 4 (t1)

-
  la a0, ProfDlist & 0x7f'ffff
  la a1, ProfDlist.EndSync & 0x7f'ffff
  lli a2, prof_dlist_idx

  syscall QUEUE_DLIST_SYSCALL
  nop
  beqz v1,-
  nop

skip_profile_bars:
