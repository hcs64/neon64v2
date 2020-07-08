// CPU assorted I/O (0x4000-0x4018, has to handle up to 0x6000)

//define LOG_IO_READ()
//define LOG_IO_WRITE()

begin_bss()
align(4)
joy1:
  dw 0

joy1_shift:
  db 0
joy_strobe:
  db 0

align(4)
end_bss()

io_read_handler:
  sw ra, cpu_rw_handler_ra (r0)
// cpu_t1: address
// return value in cpu_t1

if {defined LOG_IO_READ} {

  jal PrintStr0
  la_gp(a0, io_read_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4
}

  subi t0, cpu_t1, 0x4015
  bnez t0, not_read_4015
  nop

  //jal Scheduler.YieldFromCPU
  //nop

  jal APU.ReadStatus
  la_gp(ra, io_read_done)

not_read_4015:
  subi t0, cpu_t1, 0x4016
  bnez t0, not_read_4016
  nop

  ls_gp(lbu t0, joy_strobe)
  ls_gp(lbu t1, joy1_shift)
  bnez t0,+
  srl cpu_t1, t1, 7
// Simulate open bus, last read would have likely been the 0x40
// as the high byte of LD? 0x4016: ?? 16 40.
// Required for at least Mad Max.
  ori cpu_t1, 0x40

  sll t1, 1
  ori t1, 1
  ls_gp(sb t1, joy1_shift)
+

  j io_read_done
  nop

not_read_4016:

// TODO nothing implemented yet
  lli cpu_t1, 0

io_read_done:

if {defined LOG_IO_READ} {
  jal PrintStr0
  la_gp(a0, val_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, cycle_msg)

  ld a0, target_cycle (r0)
  jal PrintDec
  daddu a0, cycle_balance

  jal NewlineAndFlushDebug
  nop

}

  lw ra, cpu_rw_handler_ra (r0)
  jr ra
  nop

io_write_handler:
// cpu_t0: value
// cpu_t1: address

if {defined LOG_IO_WRITE} {
  sw ra, cpu_rw_handler_ra (r0)

if 1 == 1 {
  lli t0, 0x4015
  beq t0, cpu_t1,+
  andi t0, cpu_t1, 0xfffc
  subi t0, 0x4010
  bnez t0,++
  nop
+
}

  jal PrintStr0
  la_gp(a0, io_write_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

  jal PrintStr0
  la_gp(a0, val_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, cycle_msg)

  ld a0, target_cycle (r0)
  jal PrintDec
  daddu a0, cycle_balance

  jal NewlineAndFlushDebug
  nop

+
  lw ra, cpu_rw_handler_ra (r0)
}
  
  andi t0, cpu_t1, 0xffff^(0x401f)
  bnez t0, io_write_done_no_load_ra
  andi t0, cpu_t1, 0x1f
  sll t0, 2
  add t0, gp
  lw t0, io_write_jump_table - gp_base (t0)
  sw ra, cpu_rw_handler_ra (r0)
  jr t0
  la_gp(ra, io_write_done)

macro io_write_label(evaluate addr) {
io_write_{addr}:
}

macro io_write_constant(evaluate addr, v) {
constant io_write_{addr}({v})
}

// TODO Probably not all these yields are needed? The idea
// is to give the APU a chance to catch up before the write,
// but there are likely to be quite a few of these in succession.
io_write_label(0x4000)
io_write_label(0x4004)
io_write_label(0x4008)
io_write_label(0x400c)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.Write_0)

io_write_label(0x4001)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteP1_1)
io_write_label(0x4005)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteP2_1)
io_write_constant(0x4009, io_write_done)
io_write_constant(0x400d, io_write_done)

io_write_label(0x4002)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteP1TimerLow)
io_write_label(0x4006)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteP2TimerLow)
io_write_label(0x400a)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteTriTimerLow)
io_write_label(0x400e)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteNoisePeriod)

io_write_label(0x4003)
  jal Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteP1Length)
io_write_label(0x4007)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteP2Length)
io_write_label(0x400b)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteTriLength)
io_write_label(0x400f)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteNoiseLength)

io_write_label(0x4010)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteDMCFlags)
io_write_label(0x4011)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteDMCLoad)
io_write_label(0x4012)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteDMCSampleAddr)
io_write_label(0x4013)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteDMCSampleLength)

io_write_label(0x4014)
  daddi cycle_balance, 513 * cpu_div
  jal PPU.OAMDMA
  la_gp(ra, io_write_done)

io_write_label(0x4015)
  j Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteEnable)

io_write_label(0x4016)
  andi t0, cpu_t0, 1
  ls_gp(sb t0, joy_strobe)
  beqz t0, io_write_done
  nop

constant joystick_threshold(32)

  ls_gp(lbu t0, joy1)
  ls_gp(lb t1, joy1+2)
  ls_gp(lb t2, joy1+3)

  subi t3, t1, joystick_threshold
  bltz t3,+
  addi t3, t1, joystick_threshold
  ori t0, 0b0001
+
  bgtz t3,+
  subi t3, t2, joystick_threshold
  ori t0, 0b0010
+
  bltz t3,+
  addi t3, t2, joystick_threshold
  ori t0, 0b1000
+
  bgtz t3,+
  nop
  ori t0, 0b0100
+

  j io_write_done
  ls_gp(sb t0, joy1_shift)

io_write_label(0x4017)
  jal Scheduler.YieldFromCPU
  la_gp(ra, APU.WriteFrameCounter)

io_write_done:
// NOTE: A lot of handlers don't come through here, they load
// cpu_rw_handler_ra and return on their own.
  lw ra, cpu_rw_handler_ra (r0)
io_write_done_no_load_ra:
  jr ra
  nop

io_write_jump_table:
evaluate rep_i(0x4000)
while {rep_i} < 0x4018 {
  dw io_write_{rep_i}
evaluate rep_i({rep_i}+1)
}
while {rep_i} < 0x4020 {
  dw io_write_done
evaluate rep_i({rep_i}+1)
}

io_write_msg:
  db " IO write ", 0
io_read_msg:
  db " IO  read ", 0

align(4)
