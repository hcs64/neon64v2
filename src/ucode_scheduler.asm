// TODO this assumption will change if I add the dlist task, but for now
// most of this assumes exactly 2 tasks.
if num_rsp_tasks != 2 {
  error "assertion failed"
}
InitScheduler:
  sb r0, dmem_running_task (r0)
  lw t0, dmem_initial_task_ras (r0)
  sw t0, dmem_task_ras (r0)

// Set idle (SG7), clear all other signals
  la t0, CLR_SG0|CLR_SG1|CLR_SG2|CLR_SG3|CLR_SG4|CLR_SG5|CLR_SG6|SET_SG7
  mtc0 t0, C0_STATUS

// Fall through

WaitForCPU:
  break
AfterWaitForCPU:
// FIXME these nops are to work around cen64 issue #155
  nop
  nop
  nop
  nop

  sb r0, dmem_no_work_count (r0)
  lui t0, CLR_SG7>>16
  mtc0 t0, C0_STATUS

next_task:
  lbu t1, dmem_running_task (r0)
  mfc0 t0, C0_STATUS
  xori t1, 1

// Check for a priority task requested by a signal from the CPU
if 1 == 1 {
  andi t0, RSP_SG0
  beqz t0,+
  lli t2, CLR_SG0
  j run_priority_task
  lli t1, 0
+
  andi t0, RSP_SG1
  beqz t0,+
  lli t2, CLR_SG1
  lli t1, 1
run_priority_task:
// Clear signal
  mtc0 t2, C0_STATUS
+
}

  sb t1, dmem_running_task (r0)
  sw r0, dmem_completion_vector (r0)
  sb r0, dmem_work_left (r0)
  sll t0, t1, 1
  lhu t0, dmem_task_ras (t0)
if !{defined PROFILE_RDP} {
  lli t1, CLR_CLK
  mtc0 t1, C0_DPC_STATUS
}
  jr t0
  nop

Yield:
  lw t4, dmem_completion_vector (r0)
  lbu t1, dmem_running_task (r0)
  lbu t3, dmem_work_left (r0)
  lbu t2, dmem_no_work_count (r0)
  bnez t3,+
  lli t3, 0
  addi t3, t2, 1

+
  sb t3, dmem_no_work_count (r0)
if !{defined PROFILE_RDP} {
  mfc0 t0, C0_DPC_CLOCK
}

  sll t2, t1, 2
  lw t3, dmem_cycle_counts (t2)
if !{defined PROFILE_RDP} {
  add t0, t3
  sw t0, dmem_cycle_counts (t2)
}

// If there is a completion vector, break (without setting idle) to let
// the CPU run it.
  sll t1, 1
  bnez t4, WaitForCPU
  sh ra, dmem_task_ras (t1)

// If we haven't been fully idle yet, run the next task
  lbu t3, dmem_no_work_count (r0)
  lli t2, num_rsp_tasks
  bne t3, t2, next_task
  nop

// Set idle signal, break
  lui t0, SET_SG7>>16
  j WaitForCPU
  mtc0 t0, C0_STATUS
