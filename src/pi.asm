constant rom_cart_addr(0x1000'0000)
constant sram_cart_addr(0x0800'0000)

scope PI {
Init:
// Clear any previous interrupt
  lui t0, PI_BASE
  lli t1, 0b10
  sw t1, PI_STATUS (t0)

  ls_gp(sw r0, pi_completion_vector)

// Enable interrupt
  lui t0, MI_BASE
  lli t1, MI_MASK_SET_PI
  sw t1, MI_INTR_MASK (t0)

  jr ra
  nop

Interrupt:
  ls_gp(lw k0, pi_completion_vector)
  beqz k0,+
  ls_gp(sw r0, pi_completion_vector)

// Schedule to run in the interrupt task
  ls_gp(sw k0, pi_callback)
  lli k0, 1
  sw k0, int_cb_needed (r0)

+
  jr k1
  ls_gp(sb r0, pi_interrupt_wait)

macro pi_wait(pi_base, tmp) {
-
  lw {tmp}, PI_STATUS ({pi_base})
  andi {tmp}, 0b11 // DMA or I/O busy
  bnez {tmp},-
  nop
}

// Note: Will not work in an exception
WaitViaInt:
  lui t1, PI_BASE
-
  lli t0, 1
  ls_gp(sb t0, pi_interrupt_wait)

  lw t0, PI_STATUS (t1)
  andi t0, 0b11 // DMA or I/O busy
  bnez t0,+
  nop

  jr ra
  nop
+
-
  ls_gp(lbu t0, pi_interrupt_wait)
  bnez t0,-
  nop
  j --
  nop

// Note: Does not invalidate cache
// a0: PI space address
// a1: DRAM address
// a2: Length
ReadSync:
  lui t0, PI_BASE

pi_wait(t0, t1)

  sw a0, PI_CART_ADDR(t0)
  sw a1, PI_DRAM_ADDR(t0)
  addi t1, a2, -1
  sw t1, PI_WR_LEN(t0)

pi_wait(t0, t1)

  jr ra
  nop

// Start a read now, return before it has finished.
// a0: PI space address
// a1: DRAM address
// a2: Length
// a3: Callback

// This cannot be run in an interrupt/exception.
// Panics if there is already a completion vector or callback in flight.
// Does not handle cache.
ReadAsync:
  addi sp, 8
  sw ra, -8 (sp)

  jal WaitViaInt
  nop

  ls_gp(lw t0, pi_completion_vector)
  ls_gp(lw t1, pi_callback)
  bnez t0,+
  nop
  beqz t1,++
  nop
+
read_collision:
  syscall 1
+
  ls_gp(sw a3, pi_completion_vector)

  lui t0, PI_BASE
  sw a0, PI_CART_ADDR(t0)
  sw a1, PI_DRAM_ADDR(t0)
  addi t1, a2, -1
  sw t1, PI_WR_LEN(t0)

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

// Start a write now, return before it has finished.
// a0: PI space address
// a1: DRAM address
// a2: Length
// a3: Callback

// This cannot be run in an interrupt/exception.
// Panics if there is already a completion vector or callback in flight.
// Does not handle cache.
WriteAsync:
  addi sp, 8
  sw ra, -8 (sp)

  jal WaitViaInt
  nop

  ls_gp(lw t0, pi_completion_vector)
  ls_gp(lw t1, pi_callback)
  bnez t0,+
  nop
  beqz t1,++
  nop
+
write_collision:
  syscall 1
+
  ls_gp(sw a3, pi_completion_vector)

  lui t0, PI_BASE
  sw a0, PI_CART_ADDR(t0)
  sw a1, PI_DRAM_ADDR(t0)
  addi t1, a2, -1
  sw t1, PI_RD_LEN(t0)

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

SetSRAMTiming:
  lli a0, 0x5
  lli a1, 0xc
  lli a2, 0xd
// Tail call
  j SetDOM2Timing
  lli a3, 0x2

SetDOM2Timing:
  lui t0, PI_BASE

pi_wait(t0, t1)

  sw a0, PI_BSD_DOM2_LAT(t0)
  sw a1, PI_BSD_DOM2_PWD(t0)
  sw a2, PI_BSD_DOM2_PGS(t0)
  jr ra
  sw a3, PI_BSD_DOM2_RLS(t0)
}

begin_bss()
pi_completion_vector:
  dw 0

pi_interrupt_wait:
  db 0

align_dcache()

align_dcache()
end_bss()
