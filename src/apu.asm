//define LOG_FRAME_COUNTER()
//define LOG_ALIST()
//define LOG_DMC()

constant apu_min_render_cycles(cycles_per_sample * 3)

constant apu_p1(0)
constant apu_p2(1)
constant apu_tri(2)
constant apu_noise(3)

begin_bss()
align(8)
apu_timer:; dh 0, 0, 0, 0

apu_len:; db 0, 0, 0, 0
// Also used for tri's linear counter
apu_envelope_count:; db 0, 0, 0, 0
apu_envelope_level:; db 0, 0, 0, 0
apu_reset_phase:; db 0, 0, 0, 0
apu_channel_0s:; db 0, 0, 0, 0
apu_dmc_regs:; db 0, 0, 0, 0
apu_target_timer:; dh 0, 0
apu_dmc_timer_cycles:; dw 0

apu_dmc_timer:; dh 0
apu_dmc_length_left:; dh 0
apu_dmc_cur_addr:; dh 0

apu_channel_1s:; db 0, 0
apu_sweep_count:; db 0, 0

apu_noise_mode:; db 0
apu_frame_counter:; db 0
apu_frame_mode:; db 0
apu_enable:; db 0
apu_irqs:; db 0
apu_dmc_load:; db 0

constant apu_dmc_buffer_size(10)
apu_dmc_buffer:; fill apu_dmc_buffer_size
apu_dmc_buffer_count:; db 0
if {defined LOG_DMC} {
apu_dmc_sim_level:; db 0
}

align(8)
apu_alist_cycle:; dd 0

align(4)
end_bss()

