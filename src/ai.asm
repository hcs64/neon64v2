//define LOG_AI_INT()

begin_bss()
align(4)
ai_interrupt_wait:
  db 0
align(4)
end_bss()

align(4)
scope AI {
abuf_addrs:
evaluate rep_i(0)
while {rep_i} < num_abufs {
  dw (audiobuffer&0x7f'ffff) + {rep_i}*abuf_size
evaluate rep_i({rep_i}+1)
}

Init:
  addi sp, 16
  sw ra, -8 (sp)

  lui t0, AI_BASE
// TODO PAL timing
  lli t1, VI_NTSC_CLOCK / samplerate - 1
  sw t1, AI_DACRATE (t0)
  lli t1, 15
  sw t1, AI_BITRATE (t0)
// If initially busy, spin
-
  lw t1, AI_STATUS (t0)
  srl t1, 30
  andi t1, 1
  bnez t1,-
  nop
// Enable DMA
  lli t1, 1
  sw t1, AI_CONTROL (t0)

  ls_gp(sb r0, ai_interrupt_wait)

// Enable interrupt
  lui t0, MI_BASE
  lli t1, MI_MASK_SET_AI
  sw t1, MI_INTR_MASK (t0)

// Init buffer FIFO
  lui t0, SP_MEM_BASE
  sw r0, SP_DMEM + dmem_abuf_read (t0)
  sw r0, SP_DMEM + dmem_abuf_write (t0)

// Initially clear buffers
  la a0, audiobuffer
  la t0, abuf_samples
-
  lli t1, num_abufs
  move t2, a0
-
  sw r0, 0 (t2)
  addi t1, -1
  bnez t1,-
  addi t2, abuf_size
  addi t0, -1
  bnez t0,--
  addi a0, 4

  lw ra, -8 (sp)
  jr ra
  addi sp, 16

// This will be run from the SP interrupt when the APU ucode has finished
// a buffer. The ucode has already advanced dmem_abuf_write, so if the AI
// is full it will be picked up on the next AI interrupt. But if the AI
// isn't full, we need to play the next buffer now.
PlayBufferFromSP:
  lui t0, AI_BASE
  lw t1, AI_STATUS (t0)
  bgez t1,+
  lui t0, SP_MEM_BASE

// Full, nothing to do.
  jr ra
  nop
+

// Make sure we're not colliding with dmem_abuf_write somehow.
  lw t1, SP_DMEM + dmem_abuf_read (t0)
  lw t0, SP_DMEM + dmem_abuf_write (t0)
  beq t0, t1,++
  sll t1, 2

// Play the next buffer
// This should be the one that the RSP just finished, but might not be.
  add t1, gp
  lw t1, abuf_addrs - gp_base (t1)

  lui t0, AI_BASE
  sw t1, AI_DRAM_ADDR (t0)
  la t1, abuf_samples * 4
  sw t1, AI_LEN (t0)

// Advance to the next buffer
  lui t2, SP_MEM_BASE
  lw t1, SP_DMEM + dmem_abuf_read (t2)
  lli t0, num_abufs-1
  bne t0, t1,+
  addi t1, 1
  lli t1, 0
+
  sw t1, SP_DMEM + dmem_abuf_read (t2)
+
  jr ra
  nop

Pause:
  lui t0, AI_BASE
  jr ra
  sw r0, AI_CONTROL (t0)

Unpause:
  lui t0, AI_BASE
  lli t1, 1
  jr ra
  sw t1, AI_CONTROL (t0)

scope Interrupt: {

if {defined LOG_AI_INT} {
exception_save_regs_for_debug()

  jal PrintStr0
  la_gp(a0, ai_int_msg)

  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_abuf_read (t0)
  jal PrintHex
  lli a1, 2

  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_abuf_write (t0)
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop

exception_restore_regs_for_debug()
}

  ls_gp(sd t0, exception_regs + t0*8)
  ls_gp(sd t1, exception_regs + t1*8)
  ls_gp(sd sp, exception_regs + sp*8)
  mflo k0
  mfhi t0
  ls_gp(sd a0, exception_regs + a0*8)
  ls_gp(sd a1, exception_regs + a1*8)
  ls_gp(sd t2, exception_regs + t2*8)
  ls_gp(sd k0, exception_lo)
  ls_gp(sd t0, exception_hi)
  ls_gp(sd ra, exception_regs + ra*8)

  la_gp(sp, exception_stack)
  addi sp, 8

// Check that the AI isn't already Full
// FIXME Figure out what the deal is with these spurious interrupts.
  lui t1, AI_BASE
  lw t2, AI_STATUS (t1)
  bltz t2, end
  nop

// Is anything ready to play?
  lui k0, SP_MEM_BASE
  lw t0, SP_DMEM + dmem_abuf_read (k0)
  lw t1, SP_DMEM + dmem_abuf_write (k0)
  bne t0, t1, no_flush_needed
  nop

// Nothing is queued yet, request render flush (don't wait for any more alists)
  j APU.RenderFlush
  la_gp(ra, end)

no_flush_needed:
// Get the next buffer address
  sll t0, 2
  add t0, gp
  lw t0, abuf_addrs - gp_base (t0)

// Play the next buffer
  lui t1, AI_BASE
  sw t0, AI_DRAM_ADDR (t1)
  la t0, abuf_samples * 4
  sw t0, AI_LEN (t1)

// Increment read
  lui k0, SP_MEM_BASE
  lw t1, SP_DMEM + dmem_abuf_read (k0)
  lli t0, num_abufs-1
  bne t1, t0,+
  addi t1, 1
  lli t1, 0
+
  sw t1, SP_DMEM + dmem_abuf_read (k0)

// Try rendering now that there's a buffer free
  jal RSP.Run
  nop

end:
  ls_gp(ld k0, exception_lo)
  ls_gp(ld t0, exception_hi)
  ls_gp(ld a0, exception_regs + a0*8)
  ls_gp(ld a1, exception_regs + a1*8)
  ls_gp(ld t2, exception_regs + t2*8)
// Should be far enough ahead of any uses of lo/hi to avoid
// undefined behavior.
  mtlo k0
  mthi t0

  ls_gp(ld t0, exception_regs + t0*8)
  ls_gp(ld t1, exception_regs + t1*8)
  ls_gp(ld ra, exception_regs + ra*8)
  ls_gp(ld sp, exception_regs + sp*8)

if {defined LOG_AI_INT} {
exception_save_regs_for_debug()

  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_abuf_read (t0)
  jal PrintHex
  lli a1, 2

  lui t0, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_abuf_write (t0)
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop

exception_restore_regs_for_debug()
}

  ls_gp(sb r0, ai_interrupt_wait)

  jr k1
  nop
}

trap_interrupt_inconsistency:
  la k0, trap_interrupt_inconsistency
  mtc0 k0, EPC
  syscall 1
}

if {defined LOG_AI_INT} {
ai_int_msg:
  db "AI Interrupt",0
align(4)
}
