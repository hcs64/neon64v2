// Audio synthesis
constant oversample_amount_shift(1)
constant oversample_amount(1<<oversample_amount_shift)
constant min_triangle_timer(2)
constant min_abuf_margin(3)

constant reset_p1_flag(1)
constant reset_p2_flag(2)
constant tri_enabled_flag(4)
constant noise_mode_flag(8)

InitAPU:
  lli t0, 1
  jr ra
  sh t0, dmem_noise_reg (r0)

scope RunAPU: {
  lhu a0, dmem_abuf_samples_left (r0)
  bnez a0, check_alist
  lli ra, RunAPU
// 0 samples = no current buffer, get a new one

// Check that we're not getting too close to the next read buffer
  lw t0, dmem_abuf_write (r0)
  lw t1, dmem_abuf_read (r0)
  addi t2, t0, min_abuf_margin
  subi t3, t2, num_abufs
  bltz t3,+
  nop
  move t2, t3
+
  beq t2, t1, skip_render
  nop

// Wrap
  lli t2, num_abufs-1
  bne t0, t2,+
  addi t0, 1
  lli t0, 0
+

  sll t0, 2
  lw t0, dmem_abuf_addrs (t0)
  sw t0, dmem_abuf_pos (r0)

  lli a0, abuf_samples
  sh a0, dmem_abuf_samples_left (r0)

check_alist:
  lw t1, dmem_alist_entry + alist_SampleDelta (r0)
  bnez t1, alist_ready
  sub t2, t1, a0
// 0 samples left for current config, load a new one
  lw t3, dmem_alist_read (r0)
  lw t4, dmem_alist_write (r0)
  la sp_t5, alist_buffer&0x7f'ffff
  bne t3, t4,+
  sll sp_t6, t3, alist_entry_size_shift
// alist buffer is empty, do nothing unless we're flushing
  lw t0, dmem_flush_abuf (r0)
  beqz t0, skip_render
  nop
// Flushing, render the rest of the samples in the buffer anyway using
// the current config.
  j render_samples
  sw r0, dmem_flush_abuf (r0)
+

// DMA in the new alist entry
  add sp_t5, sp_t6
  mtc0 sp_t5, C0_DRAM_ADDR
  lli sp_t5, dmem_alist_entry
  mtc0 sp_t5, C0_MEM_ADDR
  lli sp_t5, alist_entry_size-1
  mtc0 sp_t5, C0_RD_LEN

-
  mfc0 t2, C0_DMA_BUSY
  bnez t2,-
  nop

// Release alist entry
  lli t2, num_alists-1
  bne t3, t2,+
  addi t3, 1
  lli t3, 0
+
  sw t3, dmem_alist_read (r0)
  lw t1, dmem_alist_entry + alist_SampleDelta (r0)
  sub t2, t1, a0

alist_ready:
// t2 = alist samples left (t1) - abuf samples left (a0)
  bgez t2,+
  nop
// alist ends before end of buffer, stop at alist end
  move a0, t1
+
  sub t1, a0
  sw t1, dmem_alist_entry + alist_SampleDelta (r0)

scope render_samples: {
// a0 = number of samples to render

constant samples_left(a0)
constant sample_ptr(a1)
constant tri_timer_init(sp_s0)
constant tri_timer(sp_s1)
constant tri_sample(sp_s2)
constant timer_dec(sp_s3)
constant p1_timer_init(sp_s4)
constant p1_timer(sp_s5)
constant p1_sample(sp_s6)
constant p2_timer_init(sp_s7)
constant p2_timer(a2)
constant p2_sample(a3)
constant sample_sum(sp_t7)
constant oversampling(sp_t6)
constant noise_timer(sp_t5)
constant noise_timer_init(sp_v0)
constant noise_sample(v1)
constant dmc_timer(k0)
constant dmc_timer_init(k1)
constant dmc_sample(t9)

  lli sample_ptr, dmem_dst

// APU rate is half CPU rate
  la timer_dec, (clock_rate<<16)/cpu_div/2/samplerate/oversample_amount

// Load P1
  lbu t0, dmem_alist_entry + alist_Flags (r0)
  lhu p1_timer_init, dmem_alist_entry + alist_P1Timer (r0)
  lw p1_timer, dmem_p1_timer (r0)
  andi t1, t0, reset_p1_flag
  beqz t1,+
  xori t0, reset_p1_flag
  sb t0, dmem_alist_entry + alist_Flags (r0)
  sb r0, dmem_p1_phase (r0)
+
  lli p1_sample, 0
  beqz p1_timer_init,+
  nop
  addi p1_timer_init, 1
  sll p1_timer_init, 16

macro scope update_pulse_sample(duty, phase, env, sample_reg, inc_reg, tmp1, tmp2) {
scope {#} {
  lbu {tmp1}, dmem_alist_entry + {duty} (r0)
  lbu {tmp2}, {phase} (r0)
  lbu {tmp1}, dmem_pulse_sequence_table ({tmp1})
if {inc_reg} != r0 {
  add {tmp2}, {inc_reg}
}
  andi {tmp2}, 7
  srlv {tmp1}, {tmp2}
  andi {tmp1}, 1
  lli {sample_reg}, 0
  beqz {tmp1}, end
  sb {tmp2}, {phase} (r0)
  lbu {sample_reg}, dmem_alist_entry + {env} (r0)
end:
}
}

update_pulse_sample(alist_P1Duty, dmem_p1_phase, alist_P1Env, p1_sample, r0, t0, t1)
+

// Load P2
  lbu t0, dmem_alist_entry + alist_Flags (r0)
  lhu p2_timer_init, dmem_alist_entry + alist_P2Timer (r0)
  lw p2_timer, dmem_p2_timer (r0)
  andi t1, t0, reset_p2_flag
  beqz t1,+
  xori t0, reset_p2_flag
  sb t0, dmem_alist_entry + alist_Flags (r0)
  sb r0, dmem_p2_phase (r0)
+
  lli p2_sample, 0
  beqz p2_timer_init,+
  nop
  addi p2_timer_init, 1
  sll p2_timer_init, 16
update_pulse_sample(alist_P2Duty, dmem_p2_phase, alist_P2Env, p2_sample, r0, t0, t1)
+

// Load Tri
macro update_tri_sample(inc_reg, tmp1) {
  lbu {tmp1}, dmem_tri_phase (r0)
if {inc_reg} != r0 {
  add {tmp1}, {inc_reg}
}
  andi {tmp1}, 0x1f
  lbu tri_sample, dmem_tri_sequence_table ({tmp1})
if {inc_reg} != r0 {
  sb {tmp1}, dmem_tri_phase (r0)
}
}

update_tri_sample(r0, t0)

  lbu tri_timer_init, dmem_alist_entry + alist_Flags (r0)
  andi tri_timer_init, tri_enabled_flag
// Don't step if disabled
  beqz tri_timer_init,+
  nop
  lhu tri_timer_init, dmem_alist_entry + alist_TriTimer (r0)
  subi t0, tri_timer_init, min_triangle_timer
  addi tri_timer_init, 1
// Don't step if period is too short
  bgez t0,+
  sll tri_timer_init, 16
  lli tri_timer_init, 0
  lli tri_sample, 22 // approximately 7.5*3
+
  lw tri_timer, dmem_tri_timer (r0)

// Load Noise
  lhu noise_timer_init, dmem_alist_entry + alist_NoiseTimer (r0)
  lw noise_timer, dmem_noise_timer (r0)

  addi noise_timer_init, 1
  sll noise_timer_init, 16

macro update_noise_sample(inc_reg, tmp1, tmp2, tmp3) {
scope {#} {
if {inc_reg} != r0 {
  lbu {tmp1}, dmem_alist_entry + alist_Flags (r0)
}
  lhu noise_sample, dmem_noise_reg (r0)
if {inc_reg} != r0 {
  andi {tmp1}, noise_mode_flag
  beqz {tmp1}, mode_done
  lli {tmp3}, 1
  lli {tmp3}, 6
mode_done:

loop:
// Assume initially > 0
  addi {inc_reg}, -1

  andi {tmp1}, noise_sample, 1
  srlv {tmp2}, noise_sample, {tmp3}
  xor {tmp1}, {tmp2}
  andi {tmp1}, 1
  srl noise_sample, 1
  sll {tmp1}, 14
  bnez {inc_reg}, loop
  or noise_sample, {tmp1}

  sh noise_sample, dmem_noise_reg (r0)
}

  andi noise_sample, 1
// Use envelope if 0
  bnez noise_sample, end
  lli noise_sample, 0
  lbu noise_sample, dmem_alist_entry + alist_NoiseEnv (r0)
end:
}
}

update_noise_sample(r0, t0, t1, t2)
+

// Load DMC
  lb t0, dmem_alist_entry + alist_DMCLoad (r0)
  lw dmc_timer, dmem_dmc_timer (r0)
  lbu dmc_sample, dmem_dmc_level (r0)
  bgez t0,+
  lhu dmc_timer_init, dmem_alist_entry + alist_DMCTimer (r0)
  andi dmc_sample, t0, 0x7f
  sb dmc_sample, dmem_dmc_level (r0)
  sb r0, dmem_alist_entry + alist_DMCLoad (r0)
+
  beqz dmc_timer_init,+
  nop
  addi dmc_timer_init, 1
  sll dmc_timer_init, 16
+

macro update_dmc_sample(inc_reg, tmp1, tmp2, tmp3, tmp4) {
scope {#} {
loop:
// Assume initially > 0
  addi {inc_reg}, -1

  lbu {tmp2}, dmem_dmc_cur (r0)
  lbu {tmp1}, dmem_alist_entry + alist_DMCSampleCount (r0)
  srl {tmp4}, {tmp2}, 1
  bnez {tmp4}, sample_present
  andi {tmp2}, 1

// Load a new sample byte
  addi {tmp2}, {tmp1}, -1
  lbu {tmp3}, dmem_alist_entry + alist_DMCSamples ({tmp2})
  beqz {tmp1}, done
  nop
  sb {tmp2}, dmem_alist_entry + alist_DMCSampleCount (r0)
  andi {tmp2}, {tmp3}, 1
  srl {tmp4}, {tmp3}, 1
  ori {tmp4}, 0x80

sample_present:
  sb {tmp4}, dmem_dmc_cur (r0)

  beqz {tmp2}, down
  addi {tmp2}, dmc_sample, -2
  addi {tmp2}, dmc_sample, 2
down:
  andi {tmp4}, {tmp2}, 0x7f
  xor {tmp4}, {tmp2}
  bnez {tmp4}, out_of_range
  nop
  move dmc_sample, {tmp2}
out_of_range:

  bnez {inc_reg}, loop
  nop
done:
  sb dmc_sample, dmem_dmc_level (r0)
}
}

// Init mix
  lli sample_sum, 0
  lli oversampling, oversample_amount-1

sample_loop:
// mix current sample

// tri is pre-multiplied (*3)
// noise*2
  add t1, tri_sample, noise_sample
  add t1, noise_sample
  add t1, dmc_sample
  lbu t0, dmem_dtn_mix_table (t1)

  add t2, p1_sample, p2_sample
  lbu t3, dmem_pulse_mix_table (t2)

  add t0, t3
  add sample_sum, t0

  bnez oversampling,+
  addi oversampling, -1

  sll sample_sum, 7-oversample_amount_shift

  sh sample_sum, 0 (sample_ptr)
  sh sample_sum, 2 (sample_ptr)

  addi samples_left, -1
  addi sample_ptr, 4

  lli sample_sum, 0
  lli oversampling, oversample_amount-1
+

// step timers
// P1
  beqz p1_timer_init,+
  nop
  sub p1_timer, timer_dec
  bgtz p1_timer,+
  lli t0, 0
-
  add p1_timer, p1_timer_init
  blez p1_timer,-
  addi t0, 1

update_pulse_sample(alist_P1Duty, dmem_p1_phase, alist_P1Env, p1_sample, t0, t1, t2)
+

// P2
  beqz p2_timer_init,+
  nop
  sub p2_timer, timer_dec
  bgtz p2_timer,+
  lli t0, 0
-
  add p2_timer, p2_timer_init
  blez p2_timer,-
  addi t0, 1

update_pulse_sample(alist_P2Duty, dmem_p2_phase, alist_P2Env, p2_sample, t0, t1, t2)
+

// Tri
  beqz tri_timer_init,+
  nop

// Tri is clocked at CPU rate, twice APU
  sub tri_timer, timer_dec
  sub tri_timer, timer_dec
  bgtz tri_timer,+
  lli t0, 0
-
  add tri_timer, tri_timer_init
  blez tri_timer,-
  addi t0, 1

update_tri_sample(t0, t1)
+

// Noise
  sub noise_timer, timer_dec
  bgtz noise_timer,+
  lli t0, 0
-
  add noise_timer, noise_timer_init
  blez noise_timer,-
  addi t0, 1

update_noise_sample(t0, t1, t2, t3)
+

// DMC
  beqz dmc_timer_init,+
  nop

// DMC is clocked at CPU rate, twice APU
  sub dmc_timer, timer_dec
  sub dmc_timer, timer_dec
  bgtz dmc_timer,+
  lli t0, 0

-
  add dmc_timer, dmc_timer_init
  blez dmc_timer,-
  addi t0,1

update_dmc_sample(t0, t1, t2, t3, t4)
+

// loop
  bnez samples_left, sample_loop
  nop

// save
  sw p1_timer, dmem_p1_timer (r0)
  sw p2_timer, dmem_p2_timer (r0)
  sw tri_timer, dmem_tri_timer (r0)
  sw noise_timer, dmem_noise_timer (r0)
  sw dmc_timer, dmem_dmc_timer (r0)
}

render_done:
// a1 = dmem_dst + samples rendered * 4

// DMA out samples
  lw a2, dmem_abuf_pos (r0)
  lli t2, dmem_dst
  mtc0 t2, C0_MEM_ADDR
  mtc0 a2, C0_DRAM_ADDR
  sub t2, a1, t2
  subi t2, 1
  mtc0 t2, C0_WR_LEN

-
  mfc0 t1, C0_DMA_BUSY
  bnez t1,-
  nop

  addi t2, 1
  add t0, a2, t2
  srl t2, 2

  lhu a0, dmem_abuf_samples_left (r0)
  sub a0, t2
  sh a0, dmem_abuf_samples_left (r0)

// Try another alist if we didn't fill the buffer
  bnez a0, check_alist
  sw t0, dmem_abuf_pos (r0)

// Release the buffer for playback
  lw t0, dmem_abuf_write (r0)
  lli t1, num_abufs-1
// Wrap
  bne t0, t1,+
  addi t0, 1
  lli t0, 0
+
  sw t0, dmem_abuf_write (r0)

// Yield to scheduler
  la a0, AI.PlayBufferFromSP
  sw a0, dmem_completion_vector (r0)
skip_render:
  lw t0, dmem_flush_abuf (r0)
  lw t1, dmem_alist_read (r0)
  lw t2, dmem_alist_write (r0)
  bnez t0,+
  lli t0, 1
  beq t1, t2,++
  nop
+
  sb t0, dmem_work_left (r0)
+
  j Yield
  nop
}