scope APU {

Init:
// TODO memset
  ls_gp(sd r0, apu_timer)
  ls_gp(sw r0, apu_len)
  ls_gp(sw r0, apu_envelope_count)
  ls_gp(sw r0, apu_envelope_level)
  ls_gp(sw r0, apu_reset_phase)
  ls_gp(sw r0, apu_channel_0s)
  ls_gp(sw r0, apu_dmc_regs)
  ls_gp(sw r0, apu_target_timer)
  ls_gp(sh r0, apu_dmc_timer)
  ls_gp(sh r0, apu_dmc_length_left)
  ls_gp(sh r0, apu_dmc_cur_addr)
  ls_gp(sh r0, apu_channel_1s)
  ls_gp(sh r0, apu_sweep_count)
  ls_gp(sb r0, apu_noise_mode)
  ls_gp(sb r0, apu_frame_counter)
  ls_gp(sb r0, apu_frame_mode)
  ls_gp(sb r0, apu_enable)
  ls_gp(sb r0, apu_irqs)
  ls_gp(sb r0, apu_dmc_load)
  ls_gp(sb r0, apu_dmc_buffer_count)
if {defined LOG_DMC} {
  ls_gp(sb r0, apu_dmc_sim_level)
}

// Noise is always running, so we need to set an initial timer
  ls_gp(lhu t0, noise_period_table + 0)
  ls_gp(sh t0, apu_timer + 2*apu_noise)

// Just in case DMC gets enabled before the timer is set.
  ls_gp(lhu t0, dmc_rate_table + 0)
  ls_gp(sh t0, apu_dmc_timer)
  lli t1, 8*cpu_div
  mult t0, t1
  mflo t2
  ls_gp(sw t2, apu_dmc_timer_cycles)

// When the pending alist took effect
  ls_gp(sd r0, apu_alist_cycle)

  la t0, alist_buffer
  lli t1, alist_entry_size * num_alists
-
  sb r0, 0 (t0)
  addi t1, -1
  bnez t1,-
  addi t0, 1

// Tail call
  j APU.ResetFrameCounter
  nop

WriteFrameCounter:
// cpu_t0: Write to 0x4017
// TODO IRQ can change, probably handle that in ResetFrameCounter?
  jal Render
  nop

  jal ResetFrameCounter
  ls_gp(sb cpu_t0, apu_frame_mode)

  andi t0, cpu_t0, 0b1000'0000 // mode
  beqz t0,+
  nop
// Write to 0x4017 in 5-step mode (bit 7 set) immediately clocks
  jal FrameStep.ClockEnvelopeLinear
  nop
  jal FrameStep.ClockLengthSweep
  nop
+

  lw ra, cpu_rw_handler_ra (r0)

  jr ra
  nop

ScheduleFrameStep:
  sw ra, 0(sp)
  addi sp, 8

  la a0, apu_quarter_frame_cycles
  la_gp(a1, FrameStep)
  jal Scheduler.ScheduleTaskFromNow
  lli a2, apu_frame_task

  lw ra, -8(sp)
  jr ra
  addi sp, -8

ResetFrameCounter:
  sw ra, 0(sp)
  addi sp, 8

  lbu t0, irq_pending (r0)
  ls_gp(sb r0, apu_frame_counter)
  andi t0, intAPUFrame^0xff
  sb t0, irq_pending (r0)

  jal ScheduleFrameStep
  nop

  lw ra, -8(sp)
  jr ra
  addi sp, -8

scope WriteEnable: {
// cpu_t0: Write to 0x4015
  jal Render
  nop

  ls_gp(sb cpu_t0, apu_enable)
evaluate rep_i(0)
while {rep_i} < 4 {
if {rep_i} == 0 {
  andi t0, cpu_t0, 1 << {rep_i}
}
  bnez t0,+
  andi t0, cpu_t0, 1 << ({rep_i}+1)
// TODO reset phase, envelope?
  ls_gp(sb r0, apu_len + {rep_i})
+
evaluate rep_i({rep_i}+1)
}
  lbu t1, irq_pending (r0)

// Clear DMC IRQ
  ls_gp(lbu t2, apu_irqs)
  andi t1, intDMC^0xff
  sb t1, irq_pending (r0)
  andi t2, 0b0111'1111
  ls_gp(sb t2, apu_irqs)

  andi t0, cpu_t0, 0b1'0000 // DMC enable
  beqzl t0, end
  ls_gp(sh r0, apu_dmc_length_left)

// Start sample if length was 0
  ls_gp(lhu t0, apu_dmc_length_left)
  bnez t0,+
  nop

  jal DMCSampleStart
  nop
+

// Start DMC task if not already running
  ld t1, task_times + apu_dmc_task*8 (r0)
  bgez t1,+
  nop

  jal DMCRead
  nop

  ls_gp(lwu a0, apu_dmc_timer_cycles)
  la_gp(a1, DMCTask)
  jal Scheduler.ScheduleTaskFromNow
  lli a2, apu_dmc_task
+

end:
  lw ra, cpu_rw_handler_ra (r0)
  jr ra
  nop
}

Write_0:
// cpu_t0: Write to 0x4000,0x4004,0x4008,0x400c
// cpu_t1: addr
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  srl t0, cpu_t1, 2
  andi t0, 0b11
  add t0, gp
  jr ra
  sb cpu_t0, apu_channel_0s - gp_base (t0)

macro apu_update_target_timer(idx, channel_1, cur_timer, tmp1, tmp2) {
  andi {tmp1}, {channel_1}, 0b0111 // shift amount

  andi {tmp2}, {channel_1}, 0b1000 // negate flag
  beqz {tmp2},+
  srlv {tmp2}, {cur_timer}, {tmp1}

if {idx} == apu_p1 {
// Pulse 1, 1's complement
  addi {tmp1}, r0, -1
  xor {tmp2}, {tmp1}
} else {
// Pulse 2, 2's complement
  neg {tmp2}
}

+
  add {tmp2}, {cur_timer}
  bgez {tmp2},+
  ls_gp(sh {tmp2}, apu_target_timer + 2*{idx})
  ls_gp(sh r0, apu_target_timer + 2*{idx})
+
}

WriteP1_1:
// cpu_t0: Write to 0x4001
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  ls_gp(lbu t0, apu_sweep_count + apu_p1)
  ls_gp(sb cpu_t0, apu_channel_1s + apu_p1)
  ori t0, 0b1000'0000 // reload flag
  ls_gp(sb t0, apu_sweep_count + apu_p1)

  ls_gp(lhu t0, apu_timer + 2*apu_p1)
apu_update_target_timer(apu_p1, cpu_t0, t0, t1, t2)

  jr ra
  nop

WriteP2_1:
// cpu_t0: Write to 0x4005
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  ls_gp(lbu t0, apu_sweep_count + apu_p2)
  ls_gp(sb cpu_t0, apu_channel_1s + apu_p2)
  ori t0, 0b1000'0000 // reload flag
  ls_gp(sb t0, apu_sweep_count + apu_p2)

  ls_gp(lhu t0, apu_timer + 2*apu_p2)
apu_update_target_timer(apu_p2, cpu_t0, t0, t1, t2)

  jr ra
  nop

WriteP1TimerLow:
// cpu_t0: Write to 0x4002
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  ls_gp(sb cpu_t0, apu_timer + 1 + 2*apu_p1)
  ls_gp(lbu t0, apu_channel_1s + apu_p1)
  ls_gp(lhu t1, apu_timer + 2*apu_p1)
apu_update_target_timer(apu_p1, t0, t1, t2, t3)
  jr ra
  nop

WriteP2TimerLow:
// cpu_t0: Write to 0x4006
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  ls_gp(sb cpu_t0, apu_timer + 1 + 2*apu_p2)
  ls_gp(lbu t0, apu_channel_1s + apu_p2)
  ls_gp(lhu t1, apu_timer + 2*apu_p2)
apu_update_target_timer(apu_p2, t0, t1, t2, t3)
  jr ra
  nop

WriteTriTimerLow:
// cpu_t0: Write to 0x400a
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  jr ra
  ls_gp(sb cpu_t0, apu_timer + 1 + 2*apu_tri)

WriteNoisePeriod:
// cpu_t0: Write to 0x400e
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  andi t0, cpu_t0, 0b1000'0000
  ls_gp(sb t0, apu_noise_mode)

  andi t0, cpu_t0, 0b1111
  sll t0, 1
  add t0, gp
  lhu t0, noise_period_table - gp_base (t0)
  jr ra
  ls_gp(sh t0, apu_timer + 2*apu_noise)

// outputs high timer bits in t0
macro apu_set_length(idx) {
  ls_gp(lbu t0, apu_enable)
  srl t1, cpu_t0, 3 // bits 7-3
  andi t0, 1<<{idx}
  add t1, gp
  lbu t1, frame_length_table - gp_base (t1)
  beqz t0,+
  andi t0, cpu_t0, 0b111
  ls_gp(sb t1, apu_len+{idx})
+
}

WriteP1Length:
// cpu_t0: Write to 0x4003
  jal Render
  nop

// Set reload flag on envelope, and reset phase
  ls_gp(lbu t0, apu_envelope_count + apu_p1)
  lw ra, cpu_rw_handler_ra (r0)
  ori t0, 0x80
  ls_gp(sb t0, apu_envelope_count + apu_p1)
  ls_gp(sb t0, apu_reset_phase + apu_p1)

apu_set_length(apu_p1)
  ls_gp(sb t0, apu_timer + 0 + apu_p1*2)

  ls_gp(lbu t0, apu_channel_1s + apu_p1)
  ls_gp(lhu t1, apu_timer + 0 + apu_p1*2)
apu_update_target_timer(apu_p1, t0, t1, t2, t3)

  jr ra
  nop

WriteP2Length:
// cpu_t0: Write to 0x4007
  jal Render
  nop

// Set reload flag on envelope, and reset phase
  ls_gp(lbu t0, apu_envelope_count + apu_p2)
  lw ra, cpu_rw_handler_ra (r0)
  ori t0, 0x80
  ls_gp(sb t0, apu_reset_phase + apu_p2)
  ls_gp(sb t0, apu_envelope_count + apu_p2)

apu_set_length(apu_p2)
  ls_gp(sb t0, apu_timer + 0 + apu_p2*2)

  ls_gp(lbu t0, apu_channel_1s + apu_p2)
  ls_gp(lhu t1, apu_timer + 0 + apu_p2*2)
apu_update_target_timer(apu_p2, t0, t1, t2, t3)

  jr ra
  nop

WriteTriLength:
// cpu_t0: Write to 0x400b
  jal Render
  nop

// Set reload flag on linear counter
  ls_gp(lbu t1, apu_envelope_count + apu_tri)
  lw ra, cpu_rw_handler_ra (r0)
  ori t1, 0x80
  ls_gp(sb t1, apu_envelope_count + apu_tri)

apu_set_length(apu_tri)

  jr ra
  ls_gp(sb t0, apu_timer + 0 + apu_tri*2)

WriteNoiseLength:
// cpu_t0: Write to 0x400f
  jal Render
  nop

// Set reload flag on envelope
  ls_gp(lbu t0, apu_envelope_count + apu_noise)
  lw ra, cpu_rw_handler_ra (r0)
  ori t0, 0x80
  ls_gp(sb t0, apu_envelope_count + apu_noise)

apu_set_length(apu_noise)

  jr ra
  nop

WriteDMCFlags:
// cpu_t0: Write to 0x4010
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

// TODO looping, may need to initiate here if loop turns on?

  lbu t1, irq_pending (r0)
  ls_gp(lb t2, apu_irqs)
// Clear IRQ if enabled flag is clear
  andi t0, cpu_t0, 0b1000'0000
  bnez t0,+
  andi t1, intDMC^0xff
  andi t2, 0b0111'1111
  sb t1, irq_pending (r0)
  j ++
  ls_gp(sb t2, apu_irqs)
+
// Set IRQ if active (bit 7, sign) and enabled flag is set (may have just become enabled)
  bltz t2,+
  ori t1, intDMC
  sb t1, irq_pending (r0)
+

  andi t0, cpu_t0, 0b1111
  sll t0, 1
  add t0, gp
  lhu t0, dmc_rate_table - gp_base (t0)

  lli t1, 8*cpu_div
  mult t0, t1
  mflo t2
  ls_gp(sh t0, apu_dmc_timer)

  ls_gp(sb cpu_t0, apu_dmc_regs + 0)

  ls_gp(lwu t0, apu_dmc_timer_cycles)
// Adjust schedule to reflect rate change
  ld t1, task_times + apu_dmc_task * 8 (r0)
  ls_gp(sw t2, apu_dmc_timer_cycles)
  bltz t1,+
  sub t2, t0
  dadd t1, t2
  //sd t1, task_times + apu_dmc_task * 8 (r0)
+
  jr ra
  nop

WriteDMCLoad:
// cpu_t0: Write to 0x4011
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  ori t0, cpu_t0, 0x80 // set load flag
  ls_gp(sb t0, apu_dmc_load)

  jr ra
  ls_gp(sb cpu_t0, apu_dmc_regs + 1)

WriteDMCSampleAddr:
// cpu_t0: Write to 0x4012
  jal Render
  nop
  lw ra, cpu_rw_handler_ra (r0)

  sll t0, cpu_t0, 6 // *64
  ori t0, 0x4000
  ls_gp(sh t0, apu_dmc_cur_addr)

  jr ra
  ls_gp(sb cpu_t0, apu_dmc_regs + 2)

WriteDMCSampleLength:
// cpu_t0: Write to 0x4013
  jal Render
  nop


  lw ra, cpu_rw_handler_ra (r0)

  jr ra
  ls_gp(sb cpu_t0, apu_dmc_regs + 3)

scope DMCRead: {
  addi sp, 8
  sw ra, -8 (sp)

// TODO spend cycles on the CPU task

  ls_gp(lbu t0, apu_dmc_buffer_count)
  lli t1, apu_dmc_buffer_size
  bne t0, t1,+
  nop

  jal Render
  nop
+

  ls_gp(lhu t0, apu_dmc_cur_addr)
  ls_gp(lhu t1, apu_dmc_length_left)
  addi t2, t0, 1
  andi t2, 0x7fff
  ls_gp(sh t2, apu_dmc_cur_addr)
  ori t0, 0x8000
  srl t2, t0, 8
  sll t2, 2
  lw t2, cpu_read_map (t2)
  beqz t1, end
  addi t1, -1
  bnez t1,++
  ls_gp(sh t1, apu_dmc_length_left)

  ls_gp(lb t4, apu_dmc_regs + 0)
  ls_gp(lbu t3, apu_irqs)
  andi t1, t4, 0b0100'0000 // loop
// Loop enabled?
  beqz t1,+
  ori t3, 0b1000'0000

// DMCSampleStart doesn't clobber t0 and t2
  j DMCSampleStart
  la_gp(ra,++)

+
// IRQ enabled (bit 7, sign)?
  bgez t4,+
  ls_gp(sb t3, apu_irqs)

  lbu t1, irq_pending (r0)
  ori t1, intDMC
  sb t1, irq_pending (r0)

+
  bgez t2,+
  add t2, t0
// Not supporting reading from a register
dmc_read_from_register:
  syscall 1
+

  lbu t0, 0 (t2)
  ls_gp(lbu t1, apu_dmc_buffer_count)
  addi t2, t1, 1
  subi t3, t2, apu_dmc_buffer_size
  blez t3,+
  ls_gp(sb t2, apu_dmc_buffer_count)
// The check before Render, or Render itself, should prevent this.
inconsistent_dmc_buffercount:
  syscall 1
+
  add t1, gp
  sb t0, apu_dmc_buffer - gp_base (t1)

if {defined LOG_DMC} {
  addi sp, 8

  jal PrintStr0
  la_gp(a0, dmc_msg)

if 1 == 0 {
  ls_gp(lbu t1, apu_dmc_buffer_count)
  addi t1, -1
  add t1, gp
  lbu t0, apu_dmc_buffer - gp_base (t1)

  srl t1, t0, 1
  ori t1, 0x80
-
  sb t1, -8(sp)

  ls_gp(lbu a0, apu_dmc_sim_level)
  andi t0, 1
  beqz t0,+
  addi t3, a0, -2
  addi t3, a0, 2
+
  andi t1, t3, 0x7f
  xor t1, t3
  bnez t1,+
  nop
  move a0, t3
  ls_gp(sb a0, apu_dmc_sim_level)
+
  lbu t0, -8(sp)
  srl t1, t0, 1
  bnez t1,-
  nop

  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, newline)
}

  lui a0, SP_MEM_BASE
  lbu a0, SP_DMEM + dmem_dmc_cur (a0)
  jal PrintHex
  lli a1, 2

  lui a0, SP_MEM_BASE
  lbu a0, SP_DMEM + dmem_dmc_buffer (a0)
  jal PrintHex
  lli a1, 2

  lui a0, SP_MEM_BASE
  lbu a0, SP_DMEM + dmem_dmc_buffer_count (a0)
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop

  addi sp, -8
}

end:
  lw ra, -8 (sp)
  jr ra
  addi sp, -8
}

