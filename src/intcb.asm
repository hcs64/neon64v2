// A scheduler task to handle interrupt callbacks
// TODO: AI, VI, SP could probably go in here as well.

InitIntCallbacks:
  ls_gp(sw r0, frame_callback)
  ls_gp(sw r0, si_callback)
  ls_gp(sw r0, pi_callback)
  jr ra
  nop

scope IntCallbackTask: {
macro do_callback(run_label, addr) {
  ls_gp(lw t0, {addr})
  beqz t0,+
  nop
{run_label}:
  jalr t0
  ls_gp(sw r0, {addr})
+
}

do_callback(run_frame, frame_callback)
do_callback(run_si, si_callback)
do_callback(run_pi, pi_callback)

// Run again if needed.
// Checked in an atomic loop in case of an interrupt while checking.
-
  lld t1, task_times + int_cb_task * 8 (r0)

macro check_callback(run_label, addr) {
  ls_gp(lw t0, {addr})
  bnez t0, {run_label}
  nop
}

check_callback(run_frame, frame_callback)
check_callback(run_si, si_callback)
check_callback(run_pi, pi_callback)

  addi t1, r0, -1
  scd t1, task_times + int_cb_task * 8 (r0)
  beqz t1,-
  nop

// Tail call
  j Scheduler.FinishTaskAlreadyUnscheduled
  nop
}

begin_bss()
frame_callback:
  dw 0
si_callback:
  dw 0
pi_callback:
  dw 0
end_bss()
