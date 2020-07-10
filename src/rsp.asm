//define LOG_SP_INT()

begin_bss()

rsp_interrupt_wait:; db 0
rsp_shutdown_requested:; db 0

align(4)
end_bss()

scope RSP {

Init:
// Halt anything that was running
  lui t0, SP_BASE
  lli t1, SET_HLT
  sw t1, SP_STATUS (t0)

// Wait for halt
-
  lw t1, SP_STATUS (t0)
  andi t1, RSP_HLT
  beqz t1,-
  nop

// Wait for DMA or I/O
-
  lw t1, SP_STATUS (t0)
  andi t1, RSP_BSY|RSP_IOF
  bnez t1,-
  nop

  la t1, Ucode & 0x7f'ffff
  sw t1, SP_DRAM_ADDR (t0)
  lli t1, 0x1000
  sw t1, SP_MEM_ADDR (t0)
  lli t2, 0x1000-1
  sw t2, SP_RD_LEN (t0)

// Wait for DMA
-
  lw t1, SP_DMA_BUSY(t0)
  bnez t1,-
  nop

// Set boot PC
  lui t2, SP_PC_BASE
  lli t1, Ucode.Boot
  sw t1, SP_PC (t2)

// Run
  lli t1, CLR_HLT|CLR_BRK|CLR_INT|CLR_STP|SET_IOB
  sw t1, SP_STATUS (t0)

// Wait for boot to finish
// Waiting for the PC to catch up avoids seeing halt too soon?
  lli t3, Ucode.AfterWaitForCPU
-
  lw t1, SP_PC (t2)
  bne t1, t3,-
  nop

-
  lw t1, SP_STATUS (t0)
  andi t1, RSP_HLT
  beqz t1,-
  nop

  ls_gp(sb r0, rsp_interrupt_wait)
  ls_gp(sb r0, rsp_shutdown_requested)

// Enable SP interrupt
  lui t0, MI_BASE
  lli t1, MI_MASK_SET_SP
  sw t1, MI_INTR_MASK (t0)

  jr ra
  nop

// The Ucode has its own scheduler, but this will request priority for the given task.
// a0 = task id
RunPriority:
  sll t1, a0, 1
  addi t1, 10 // SET_SG0
  lli t0, 1
  sllv t0, t1
  lui t1, SP_BASE
  sw t0, SP_STATUS (t1)
// Fall through

Run:
if 1 != 1 {
  lli t2, (num_abufs-1)*4
-
  la t0, (SP_MEM_BASE<<16) + SP_DMEM + dmem_abuf_addrs
  add t0, t2
  lw t1, 0 (t0)
  la t0, AI.abuf_addrs
  add t0, t2
  lw t0, 0 (t0)
  beq t1, t0,+
  nop
}

// Only start from idle
  lui t1, SP_BASE
  lw t0, SP_STATUS (t1)
  andi t0, RSP_SG7
  beqz t0,+
  lli t0, CLR_HLT|CLR_BRK|SET_IOB
  sw t0, SP_STATUS (t1)
+
  jr ra
  nop

SP_Interrupt:
if {defined LOG_SP_INT} {
exception_save_regs_for_debug()

  jal PrintStr0
  la_gp(a0, sp_int_msg)

  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_completion_vector (t0)
  jal PrintHex
  lli a1, 8

  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_task_ras (t0)
  jal PrintHex
  lli a1, 8

  jal NewlineAndFlushDebug
  nop

exception_restore_regs_for_debug()
}

  ls_gp(sd a0, exception_regs + a0*8)
  ls_gp(sd a1, exception_regs + a1*8)
  ls_gp(sd a2, exception_regs + a2*8)
  ls_gp(sd t0, exception_regs + t0*8)
  mflo k0
  mfhi t0
  ls_gp(sd t1, exception_regs + t1*8)
  ls_gp(sd t2, exception_regs + t2*8)
  ls_gp(sd ra, exception_regs + ra*8)
  ls_gp(sd k0, exception_lo)
  ls_gp(sd t0, exception_hi)

// If the RSP is already running, someone likely started it from
// idle, nothing to do (idle doesn't set a completion vector).
  lui t0, SP_BASE
  lw t1, SP_STATUS (t0)
  andi t2, t1, RSP_HLT|RSP_BRK
  beqz t2, int_done
  nop

// Run completion vector
  lui t0, SP_MEM_BASE
  lw t1, SP_DMEM + dmem_completion_vector (t0)
  beqz t1,+
  nop
  sw r0, SP_DMEM + dmem_completion_vector (t0)
  jalr t1
  nop
+

  ls_gp(lbu t0, rsp_shutdown_requested)
  beqz t0,+
  lui t1, SP_BASE
// Shutdown requested, clear idle so someone else doesn't start it
  lui t0, CLR_SG7>>16
  j ++
  sw t0, SP_STATUS (t1)
+
// Check if the scheduler was idle
  lw t0, SP_STATUS (t1)
  andi t0, RSP_SG7
  bnez t0,+
// If not idle, start the RSP
  lli t0, CLR_HLT|CLR_BRK
  sw t0, SP_STATUS (t1)
+

int_done:
  ls_gp(ld a0, exception_regs + a0*8)
  ls_gp(ld a1, exception_regs + a1*8)
  ls_gp(ld a2, exception_regs + a2*8)
  ls_gp(ld k0, exception_lo)
  ls_gp(ld t0, exception_hi)
// Should be far enough ahead of any uses of lo/hi to avoid
// undefined behavior.
  mtlo k0
  mthi t0
  ls_gp(ld t0, exception_regs + t0*8)
  ls_gp(ld t1, exception_regs + t1*8)
  ls_gp(ld t2, exception_regs + t2*8)
  ls_gp(ld ra, exception_regs + ra*8)

  ls_gp(sb r0, rsp_interrupt_wait)

  jr k1
  nop
}

if {defined LOG_SP_INT} {
sp_int_msg:
  db "SP Interrupt\n",0
align(4)
}