// Must not clobber t0 and t2
DMCSampleStart:
  ls_gp(lbu t1, apu_dmc_regs + 2)
  ls_gp(lbu t3, apu_dmc_regs + 3)

  sll t1, 6 // *64
  ori t1, 0x4000
  ls_gp(sh t1, apu_dmc_cur_addr)

  sll t3, 4 // *16
  addi t3, 1
  ls_gp(sh t3, apu_dmc_length_left)

  jr ra
  nop

DMCTaskLoop:
  ls_gp(lwu t0, apu_dmc_timer_cycles)
  dadd cycle_balance, t0
  bgezal cycle_balance, Scheduler.Yield
  nop

DMCTask:
  ls_gp(lhu t0, apu_dmc_length_left)
  beqz t0, Scheduler.FinishTask
  nop

  j DMCRead
  la_gp(ra, DMCTaskLoop)

// TODO: technically this might need to be in two parts, a read from
// the CPU before it increments cycle_balance, then the effect afterwards.
// But I'm really not sure how that should work.
ReadStatus:
// Clear interrupts, return counter and interrupt status
// Returns value in cpu_t1

  ls_gp(lw t0, apu_len)
  lbu t2, irq_pending (r0)
  ls_gp(lhu t3, apu_dmc_length_left)
  
// Calculate lengths == 0
  andi t1, t0, 0xff
  slti cpu_t1, 1
  or cpu_t1, t1
  andi t1, t0, 0xff00
  slti t1, 1
  sll cpu_t1, 1
  or cpu_t1, t1

  srl t0, 16
  andi t1, t0, 0xff
  slti t1, 1
  sll cpu_t1, 1
  or cpu_t1, t1
  andi t0, 0xff00
  slti t0, 1
  sll cpu_t1, 1
  or cpu_t1, t0

  beqz t3,+
