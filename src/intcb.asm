// A scheduler task to handle interrupt callbacks
// TODO: AI, VI, SP could probably go in here as well.

InitIntCallbacks:
  ls_gp(sw r0, frame_callback)
  ls_gp(sw r0, si_callback)
  ls_gp(sw r0, pi_callback)
  jr ra
  nop

scope IntCallbackTask: {
if {defined LOG_SCHEDULER} {
  addi sp, 8
  sw ra, -8(sp)

  ls_gp(lw a0, frame_callback)
  jal PrintHex
  lli a1, 8

  ls_gp(lw a0, si_callback)
  jal PrintHex
  lli a1, 8

  ls_gp(lw a0, pi_callback)
  jal PrintHex
  lli a1, 8

  jal NewlineAndFlushDebug
  nop

  lw ra, -8(sp)
  addi sp, -8

  j +
  nop

+
}

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
  ll t1, int_cb_needed (r0)

macro check_callback(run_label, addr) {
  ls_gp(lw t0, {addr})
  bnez t0, {run_label}
  nop
}

check_callback(run_frame, frame_callback)
check_callback(run_si, si_callback)
check_callback(run_pi, pi_callback)

// FIXME LL/SC aren't implemented on cen64
  lli t1, 0
  sc t1, int_cb_needed (r0)
  beqz t1,-
  nop

// Tail call
  j Scheduler.FinishIntCBTask
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
