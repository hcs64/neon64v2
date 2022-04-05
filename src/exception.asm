constant HW_INT_MIPS(0)
constant HW_INT_PRE_NMI(2)
constant TIMER_INT(7)

constant QUEUE_DLIST_SYSCALL(0x10)

//define TRAP_WRITE(APU.There)
define TRAP_HANG(100'000'000)

InitExceptions:
// Disable interrupts
  mtc0 r0, Status
  mtc0 r0, WatchLo
  mtc0 r0, WatchHi

// Install exception vector.
  la t0, CommonExceptionVector
  lui t1, 0x8000
  lwu t2, 0(t0)
  lwu t3, 4(t0)
  sw t2, 0x180(t1)
  sw t3, 0x184(t1)
  cache data_hit_write_back, 0x180(t1)
  cache inst_hit_invalidate, 0x180(t1)

  la t0, TLBExceptionVector
  lwu t2, 0(t0)
  lwu t3, 4(t0)
  sw t2, 0(t1)
  sw t3, 4(t1)
  cache data_hit_write_back, 0(t1)
  cache inst_hit_invalidate, 0(t1)
  sw t2, 0x80(t1)
  sw t3, 0x84(t1)
  cache data_hit_write_back, 0x80(t1)
  cache inst_hit_invalidate, 0x80(t1)

// Mask off all MI interrupts
  lui t0, MI_BASE
  lli t1, MI_MASK_CLR_SP|MI_MASK_CLR_SI|MI_MASK_CLR_AI|MI_MASK_CLR_VI|MI_MASK_CLR_PI|MI_MASK_CLR_DP
  sw t1, MI_INTR_MASK (t0)

// Enable pre-NMI, MIPS interrupts
evaluate INITIAL_STATUS((1<<(8+2+HW_INT_MIPS))|(1<<(8+2+HW_INT_PRE_NMI))|1)

if {defined TRAP_HANG} {
  la t0, {TRAP_HANG}
  mtc0 r0, Count
  mtc0 t0, Compare

// Enable timer interrupt
evaluate INITIAL_STATUS({INITIAL_STATUS}|(1<<(8+TIMER_INT)))
}

  la t0, {INITIAL_STATUS}
  mtc0 t0, Status