// Flip to lengths > 0
  xori cpu_t1, 0b1111
// DMC length > 0
  ori cpu_t1, 0b1'0000
+

// Clear IRQ pending, return previous status
  ls_gp(lbu t1, apu_irqs)
  andi t2, intAPUFrame^0xff
  sb t2, irq_pending (r0)
  or cpu_t1, t1
  andi t1, 0b1011'1111
  ls_gp(sb t1, apu_irqs)

  jr ra
  nop

macro apu_clock_length(idx) {
  ls_gp(lbu t1, apu_channel_0s + {idx})
  ls_gp(lbu t0, apu_len + {idx})

if {idx} == apu_tri {
  andi t1, 0b1000'0000
} else {
  andi t1, 0b0010'0000
}
// Check halt
  bnez t1,+
  nop
// Check already zero
  beqz t0,+
  addi t0, -1
  ls_gp(sb t0, apu_len + {idx})
+
}

macro apu_clock_linear_counter() {
  ls_gp(lb t0, apu_envelope_count + apu_tri)
  ls_gp(lb t1, apu_channel_0s + apu_tri)
// Count Zero or Reload (bit 7, sign)
  bgtz t0,+
  addi t2, t0, -1

  bgez t0,+
  lli t2, 0
  andi t3, t1, 0b0111'1111
// Reload set, reload, keep reload flag set
  ori t2, t3, 0x80

+
// Control flag (bit 7, sign)
  bltz t1,+
  nop
// Control flag clear, clear reset flag
  andi t2, 0b0111'1111
+
  ls_gp(sb t2, apu_envelope_count + apu_tri)
}

