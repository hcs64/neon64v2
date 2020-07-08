//define LOG_SCHEDULER()

// Lower index conceptually runs first on the same cycle (lower idx is higher priority)
constant cpu_inst_task(0)
constant ppu_task(1)
constant apu_frame_task(2)
constant apu_dmc_task(3)
constant int_cb_task(4)

constant num_tasks(5)

begin_low_page()
align(8)

target_cycle:; dd 0
// No time or ra for int_cb_task
task_times:; fill 8 * (num_tasks-1)
task_ras:; fill 4 * (num_tasks-1)
frame_cycles:; fill 4 * num_tasks
frame_scheduler_cycles:; dw 0
int_cb_needed:; dw 0
running_task:; db 0

align(4)

end_low_page()

scope Scheduler {
Init:
  lli t1, (num_tasks-2) * 8
  lli t2, (num_tasks-2) * 4
  daddi t0, r0, -1
  la_gp(t3, BadTask)

-
  sd t0, task_times (t1)
  sw t3, task_ras (t2)
  sw r0, frame_cycles (t2)
  addiu t2, -4
  bnez t1,-
  addiu t1, -8

  sw r0, frame_scheduler_cycles (r0)
  move cycle_balance, r0

  sw r0, int_cb_needed (r0)

  jr ra
  sd r0, target_cycle (r0)

// Returns if nothing is found to run
scope Run: {
// Find the two earliest tasks, in priority order.
constant cur_idx(a0)
constant earliest0(t0)
constant earliest1(t1)
constant earliest0_idx(t2)
constant temp0(t3)
constant temp1(t4)

if {defined LOG_SCHEDULER} {
  addiu sp, 24
  sw ra, -24(sp)
  sd a0, -16(sp)

  jal PrintStr0
  la_gp(a0, scheduler_header_msg)

  lli t0, 0
print_schedule_loop:
  ld a0, task_times (t0)

  jal PrintDec
  sb t0, -8(sp)

  jal NewlineAndFlushDebug
  nop

  lbu t0, -8(sp)

  lli t1, (num_tasks - 2) * 8
  bne t1, t0, print_schedule_loop
  addi t0, 8

  lw ra, -24(sp)
  ld a0, -16(sp)
  addiu sp, -24
}

  lw temp0, int_cb_needed (r0)

// Initially load with task 0.
// This assumes task 0 is always scheduled.
  ld earliest0, task_times + 0 * 8 (r0)
  bnez temp0, run_int_cb
  lli earliest0_idx, 0
  ls_gp(ld earliest1, end_of_time)

  lli cur_idx, 8

search_loop:
// Skip the last task (intcb) as it is checked explicitly above
  subi temp0, cur_idx, (num_tasks-1) * 8
  bgez temp0, search_end

  ld temp0, task_times (cur_idx)
  addi cur_idx, 8
  bltz temp0, search_loop
  dsub temp1, temp0, earliest0
  bgez temp1, try_second
  dsub temp1, temp0, earliest1
// cur < earliest0
  move earliest1, earliest0
  move earliest0, temp0
  j search_loop
  addi earliest0_idx, cur_idx, -8

try_second:
  bgez temp1, search_loop
  nop
// cur < earliest1
  j search_loop
  move earliest1, temp0
search_end:

  bgez earliest0_idx, any_task
  srl earliest0_idx, 1

// No tasks.
  jr ra
  nop

run_int_cb:
  la_gp(temp0, IntCallbackTask)
  j finish
  lli earliest0_idx, int_cb_task

any_task:
  sd earliest1, target_cycle (r0)
  dsub cycle_balance, earliest0, earliest1
  lw temp0, task_ras (earliest0_idx)
  srl earliest0_idx, 2
finish:
  sb earliest0_idx, running_task (r0)

if {defined LOG_SCHEDULER} {
  addiu sp, 8
  sw temp0, -8(sp)

  jal PrintStr0
  la_gp(a0, schedulder_footer_msg)

  jal PrintDec
  lbu a0, running_task (r0)

  jal PrintStr0
  la_gp(a0, schedulder_footer2_msg)

  jal PrintDec
  ld a0, target_cycle (r0)

  jal NewlineAndFlushDebug
  nop

  lw temp0, -8(sp)
  addiu sp, -8
}

  lw temp1, frame_scheduler_cycles (r0)
  mfc0 earliest0, Count
  mtc0 r0, Count
  addu temp1, earliest0
  jr temp0
  sw temp1, frame_scheduler_cycles (r0)
}

YieldFromCPU:
// CPU is task 0, if the balance is exactly 0 it would just be run again
// immediately, so resume instead.
  bnez cycle_balance, Yield
// Unless the intcb task needs to run.
  lw t0, int_cb_needed (r0)
  bnez t0, Yield
  nop
  jr ra
  nop
Yield:
// Reschedule ra as callback for a continuing task
  ld t0, target_cycle  (r0)
  mfc0 t1, Count
  mtc0 r0, Count
  lbu t2, running_task (r0)
  move a1, ra
  sll t2, 2
  lwu t3, frame_cycles (t2)
  daddu a0, t0, cycle_balance
  addu t3, t1
  sw t3, frame_cycles (t2)

if {defined LOG_SCHEDULER} {
  addi sp, 24
  sd a0, -24 (sp)
  sd a1, -16 (sp)
  sd ra, -8 (sp)

  jal PrintDec
  lbu a0, running_task (r0)

  jal PrintStr0
  la_gp(a0, yielded_msg)

  ld a0, -16 (sp)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, until_cycle_msg)

  jal PrintDec
  ld a0, -24 (sp)

  jal NewlineAndFlushDebug
  nop

  ld a0, -24 (sp)
  ld a1, -16 (sp)
  ld ra, -8 (sp)
  addi sp, -24
}

  jal ScheduleTask
  lbu a2, running_task (r0)