// Trap a write
if {defined TRAP_WRITE} {

evaluate trap_write_eval({TRAP_WRITE})
if {trap_write_eval} >= low_page_base && {trap_write_eval} < low_page_end {
evaluate trap_write_eval({TRAP_WRITE} - low_page_base + low_page_ram_base)
}

  la t0, ({trap_write_eval}&0x1fff'fff8)|1
  mtc0 t0, WatchLo
  mtc0 r0, WatchHi
}

  jr ra
  nop

DisableTimerInterrupt:
if {defined TRAP_HANG} {
// Load status without timer interrupt enabled
  la t0, {INITIAL_STATUS}^(1<<(8+TIMER_INT))
  mtc0 t0, Status
}
  jr ra
  nop

CommonExceptionVector:
  j CommonExceptionHandler
  nop

TLBExceptionVector:
  j CommonExceptionHandler
  nop

CommonExceptionHandler:
  mfc0 k0, Cause
if 1 != 1 {
  mfc0 k1, Count
  ls_gp(sw k1, exception_start_count)
}

  srl k1, k0, 2
  andi k1, 0b1'1111
  bnez k1, not_interrupt
  nop
// Only check interrupts that could have caused the exception.
  mfc0 k1, Status
  and k0, k1

if {defined TRAP_HANG} {
// Timer interrupt
  andi k1, k0, 1<<(8+TIMER_INT)
  bnez k1, timer_interrupt
  nop
}

  andi k1, k0, 1<<(8+2+HW_INT_PRE_NMI)
  beqz k1,+
  nop

// Pre-NMI, stop DP and SP to ensure reset succeeds.

  lui k0, DPC_BASE
  lli t0, CLR_XBS|SET_FRZ
  sw k1, DPC_STATUS (k0)

  lui k0, SP_BASE
  lli k1, SET_HLT
  sw k1, SP_STATUS (k0)
// Set PC. This seems to fix an issue with resetting when a break
// is on 0x4f8, probably due to IPL2 ending up in IMEM during boot.
  lui k0, SP_PC_BASE
  sw r0, SP_PC (k0)
  nop

// Enable AI DMA in case it was stopped, to avoid getting stuck on boot.
  lui k0, AI_BASE
  lli k1, 1
  sw k1, AI_CONTROL (k0)

// FIXME Disable because I haven't been able to test, my reset button broke
if 1 != 1 {
// Reset PI
  lui k0, PI_BASE
  lli k1, 0b11 // Reset controller, clear interrupt
  sw k1, PI_STATUS (k0)
}

// Mask off all interrupts
  mtc0 r0, Status
  mtc0 r0, WatchLo
  mtc0 r0, WatchHi

  lui k0, MI_BASE
  lli k1, MI_MASK_CLR_SP|MI_MASK_CLR_SI|MI_MASK_CLR_AI|MI_MASK_CLR_VI|MI_MASK_CLR_PI|MI_MASK_CLR_DP
  sw k1, MI_INTR_MASK (k0)

// Spin until NMI
-
  j -
  nop
+

  andi k1, k0, 1<<(8+2+HW_INT_MIPS)
  bnez k1, mips_interrupt_check
  nop

// not MIPS, should be unreachable
  eret

mips_interrupt_check:
  lui k1, MI_BASE
  lwu k0, MI_INTR(k1)

// Only check interrupts that could have caused the exception.
  lwu k1, MI_INTR_MASK(k1)
  and k1, k0

  andi k0, k1, %11'1000
  bnez k0, high_interrupts
  nop

// Low interrupts
  andi k0, k1, MI_INTR_SP
  beqz k0,+
  andi k0, k1, MI_INTR_AI

// Clear interrupt
  lui k0, SP_BASE
  lli k1, CLR_INT
  sw k1, SP_STATUS (k0)

  la k0, RSP.SP_Interrupt
  jalr k1, k0
  nop

  j mips_interrupt_check
  nop

+
  beqz k0,+
  andi k0, k1, MI_INTR_SI

// Clear AI interrupt
  lui k0, AI_BASE
  sw r0, AI_STATUS (k0)

  la k0, AI.Interrupt
  jalr k1, k0
  nop

  j mips_interrupt_check
  nop

+
  beqz k0,+
  nop

// Clear SI interrupt
  lui k0, SI_BASE
  sw r0, SI_STATUS (k0)

  la k0, SI.Interrupt
  jalr k1, k0
  nop

  j mips_interrupt_check
  nop

+
// No MI interrupts left.

if 1 != 1 {
// Account!
  ls_gp(lwu k1, exception_start_count)
  mfc0 k0, Count
  subu k0, k1
  ls_gp(lwu k1, frame_exception_cycles)
  addu k1, k0
  ls_gp(sw k1, frame_exception_cycles)
}

  eret

high_interrupts:
  andi k0, k1, MI_INTR_VI
  beqz k0,+
  andi k0, k1, MI_INTR_PI

// Clear VI interrupt
  lui k0, VI_BASE
  sw r0, VI_V_CURRENT_LINE(k0)

  la k0, VI.VI_Interrupt
  jalr k1, k0
  nop

  j mips_interrupt_check
  nop

+
  beqz k0,+
  andi k0, k1, MI_INTR_DP

// Clear PI interrupt
  lui k0, PI_BASE
  lli k1, 0b10 // clear interrupt
  sw k1, PI_STATUS (k0)

  la k0, PI.Interrupt
  jalr k1, k0
  nop

  j mips_interrupt_check
  nop

+
  beqz k0,+
  nop

// Clear DP interrupt
  lui k0, MI_BASE
  lli k1, MI_CLEAR_DP_INT
  sw k1, MI_INIT_MODE(k0)

  la k0, VI.DP_Interrupt
  jalr k1, k0
  nop

  j mips_interrupt_check
  nop

+
// should be unreachable
  eret

if {defined TRAP_HANG} {
timer_interrupt:
  jal PrintHeaderInfo
  nop

  jal PrintStr0
  la_gp(a0, hang_msg)

  j exception_print2
  nop
}

// The only interrupts we're interested in are those from the RCP (interrupt line 0),
// so don't bother checking for now.

not_interrupt:
  ls_gp(sd t0, exception_regs + t0*8)
  lli t0, 1 // TLB modification
  bne t0, k1, not_tlb_modification
  nop

scope TLBModification {
// TLB modification exception, only used here for write protection
  ls_gp(sd t1, exception_regs + t1*8)
  ls_gp(sd t2, exception_regs + t2*8)

  mfc0 t1, Cause
  dmfc0 t0, EPC

  bltz t1,+
  nop
// Not delay slot, simply skip the offending instruction
  daddi t0, 4
  j end
  dmtc0 t0, EPC
+

// Special case for handling for the jr ra at the end of PPU.WriteData
  lw t1, 0 (t0)
  la t2, 0x03e0'0008
  bne t1, t2,+
  nop

  j end
  dmtc0 ra, EPC

+
  j unhandled_exception
  nop

end:
  ls_gp(ld t0, exception_regs + t0*8)
  ls_gp(ld t1, exception_regs + t1*8)
  ls_gp(ld t2, exception_regs + t2*8)

// TODO this isn't currently accounted for in the cycle counts
  eret
}

not_tlb_modification:
  lli t0, 2 // TLB miss
  bne t0, k1, not_tlb_miss
  nop

scope TLBMiss {
  ls_gp(sd a0, exception_regs + a0*8)
  ls_gp(sd a1, exception_regs + a1*8)
  ls_gp(sd ra, exception_regs + ra*8)

// Handle only one special case: remap PC if opcode fetch misses,
// as it has run off the end of a bank.

// FIXME there are a lot of other places in cpu.asm and opcodes.asm that
// load from cpu_mpc that should probably be covered, in case an instruction
// crosses a bank boundary. Probably should just check for an lb/lbu instruction
// that uses cpu_mpc as base. But I want to wait for a failing example
// before taking that step.

  dmfc0 t0, EPC
  la a0, opcode_fetch_lbu
  bne t0, a0, unhandled_exception
  nop

  //get_pc(a1)
  lw a1, cpu_mpc_base (r0)
  subu a1, cpu_mpc, a1
  andi a0, a1, 0xff
  srl a1, 8
  jal SetPC
  andi a1, 0xff

  ls_gp(ld t0, exception_regs + t0*8)
  ls_gp(ld a0, exception_regs + a0*8)
  ls_gp(ld a1, exception_regs + a1*8)
  ls_gp(ld ra, exception_regs + ra*8)

  eret
}

not_tlb_miss:
  lli t0, 8 // syscall
  bne t0, k1, not_syscall
  nop

  ls_gp(sd t1, exception_regs + t1*8)
  ls_gp(sd t2, exception_regs + t2*8)
// Syscall, check the code
  dmfc0 t0, EPC
  lw t1, 0(t0)
  srl t1, 6

  lli t2, QUEUE_DLIST_SYSCALL
  bne t1, t2, unhandled_exception
  nop
  daddi t0, 4

  dmtc0 t0, EPC

  ls_gp(ld t0, exception_regs + t0*8)
  ls_gp(ld t1, exception_regs + t1*8)
  ls_gp(ld t2, exception_regs + t2*8)

  la k0, VI.QueueDlist
  jalr k1, k0
  nop

  eret
not_syscall:

unhandled_exception:
  jal PrintHeaderInfo
  nop

// Whatever it is, we're not handling it now.
  la_hi(a0, exception_msg1)
  jal PrintStr0
  la_lo(a0, exception_msg1)

  jal PrintDec
  move a0, k1

exception_print2:
  la_hi(a0, exception_msg2)
  jal PrintStr0
  la_lo(a0, exception_msg2)

  dmfc0 a0, EPC
  jal PrintHex
  lli a1, 16

  la_hi(a0, space)
  jal PrintStr0
  la_lo(a0, space)

if 1 != 1 {
// If the instruction wasn't the error, fetch and print it.
  dmfc0 t0, EPC
  dmfc0 t1, BadVAddr
  beq t0, t1,+
  nop

  cache data_hit_invalidate, 0 (t0)
// I'm not sure if this works, the idea is to get the instruction
// back out of ICache in case the underlying memory changed since.

// FIXME Disabled for now as it crashes cen64
  //cache inst_hit_write_back, 0 (t0)

  lw a0, 0 (t0)
  jal PrintHex
  lli a1, 8
+
}

  la_hi(a0, exception_msg3)
  jal PrintStr0
  la_lo(a0, exception_msg3)

  dmfc0 a0, BadVAddr
  jal PrintHex
  lli a1, 16

if 1 == 1 {
  jal PrintStr0
  la_gp(a0, newline)

  lui t0, DPC_BASE
  lw a0, DPC_STATUS (t0)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, newline)

  lui t0, DPC_BASE
  lw a0, DPC_CURRENT (t0)
  jal PrintHex
  lli a1, 8

  lui t0, MI_BASE
  lw a0, MI_INTR(t0)
  jal PrintHex
  lli a1, 8

  lui t0, MI_BASE
  lw a0, MI_INTR_MASK(t0)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, newline)
}