macro apu_clock_sweep(idx) {
scope {#} {
  ls_gp(lb t2, apu_channel_1s + {idx})
  ls_gp(lb t0, apu_sweep_count + {idx})
// Enabled? (bit 7, sign)
  bgez t2, no_update
  ls_gp(lhu t1, apu_target_timer + 2*{idx})
  andi t3, t0, 0b111 // divider count
  ls_gp(lhu t4, apu_timer + 2*{idx})
// Count Zero?
  bnez t3, no_update
  subi t3, t1, 0x7ff
// Muted high?
  bgtz t3, no_update
  subi t4, 8
// Muted low?
  bltz t4, no_update
  andi t4, t2, 0b111 // shift
// Shift nonzero?
  beqz t4, no_update
  nop
// All conditions met, change the timer
  ls_gp(sh t1, apu_timer + 2*{idx})

apu_update_target_timer({idx}, t2, t1, t3, t4)
no_update:

  bgtz t0,+
  addi t0, -1
// Count Zero, or reload flag set
  andi t0, t2, 0b0111'0000  // reload divider period
  srl t0, 4
+
  ls_gp(sb t0, apu_sweep_count + {idx})
}
}

macro apu_clock_envelope(idx) {
  ls_gp(lb t0, apu_envelope_count + {idx})
  ls_gp(lbu t1, apu_channel_0s + {idx})
  bgtz t0,++
  addi t2, t0, -1
// Count Zero or Start (bit 7, sign)
  bnez t0,+
  lli t0, 15
// Count Zero, reload count and decrement level
  ls_gp(lbu t0, apu_envelope_level + {idx})
  bgtz t0,+
  addi t0, -1
// Level was 0, restart if looping
  andi t0, t1, 0b0010'0000
  bnez t0,+
  lli t0, 15
// No loop, stay at 0
  lli t0, 0
+
// Clear start flag, set level (loaded in t0 above) and reload count
  ls_gp(sb t0, apu_envelope_level + {idx})
  andi t2, t1, 0b1111
+
  ls_gp(sb t2, apu_envelope_count + {idx})
}