// TODO: need to figure out in general what other stuff a task should attempt to run
// I don't really have the concept of "catchup" in here properly yet.

// Should not return unless there are no runnable tasks
  jal Run
  nop

  j NoTasks
  nop

FinishTask:
// Task has finished, doesn't need to be rescheduled now.
  lbu t2, running_task (r0)
  sll t3, t2, 2
  sll t0, t2, 3
  mfc0 t2, Count
  lwu t4, frame_cycles (t3)
  mtc0 r0, Count

  daddi t1, r0, -1
  sd t1, task_times (t0)
  la_gp(t1, BadTask)
  sw t1, task_ras (t3)

  addu t4, t2
  sw t4, frame_cycles (t3)

// Should not return unless there are no runnable tasks
  jal Run
  nop

  j NoTasks
  nop

FinishIntCBTask:
// Task has finished, doesn't need to be rescheduled now, and
// has already unscheduled itself.
// This is used for the interrupt callback task which has some careful atomic ops.
// All we need to do is account for the time spent.
  lbu t2, running_task (r0)
  sll t3, t2, 2
  mfc0 t2, Count
  lwu t4, frame_cycles (t3)
  mtc0 r0, Count

  addu t4, t2
  sw t4, frame_cycles (t3)

// Should not return unless there are no runnable tasks
  jal Run
  nop

  j NoTasks
  nop

ScheduleTaskFromNow:
// a0: relative time
// a1: callback
// a2: task index
  ld t0, target_cycle (r0)
  daddu a0, cycle_balance
  daddu a0, t0

// fallthrough

ScheduleTask:
// a0: time
// a1: callback
// a2: task index

// t0: clobbered
  sll t0, a2, 3
  sd a0, task_times(t0)
  sll t0, a2, 2
  sw a1, task_ras(t0)

  jr ra
  nop

align(8)
// Run to this time if nothing else is scheduled. If anything gets scheduled it must be the
// doing of the running task so it should yield to get rescheduled.
end_of_time:
  dd 0x7fff'ffff'ffff'ffff

BadTask:
  syscall 1 ; nop

NoTasks:
  jal PrintStr0
  la_gp(a0, no_tasks_msg)

  j DisplayDebugAndHalt
  nop

no_tasks_msg:
  db "No tasks scheduled",0
if {defined LOG_SCHEDULER} {
scheduler_header_msg:
  db "Scheduler could run\n",0
schedulder_footer_msg:
  db "Scheduler picked ",0
schedulder_footer2_msg:
  db " to run until ",0
yielded_msg:
  db " yielded, ra=",0
until_cycle_msg:
  db " until cycle=",0
}

align(4)
}