if 1 == 0 {
  la_hi(a0, newline)
  jal PrintStr0
  la_lo(a0, newline)

  addi sp, 8
  lli t0, num_abufs-1
-
  sw t0, -8 (sp)

  lui a0, SP_MEM_BASE
  sll t0, 2
  add a0, t0
  lw a0, SP_DMEM + dmem_abuf_addrs (a0)
  jal PrintHex
  lli a1, 8

  jal PrintStr0
  la_gp(a0, newline)

  lw t0, -8 (sp)
  bnez t0,-
  addi t0, -1

  addi sp, -8

  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_other (t0)
  jal PrintHex
  lli a1, 8
}

if 1 != 1 {
  la_hi(a0, newline)
  jal PrintStr0
  la_lo(a0, newline)

  lui t0, SP_MEM_BASE
  la t1, Ucode
  lli t2, (Ucode.End - Ucode)/4-1
-
  lw t3, SP_IMEM (t0)
  lw t4, 0 (t1)
  bne t3, t4,+
  addi t0, 4
  addi t1, 4
  bnez t2,-
  addi t2, -1
+
  move a0, t2
  jal PrintHex
  lli a1, 8
}


if 1 != 1 {
  la_hi(a0, newline)
  jal PrintStr0
  la_lo(a0, newline)

if 1 != 1 {
// Stop SP so PC can be read reliably
  lui t0, SP_BASE
  lli t1, SET_STP
  sw t1, SP_STATUS (t0)
}

if 1 == 1 {
  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_frames_finished (t0)
  jal PrintHex
  lli a1, 4

  la_hi(a0, space)
  jal PrintStr0
  la_lo(a0, space)

  ls_gp(lw a0, frames_finished)
  jal PrintHex
  lli a1, 8
}

}
  mtc0 r0, WatchLo
  mtc0 r0, WatchHi

  jal VI.StopDP
  nop

  la t0, framebuffer0
  ls_gp(sw t0, active_framebuffer)

  la a0, framebuffer0 + (16*width+22)*2
  jal VI.PrintDebugToScreen
  lli a1, 30

  jal NewlineAndFlushDebug
  nop

  lui t1, VI_BASE
  la t0, framebuffer0
  sw t0, VI_ORIGIN(t1)