scope FrameStep: {
if {defined LOG_FRAME_COUNTER} {
  jal PrintStr0
  la_gp(a0, qf_msg)

  ls_gp(lbu a0, apu_frame_counter)
  jal PrintHex
  lli a1, 2

  jal NewlineAndFlushDebug
  nop
}

// Catch up with rendering before things change
  jal Render
  nop

  ls_gp(lbu t1, apu_frame_mode)
  ls_gp(lbu t0, apu_frame_counter)

  andi t1, 0b1000'0000 // frame mode, 1 = 5-step
  beqz t1,+
  addi t2, t0, 1
  addi t0, 4
+
  sll t0, 2
  add t0, gp
  lw t0, step_jump_table - gp_base (t0)
  jr t0
  ls_gp(sb t2, apu_frame_counter)

step_jump_table:
  dw _4_step_1, _4_step_2, _4_step_3, _4_step_4
  dw _5_step_1, _5_step_2, _5_step_3, done, _5_step_5

_4_step_1:
  j ClockEnvelopeLinear
  la_gp(ra, done)
_4_step_2:
  jal ClockEnvelopeLinear
  nop
  j ClockLengthSweep
  la_gp(ra, done)
_4_step_3:
  j ClockEnvelopeLinear
  la_gp(ra, done)
_4_step_4:
  jal ClockEnvelopeLinear
  ls_gp(sb r0, apu_frame_counter)
  jal ClockLengthSweep
  nop

  ls_gp(lbu t1, apu_frame_mode)
  lbu t0, irq_pending (r0)
  andi t1, 0b0100'0000 // IRQ inhibit
  bnez t1,+
  ori t0, intAPUFrame
// TODO fix this, StarsSE hangs with this enabled. Should I assume IRQ inhibit is set on reset?
  //sb t0, irq_pending (r0)
+

  j done
  nop

_5_step_1:
  j ClockEnvelopeLinear
  la_gp(ra, done)
_5_step_2:
  jal ClockEnvelopeLinear
  nop
  j ClockLengthSweep
  la_gp(ra, done)
_5_step_3:
  j ClockEnvelopeLinear
  la_gp(ra, done)
_5_step_5:
  jal ClockEnvelopeLinear
  ls_gp(sb r0, apu_frame_counter)
  j ClockLengthSweep
  la_gp(ra, done)

ClockEnvelopeLinear:
apu_clock_linear_counter()

apu_clock_envelope(apu_p1)
apu_clock_envelope(apu_p2)
apu_clock_envelope(apu_noise)
  jr ra
  nop

ClockLengthSweep:
apu_clock_length(apu_p1)
apu_clock_length(apu_p2)
apu_clock_length(apu_tri)
apu_clock_length(apu_noise)

apu_clock_sweep(apu_p1)
apu_clock_sweep(apu_p2)
  jr ra
  nop

done:
  la t0, apu_quarter_frame_cycles
  dadd cycle_balance, t0
  j Scheduler.Yield
  la_gp(ra, FrameStep)
}

scope Render: {
  ld t2, target_cycle (r0)
  ls_gp(ld t0, apu_alist_cycle)
  dadd t2, cycle_balance
  dsub t3, t2, t0 // cycles since we last sent a config to the alist
  bgez t3,+
  nop
alist_ahead:
  syscall 1
+
  daddi t1, t3, -apu_min_render_cycles
  bgez t1,+
  nop

// Not enough cycles have passed since we started on the new config, do nothing yet
  jr ra
  nop
+

constant stack_frame(32)
  addi sp, stack_frame
constant stack_current_cycle(-8)
  sd t2, stack_current_cycle (sp)
constant stack_cycle_delta(-16)
  sd t3, stack_cycle_delta (sp)
constant stack_next_alist_idx(-24)
constant stack_ra(-32)
  sw ra, stack_ra (sp)

if {defined LOG_ALIST} {
  jal PrintDec
  ls_gp(ld a0, apu_alist_cycle)
  jal PrintStr0
  la_gp(a0, space)

  lui t1, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_alist_write (t1)
  jal PrintHex
  lli a1, 2
  jal PrintStr0
  la_gp(a0, space)
  lui t1, SP_MEM_BASE
  lw a0, SP_DMEM + dmem_alist_read (t1)
  jal PrintHex
  lli a1, 2
  jal NewlineAndFlushDebug
  nop
}

// Check that the next alist entry is free
wait_for_alist:
  lui t1, SP_MEM_BASE
  lw t0, SP_DMEM + dmem_alist_write (t1)
  lw t1, SP_DMEM + dmem_alist_read (t1)
  lli t2, num_alists-1
// Wrap
  bne t0, t2,+
  addi t3, t0, 1
  lli t3, 0
+
  bne t3, t1, alist_free
  nop

// No free alist available, try to get the RSP going
  lli t0, 1
  ls_gp(sb t0, rsp_interrupt_wait)

  jal RSP.Run
  nop

-
  ls_gp(lbu t0, rsp_interrupt_wait)
  bnez t0,-
  nop

  j wait_for_alist
  nop

alist_free:
  sb t3, stack_next_alist_idx (sp)

// Write out the current APU state to the alist entry
  la t1, (alist_buffer&0x1fff'ffff)|0x8000'0000
  sll t2, t0, alist_entry_size_shift
  add t1, t2

evaluate rep_i(0)
while {rep_i} < alist_entry_size / DCACHE_LINE {
  cache data_create_dirty_exclusive, {rep_i} * DCACHE_LINE (t1)
evaluate rep_i({rep_i}+1)
}

  ld t2, stack_cycle_delta (sp)
// TODO cycles_per_sample is an integer (~400), this would be more accurate
// with a multiply and divide
  lli t4, cycles_per_sample
  div t2, t4
  mflo t2
// Clear low bit, sample count has to be even for accurate DMA.
// apu_min_render_cycles > 2 samples so this should be safe.
// TODO this rounding should be biased somehow
  andi t4, t2, 1
  xor t2, t4
  sw t2, alist_SampleDelta (t1)

// Pulse 1
  ls_gp(lbu t2, apu_len + apu_p1)
  ls_gp(lhu t3, apu_target_timer + apu_p1 * 2)
  ls_gp(lhu t0, apu_timer + apu_p1 * 2)
  beqz t2,+
  subi t3, 0x7ff
  bgtz t3,+
  subi t3, t0, 8
  bgez t3,++
  nop
+
  lli t0, 0
+
  sh t0, alist_P1Timer (t1)

  ls_gp(lbu t0, apu_channel_0s + apu_p1)
  andi t3, t0, 0b1'0000 // constant volume
  beqz t3,+
  ls_gp(lbu t2, apu_envelope_level + apu_p1)
  andi t2, t0, 0b1111
+
  sb t2, alist_P1Env (t1)
  srl t0, 6
  sb t0, alist_P1Duty (t1)

// Pulse 2
  ls_gp(lbu t2, apu_len + apu_p2)
  ls_gp(lhu t3, apu_target_timer + apu_p2 * 2)
  ls_gp(lhu t0, apu_timer + apu_p2 * 2)
  beqz t2,+
  subi t3, 0x7ff
  bgtz t3,+
  subi t3, t0, 8
  bgez t3,++
  nop
+
  lli t0, 0
+
  sh t0, alist_P2Timer (t1)

  ls_gp(lbu t0, apu_channel_0s + apu_p2)
  andi t3, t0, 0b1'0000 // constant volume
  beqz t3,+
  ls_gp(lbu t2, apu_envelope_level + apu_p2)
  andi t2, t0, 0b1111
+
  sb t2, alist_P2Env (t1)
  srl t0, 6
  sb t0, alist_P2Duty (t1)

// Triangle
  ls_gp(lbu t0, apu_len + apu_tri)
  ls_gp(lbu t3, apu_envelope_count + apu_tri) // Linear counter
  beqz t0,+
  lli t2, 0
  andi t3, 0b0111'1111
  beqz t3,+
  nop
  ls_gp(lhu t2, apu_timer + 2*apu_tri)
+
  sh t2, alist_TriTimer (t1)

// Noise
  ls_gp(lbu t2, apu_len + apu_noise)
  ls_gp(lbu t0, apu_channel_0s + apu_noise)
  lli t4, 0
  beqz t2,+
  ls_gp(lhu t3, apu_timer + 2*apu_noise)
  andi t2, t0, 0b1'0000 // constant volume
  beqz t2,+
  ls_gp(lbu t4, apu_envelope_level + apu_noise)
  andi t4, t0, 0b1111
+

  sb t4, alist_NoiseEnv (t1)
  sh t3, alist_NoiseTimer (t1)

// DMC
// TODO disablement?
  ls_gp(lbu t0, apu_dmc_buffer_count)
  ls_gp(lb t2, apu_dmc_load)
  bltz t2,+
  nop
  lli t2, 0
+

  sb t2, alist_DMCLoad (t1)
  sb t0, alist_DMCSampleCount (t1)
  ls_gp(lhu t2, apu_dmc_timer)
  ls_gp(sb r0, apu_dmc_buffer_count)
  ls_gp(sb r0, apu_dmc_load)
  sh t2, alist_DMCTimer (t1)

// Copy the samples into the alist backwards,
// so the count can be used as an index while reading.
  beqz t0,+
  addi t0, -1
  add t2, t0, gp
  addi t3, t1, alist_DMCSamples
-
  lbu t4, apu_dmc_buffer - gp_base (t2)
  addi t2, -1
  sb t4, 0 (t3)
  addi t3, 1
  bnez t0,-
  addi t0, -1
+

// Flags
  lli t2, 0
  ls_gp(lbu t0, apu_noise_mode)
  beqz t0,+
  ls_gp(lbu t0, apu_reset_phase + apu_p1)
  ori t2, Ucode.noise_mode_flag
+
  beqz t0,+
  ls_gp(lbu t0, apu_reset_phase + apu_p2)
  ori t2, Ucode.reset_p1_flag
  ls_gp(sb r0, apu_reset_phase + apu_p1)
+
  beqz t0,+
  lhu t0, alist_TriTimer (t1)
  ori t2, Ucode.reset_p2_flag
  ls_gp(sb r0, apu_reset_phase + apu_p2)
+
  beqz t0,+
  nop
  ori t2, Ucode.tri_enabled_flag
+
  sb t2, alist_Flags (t1)

evaluate rep_i(0)
while {rep_i} < alist_entry_size / DCACHE_LINE {
  cache data_hit_write_back, {rep_i} * DCACHE_LINE (t1)
evaluate rep_i({rep_i}+1)
}

// Finally, advance write index to allow RSP to read it
  lbu t2, stack_next_alist_idx (sp)
  ld t0, stack_current_cycle (sp)
  lui t1, SP_MEM_BASE
  sw t2, SP_DMEM + dmem_alist_write (t1)
  ls_gp(sd t0, apu_alist_cycle)

// Try kicking off RSP rendering
  jal RSP.Run
  nop

if {defined LOG_ALIST} {
  addi sp, 32

  lui t0, SP_MEM_BASE
  lw t0, dmem_alist_write (t0)
  bnez t0,+
  addi t0, -1
  lli t0, num_alists-1
+
  la t1, (alist_buffer&0x1fff'ffff)|0x8000'0000
  sll t2, t0, alist_entry_size_shift
  add t1, t2

  ld a0, 0 (t1)
  ld t0, 8 (t1)
  sd t0, -32 (sp)
  ld t0, 16 (t1)
  sd t0, -24 (sp)
  ld t0, 24 (t1)
  sd t0, -16 (sp)
  jal PrintHex
  lli a1, 16
  jal PrintStr0
  la_gp(a0, newline)

  ld a0, -32 (sp)
  jal PrintHex
  lli a1, 16
  jal PrintStr0
  la_gp(a0, newline)

  ld a0, -24 (sp)
  jal PrintHex
  lli a1, 16
  jal PrintStr0
  la_gp(a0, newline)

  ld a0, -16 (sp)
  jal PrintHex
  lli a1, 16

  jal NewlineAndFlushDebug
  nop

  addi sp, -32
}

  lw ra, stack_ra (sp)
  jr ra
  addi sp, -stack_frame
}

// Called from exception handler
RenderFlush:
  addi sp, 8
  sw ra, -8 (sp)

  lui t0, SP_MEM_BASE
  lli t1, 1
  sw t1, SP_DMEM + dmem_flush_abuf (t0)
  lw r0, SP_DMEM + dmem_flush_abuf (t0)

  jal RSP.RunPriority
  lli a0, apu_rsp_task

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

frame_length_table:
  db 10,254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14
  db 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30

if {defined LOG_FRAME_COUNTER} {
qf_msg:
  db "QF: ",0
}
if {defined LOG_DMC} {
dmc_msg:
  db "DMC: ",0
}

align(4)
}