-;j -
  nop

macro exception_save_regs_for_debug() {
ls_gp(sd t0, exception_regs + t0*8)
ls_gp(sd t1, exception_regs + t1*8)
ls_gp(sd t2, exception_regs + t2*8)
ls_gp(sd t3, exception_regs + t3*8)
ls_gp(sd t4, exception_regs + t4*8)
ls_gp(sd a0, exception_regs + a0*8)
ls_gp(sd a1, exception_regs + a1*8)
ls_gp(sd ra, exception_regs + ra*8)
ls_gp(sd sp, exception_regs + sp*8)
}

macro exception_restore_regs_for_debug() {
ls_gp(ld t0, exception_regs + t0*8)
ls_gp(ld t1, exception_regs + t1*8)
ls_gp(ld t2, exception_regs + t2*8)
ls_gp(ld t3, exception_regs + t3*8)
ls_gp(ld t4, exception_regs + t4*8)
ls_gp(ld a0, exception_regs + a0*8)
ls_gp(ld a1, exception_regs + a1*8)
ls_gp(ld ra, exception_regs + ra*8)
ls_gp(ld sp, exception_regs + sp*8)
}

begin_bss()
align(8)
exception_regs:; fill 32*8
exception_lo:;   dd 0
exception_hi:;   dd 0
exception_stack:; fill 16*8

if 1 != 1 {
exception_start_count:; dw 0
}
end_bss()

if {defined TRAP_HANG} {
hang_msg:
  db "Hang detected.",0
}
exception_msg1:
  db "Unhandled exception. ExcCode=",0
exception_msg2:
  db "\nEPC=",0
exception_msg3:
  db "\nBadVAddr=",0

align(4)
