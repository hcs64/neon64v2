// TODO consider other values in regs:
// - stack (could be ptr)

// Ref timing: http://nesdev.com/6502_cpu.txt

//define LOG_CPU()
//define LOG_IRQ()
//define TRAP_BAD_WRITE()

define UNOFFICIAL_OPCODES()

constant flagN(0x80)
constant flagV(0x40)
constant flag1(0x20)
constant flagB(0x10)
constant flagD(0x08)
constant flagI(0x04)
constant flagZ(0x02)
constant flagC(0x01)

// pending interrupts
constant intAPUFrame(0x01)
constant intMMC3(0x02)
constant intDMC(0x04)
constant intDelayed(0x80)

begin_low_page()

align_dcache()
cpu_mpc_base:;    dw 0
// These two are accessed together as a dh
interrupt_pending:
irq_pending:;     db 0
nmi_pending:;     db 0

cpu_flags:;       db 0
cpu_stack:;       db 0
cpu_n_byte:;      db 0
cpu_z_byte:;      db 0
cpu_c_byte:;      db 0

align(4)
// To avoid stack manipulations, or the use of an extra register
cpu_rw_handler_ra:; dw 0

end_low_page()

// a0 = new PC low byte
// a1 = new PC high byte
// Must not touch any other regs as this is used in TLBMiss.
SetPC:
  sll a1, 2
  lw cpu_mpc, cpu_read_map (a1)
  sll a1, 8-2
  or a0, a1
  sw cpu_mpc, cpu_mpc_base (r0)
  jr ra
  addu cpu_mpc, a0

macro set_pc_and_finish(lo, hi) {
  sll {hi}, 2
  lw cpu_mpc, cpu_read_map ({hi})
  sll {hi} , 8-2
  sw cpu_mpc, cpu_mpc_base (r0)
  addu cpu_mpc, {hi}
  j FinishCycleAndFetchOpcode
  addu cpu_mpc, {lo}
}

// Probably don't want to use this directly so something else can go in delay slot
macro get_pc(out_reg) {
// NOTE: Technically this should be masking 0xffff in case we incremented off the end of memory,
// but I'm not going to worry about it.
  lw {out_reg}, cpu_mpc_base (r0)
// delay slot?
  subu {out_reg}, cpu_mpc, {out_reg}
}

macro get_flags(out_reg, tmp1, tmp2) {
  lbu {tmp1}, cpu_z_byte (r0)
  lbu {out_reg}, cpu_flags (r0)
  bnez {tmp1},+
  lb {tmp1}, cpu_n_byte (r0)
  ori {out_reg}, flagZ
+
  lbu {tmp2}, cpu_c_byte (r0)
  bgez {tmp1},+
  or {out_reg}, {tmp2}
  ori {out_reg}, flagN
+
}

ex_nop:
FinishCycleAndFetchOpcode:
  daddi cycle_balance, cpu_div
TestNextCycleAndFetchOpcode:
  bgezal cycle_balance, Scheduler.YieldFromCPU
  nop // use this delay slot?
// Entry to CPU loop. This will only return through Scheduler.YieldFromCPU
FetchOpcode:
// Cycle 1: Fetch opcode, increment PC

  lhu t1, interrupt_pending (r0)
opcode_fetch_lbu:
  lbu cpu_t0, 0 (cpu_mpc)

  bnez t1, TakeInt
  la_gp(cpu_t1, opcode_table)
dont_take_int:

if {defined LOG_CPU} {
if 1 != 1 {
  ls_gp(lbu t0, menu_enabled)
  beqz t0,+
  nop
}

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintCPUInfo
  nop

  jal NewlineAndFlushDebug
  nop
+
}

  addi cpu_mpc, 1

  daddi cycle_balance, cpu_div

// Cycle 2: Begin executing opcode
  bgezal cycle_balance, Scheduler.YieldFromCPU
  sll cpu_t0, 3
  addu cpu_t0, cpu_t1
  jr cpu_t0
  nop // use delay slot?

include "opcodes.asm"

macro addr_fetch_imm(evaluate fetch_reg) {
  lbu {fetch_reg}, 0 (cpu_mpc)

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addi cpu_mpc, 1
}

macro addr_fetch_lh_imm(evaluate low_reg, evaluate high_reg) {
  lbu {low_reg}, 0 (cpu_mpc)
  lbu {high_reg}, 1 (cpu_mpc)

  daddi cycle_balance, cpu_div * 2
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addi cpu_mpc, 2
}

macro addr_fetch_ix(evaluate low_reg, evaluate high_reg) {
  lbu {high_reg}, 0 (cpu_mpc)
  addi cpu_mpc, 1
  add {high_reg}, cpu_x
  andi {high_reg}, 0xff
  lbu {low_reg}, nes_ram ({high_reg})
  addi {high_reg}, 1
  andi {high_reg}, 0xff

  daddi cycle_balance, cpu_div * 4
  bgezal cycle_balance, Scheduler.YieldFromCPU
  lbu {high_reg}, nes_ram ({high_reg})
}


// R addressing modes
// Enter:
//   cpu_t0: execute
// Exit:
//   lbu cpu_t1
//   jr cpu_t0

// cpu_t1 (low addr) must be 0-0xff
macro read_abs_no_carry_and_finish() {
  sll cpu_t2, 2
  lw t0, cpu_read_map (cpu_t2)

  sll cpu_t2, 8-2
  or cpu_t1, cpu_t2

  bltz t0,+
  add t1, t0, cpu_t1

  jr cpu_t0
  lbu cpu_t1, 0 (t1)

+
  jr t0
  move ra, cpu_t0
}

addr_r_imm:
// Cycle 2: Fetch value, increment PC
  lbu cpu_t1, 0 (cpu_mpc)
  jr cpu_t0
  addi cpu_mpc, 1

addr_r_zp:
// Cycle 2: Fetch address, increment PC
  addr_fetch_imm(cpu_t1)

// Cycle 3: Read
  jr cpu_t0
  lbu cpu_t1, nes_ram (cpu_t1)

macro addr_r_zxy(evaluate reg) {
// Cycle 2: Fetch address, increment PC
  addr_fetch_imm(cpu_t1)

// Cycle 3: Read from unindexed address (no effect), add X/Y
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addu cpu_t1, {reg}

// Cycle 4: Read, execute
  andi cpu_t1, 0xff
  jr cpu_t0
  lbu cpu_t1, nes_ram (cpu_t1)
}

addr_r_zx:
  addr_r_zxy(cpu_x)

addr_r_zy:
  addr_r_zxy(cpu_y)

addr_r_abs:
// Cycle 2: Read low address byte
// Cycle 3: Read high address byte
  addr_fetch_lh_imm(cpu_t1, cpu_t2)

// Cycle 4: Read, execute
  read_abs_no_carry_and_finish()

macro addr_r_absxy(reg) {
// Cycle 2: Read low address byte
// Cycle 3: Read high address byte
  addr_fetch_lh_imm(cpu_t2, cpu_t1)

  add cpu_t2, {reg}

// Cycle 4 (or 5): Read from effective address
  andi t1, cpu_t2, 0xff
  sll t2, cpu_t1, 8
  or cpu_t1, t1, t2

  srl t3, t2, 8-2
  bne t1, cpu_t2,++
-
  lw t0, cpu_read_map (t3)

  bgez t0,+
  addu t1, t0, cpu_t1

  jr t0
  move ra, cpu_t0

+
  jr cpu_t0
  lbu cpu_t1, 0 (t1)

// Cycle 4a: Read from wrong effective address
+
// Only need to read if it has a side effect.
  bgez t0,+
  nop

// Call read handler (reads into cpu_t1)
  jalr t0
  move cpu_t2, cpu_t1

  move cpu_t1, cpu_t2
+

// Fix address, retry
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addi cpu_t1, 0x100
  andi cpu_t1, 0xffff
  andi t3, cpu_t1, 0xff00
  j -
  srl t3, 8-2
}

addr_r_absx:
  addr_r_absxy(cpu_x)

addr_r_absy:
  addr_r_absxy(cpu_y)

addr_r_ix:
// Cycle 2: Fetch pointer address, increment PC
// Cycle 3: Read from address, add X
// Cycle 4: Fetch effective address low
// Cycle 5: Fetch effective address high
  addr_fetch_ix(cpu_t1, cpu_t2)

// Cycle 6: Read from effective address
  read_abs_no_carry_and_finish()

scope addr_r_iy: {
// Cycle 2: Fetch pointer address, increment PC
  addr_fetch_imm(cpu_t1)

// Cycle 3: Fetch effective address low (ZP)
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  lbu cpu_t2, nes_ram (cpu_t1)

// Cycle 4: Fetch effective address high (ZP)
  addi cpu_t1, 1
  andi cpu_t1, 0xff
  lbu cpu_t1, nes_ram (cpu_t1)

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  add cpu_t2, cpu_y

// Cycle 5 (or 6): Read from effective address
  andi t1, cpu_t2, 0xff
  move t3, cpu_t2
  sll t0, cpu_t1, 8
  sll t2, cpu_t1, 2
  or cpu_t1, t1, t0

  bne t1, t3, cycle5a
retry:
  lw t0, cpu_read_map (t2)

  bgez t0,+
  add t1, t0, cpu_t1

  jr t0
  move ra, cpu_t0

+
  jr cpu_t0
  lbu cpu_t1, 0 (t1)

// Cycle 5a: Read from wrong effective address
cycle5a:
// Only need to read if it has a side effect.
  bgez t0,+
  nop

// Call read handler (reads into cpu_t1)
  jalr t0
  move cpu_t2, cpu_t1

  move cpu_t1, cpu_t2
+

// Fix address, retry
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addi cpu_t1, 0x100
  andi cpu_t1, 0xffff
  andi t2, cpu_t1, 0xff00
  j retry
  srl t2, 8-2
}

// RMW addressing modes
// Enter:
//   cpu_t0: execute
// Call execute:
//   a0: value
//   jal cpu_t0
//   returns with new value in a0
// Exit:
//   j FinishCycleAndFetchOpcode

addr_rw_zp:
// Cycle 2: Fetch address, increment PC
  lbu cpu_t1, 0 (cpu_mpc)
  addi cpu_mpc, 1

// Cycle 3: Read from effective address
// Cycle 4: Write back old value (no effect on ZP), execute
  jalr cpu_t0
  lbu a0, nes_ram (cpu_t1)

// Cycle 5: Write
  daddi cycle_balance, cpu_div * 4
  j TestNextCycleAndFetchOpcode
  sb a0, nes_ram (cpu_t1)

addr_rw_zx:
// Cycle 2: Fetch address, increment PC
  lbu cpu_t1, 0 (cpu_mpc)
  addi cpu_mpc, 1
// Cycle 3: Read from unincremented address (no effect on ZP), add X
  addu cpu_t1, cpu_x
  andi cpu_t1, 0xff
// Cycle 4: Read from effective address
// Cycle 5: Write back old value to effective address (no effect on ZP), execute
  jalr cpu_t0
  lbu a0, nes_ram (cpu_t1)
// Cycle 6: Write new value to effective address
  daddi cycle_balance, cpu_div * 5
  j TestNextCycleAndFetchOpcode
  sb a0, nes_ram (cpu_t1)

scope addr_rw_abs: {
// Cycle 2: Fetch low address byte, increment PC
// Cycle 3: Fetch high address byte, increment PC
  addr_fetch_lh_imm(cpu_t1, cpu_t2)

// Cycle 4: Read from effective address
  sll cpu_t2, 2
  lw t0, cpu_read_map (cpu_t2)

  sll cpu_t2, 8-2
  or cpu_t1, cpu_t2
  bgez t0, pod_read
  move cpu_t2, cpu_t1

// Call read handler (reads into cpu_t1)
  jr t0
  la_gp(ra, write_back)

pod_read:
  addu t0, cpu_t1
  lbu cpu_t1, 0 (t0)

write_back:
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  nop

// Cycle 5: Write back old value, execute
// I have to rotate the regs here to match protocols.
// Before:
// cpu_t0: exec callback (common with read, TODO this could change or be run earlier)
// cpu_t1: read value (from read handler, so exec can stay in cpu_t0)
// cpu_t2: address
// After:
// cpu_t0: read value (for write handler)
// cpu_t1: address (for write handler)
// cpu_t2: exec callback

// TODO if this can't improve, xor swap might be slightly shorter?
  move t0, cpu_t0
  move cpu_t0, cpu_t1
  move cpu_t1, cpu_t2
  move cpu_t2, t0

  andi t1, cpu_t1, 0xff00
  srl t1, 8-2
  lw t0, cpu_write_map (t1)

  // no need to do first write for plain data
  bgez t0, pod
  add t1, t0, cpu_t1

// Call write handler
  jalr t0
  nop

// Execute
  jalr cpu_t2
  move a0, cpu_t0

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  move cpu_t0, a0

// Cycle 6: Write
  andi t1, cpu_t1, 0xff00
  srl t1, 8-2
  lw t0, cpu_write_map (t1)

  bgez t0, changed_to_pod
  nop

// Call write handler
  jr t0
  la_gp(ra, FinishCycleAndFetchOpcode)

changed_to_pod:
// Not sure if it could change to POD, trap just in case
  syscall 1

pod:
// Execute
  move a0, cpu_t0
  jalr cpu_t2
  move cpu_t1, t1

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  move cpu_t0, a0

// Cycle 6: Write
  j FinishCycleAndFetchOpcode
  sb cpu_t0, 0 (cpu_t1)
}

scope addr_rw_absx: {
// Cycle 2: Fetch low byte of address, increment PC
// Cycle 3: Fetch high byte of address, add X to low, increment PC
  addr_fetch_lh_imm(cpu_t1, cpu_t2)
  addu t1, cpu_t1, cpu_x
cycle4:
// Cycle 4: Read from wrong effective address, fix high byte
  andi t0, t1, 0xff
  sll cpu_t2, 2
  lw t2, cpu_read_map (cpu_t2)
  sll cpu_t2, 8-2
  or cpu_t2, t0

  beq t0, t1, no_fixup
  move cpu_t1, cpu_t2
  addi cpu_t2, 0x100
  andi cpu_t2, 0xffff
no_fixup:

  bgez t2,+
  nop
// Call read handler (reads into cpu_t1)
  jalr t2
  nop
+
// No need to actually do wrong read for POD (it's the reed!)

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  nop

// Cycle 5: Read from effective address
  andi t0, cpu_t2, 0xff00

  srl t0, 8-2
  lw t0, cpu_read_map (t0)

  bgez t0, addr_rw_abs.pod_read
  move cpu_t1, cpu_t2
// Call read handler (reads into cpu_t1)
  jr t0
  la_gp(ra, addr_rw_abs.write_back)

// Cycle 6: Write back the old value to effective address
// Cycle 7: Write the new value to effective address
// I'm reusing cycles 5 and 6 of addr_rw_abs for this.
}

// W addressing modes
// Enter:
//   cpu_t0: value to write (this assumes that the register to write doesn't
//           change during an instruction)
// Exit:
//   j FinishCycleAndFetchOpcode

// lo_addr must be 0-0xff
// This should always be data=cpu_t0, lo_addr=cpu_t1 in order to interface
// correctly with write handlers
macro write_abs_no_carry_and_finish(evaluate data, evaluate lo_addr, evaluate hi_addr) {
  sll {hi_addr}, 2
  lw t0, cpu_write_map ({hi_addr})

  sll {hi_addr}, 8-2
  or {lo_addr}, {hi_addr}

  bltz t0,+
  addu t1, t0, {lo_addr}

  j FinishCycleAndFetchOpcode
  sb {data}, 0 (t1)

+
  jr t0
  la_gp(ra, FinishCycleAndFetchOpcode)
}

// lo_addr may be 0-0x1ff
// This should always be data=cpu_t0, lo_addr=cpu_t1 in order to interface
// correctly with write handlers
macro write_abs_carry_and_finish(evaluate data, evaluate lo_addr, evaluate hi_addr) {
  sll {hi_addr}, 8
  add {lo_addr}, {hi_addr}
  andi {lo_addr}, 0xffff
  srl {hi_addr}, {lo_addr}, 8
  sll {hi_addr}, 2
  lw t0, cpu_write_map ({hi_addr})

  bltz t0,+
  addu t1, t0, {lo_addr}

  j FinishCycleAndFetchOpcode
  sb {data}, 0 (t1)

+
  jr t0
  la_gp(ra, FinishCycleAndFetchOpcode)
}

addr_w_zp:
// Cycle 2: Fetch address, increment PC
  lbu cpu_t1, 0 (cpu_mpc)
  addi cpu_mpc, 1

// Cycle 3: Write
  daddi cycle_balance, cpu_div * 2
  j TestNextCycleAndFetchOpcode
  sb cpu_t0, nes_ram (cpu_t1)
 
macro addr_w_zxy(evaluate reg) {
// Cycle 2: Fetch address, increment PC
  lbu cpu_t1, 0 (cpu_mpc)
  addi cpu_mpc, 1

// Cycle 3: Read from unindexed address (no effect), add X/Y
  addu cpu_t1, {reg}
  andi cpu_t1, 0xff

// Cycle 4: Write

  daddi cycle_balance, cpu_div * 3
  j TestNextCycleAndFetchOpcode
  sb cpu_t0, nes_ram (cpu_t1)
}
addr_w_zx:
  addr_w_zxy(cpu_x)

addr_w_zy:
  addr_w_zxy(cpu_y)

addr_w_abs:
// Cycle 2: Fetch low address byte, increment PC
// Cycle 3: Fetch high address byte, increment PC
  addr_fetch_lh_imm(cpu_t1, cpu_t2)

// Cycle 4: Write
  write_abs_no_carry_and_finish(cpu_t0, cpu_t1, cpu_t2)

macro addr_w_absxy(evaluate reg) {
// Cycle 2: Fetch low address byte, increment PC
// Cycle 3: Fetch high address byte, increment PC
  addr_fetch_lh_imm(cpu_t1, cpu_t2)

// Cycle 4: Read from wrong effective address (TODO?)
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  add cpu_t1, {reg}

// Cycle 5: Write
  write_abs_carry_and_finish(cpu_t0, cpu_t1, cpu_t2)
}

addr_w_absx:
  addr_w_absxy(cpu_x)

addr_w_absy:
  addr_w_absxy(cpu_y)

addr_w_ix:
// Cycle 2: Fetch pointer address, increment PC
// Cycle 3: Read from address, add X
// Cycle 4: Fetch effective address low
// Cycle 5: Fetch effective address high
  addr_fetch_ix(cpu_t1, cpu_t2)

// Cycle 6: Write to effective address
  write_abs_no_carry_and_finish(cpu_t0, cpu_t1, cpu_t2)

addr_w_iy:
// Cycle 2: Fetch pointer address, increment PC
  addr_fetch_imm(cpu_t2)

// Cycle 3: Fetch effective address low (ZP)
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  lbu cpu_t1, nes_ram (cpu_t2)

// Cycle 4: Fetch effective address high (ZP), add Y to low
  addi cpu_t2, 1
  andi cpu_t2, 0xff
  lbu cpu_t2, nes_ram (cpu_t2)

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  add cpu_t1, cpu_y

// Cycle 5: Read from wrong effective address
  // TODO

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  nop

// Cycle 6: Write to effective address
  write_abs_carry_and_finish(cpu_t0, cpu_t1, cpu_t2)

// R execute
// These run on the last cycle of an opcode.
// Enter:
//   cpu_t1: value to operate on
// Exit:
//   j FinishCycleAndFetchOpcode

ex_ora:
  or cpu_acc, cpu_t1
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_and:
  and cpu_acc, cpu_t1
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_eor:
  xor cpu_acc, cpu_t1
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_bit:
  and t0, cpu_acc, cpu_t1
  sb t0, cpu_z_byte (r0)

  lbu t0, cpu_flags (r0)
  andi t1, cpu_t1, flagV
  andi t0, flagV^0xff
  or t0, t1
  sb t0, cpu_flags (r0)

// flagN is 0x80, this will make signed cpu_z_byte negative if set
  andi t0, cpu_t1, flagN
  j FinishCycleAndFetchOpcode
  sb t0, cpu_n_byte (r0)

scope ex_adc: {
constant flags(t0)
constant carry(t1)
constant overflow(t2)
  lbu carry, cpu_c_byte (r0)
  lbu flags, cpu_flags (r0)
  xor overflow, cpu_t1, cpu_acc
  addu cpu_acc, cpu_t1
  addu cpu_acc, carry

  srl carry, cpu_acc, 8
  sb carry, cpu_c_byte (r0)
  andi cpu_acc, 0xff

// overflooooow
  xori overflow, 0x80
  xor cpu_t1, cpu_acc
  and overflow, cpu_t1
  andi overflow, 0x80
  srl overflow, 1 // V = 0x40

  andi flags, flagV^0xff
  or flags, overflow
  sb flags, cpu_flags (r0)

  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)
}

scope ex_sbc: {
constant flags(t0)
constant borrow(t1)
constant overflow(t2)
constant result(t3)
  lbu borrow, cpu_c_byte (r0)
  lbu flags, cpu_flags (r0)
  xori borrow, flagC
  xor overflow, cpu_t1, cpu_acc
  subu result, cpu_acc, cpu_t1
  subu result, borrow

  move borrow, result
  slti borrow, 0
  xori borrow, 1
  sb borrow, cpu_c_byte (r0)

// overflooooow
  xor cpu_t1, result, cpu_acc
  and overflow, cpu_t1
  andi overflow, 0x80
  srl overflow, 1 // V = 0x40

  andi flags, flagV^0xff
  or flags, overflow
  sb flags, cpu_flags (r0)

  andi cpu_acc, result, 0xff

  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)
}

macro ex_cmp_axy(evaluate reg) {
  sub t1, {reg}, cpu_t1
  andi t0, t1, 0xff
  sb t0, cpu_n_byte (r0)
  sb t0, cpu_z_byte (r0)
  sltiu t1, 0x100
  j FinishCycleAndFetchOpcode
  sb t1, cpu_c_byte (r0)
}

ex_cmp:
ex_cmp_axy(cpu_acc)

ex_cpx:
ex_cmp_axy(cpu_x)

ex_cpy:
ex_cmp_axy(cpu_y)

ex_lda:
  move cpu_acc, cpu_t1
  sb cpu_t1, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_t1, cpu_z_byte (r0)

ex_ldx:
  move cpu_x, cpu_t1
  sb cpu_t1, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_t1, cpu_z_byte (r0)

ex_ldy:
  move cpu_y, cpu_t1
  sb cpu_t1, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_t1, cpu_z_byte (r0)

// RMW execute
// These will not yield or clobber cpu_t*
// Enter:
//   a0: value to operate on
//   ra: link back to addr mode
// Exit:
//   a0: new value
//   jr ra

ex_asl:
  srl t0, a0, 7
  sll a0, 1
  andi a0, 0xff
  sb t0, cpu_c_byte (r0)
  sb a0, cpu_n_byte (r0)
  jr ra
  sb a0, cpu_z_byte (r0)

ex_rol:
  lbu t0, cpu_c_byte (r0)
  sll a0, 1
  srl t1, a0, 8
  sb t1, cpu_c_byte (r0)
  andi a0, 0xff
  or a0, t0
  sb a0, cpu_n_byte (r0)
  jr ra
  sb a0, cpu_z_byte (r0)

ex_lsr:
  andi t0, a0, 1
  sb t0, cpu_c_byte (r0)
  srl a0, 1
  sb a0, cpu_n_byte (r0)
  jr ra
  sb a0, cpu_z_byte (r0)

ex_ror:
  lbu t0, cpu_c_byte (r0)
  andi t1, a0, 1
  sb t1, cpu_c_byte (r0)

  srl a0, 1
  sll t0, 7
  or a0, t0

  sb a0, cpu_n_byte (r0)
  jr ra
  sb a0, cpu_z_byte (r0)

ex_inc:
  addi a0, 1
  andi a0, 0xff
  sb a0, cpu_n_byte (r0)
  jr ra
  sb a0, cpu_z_byte (r0)

ex_dec:
  addi a0, -1
  andi a0, 0xff
  sb a0, cpu_n_byte (r0)
  jr ra
  sb a0, cpu_z_byte (r0)

// Accumulator operations

ex_asl_acc:
// cpu_t0: cpu_acc >> 7 (carry)
  sll cpu_acc, 1
  andi cpu_acc, 0xff
  sb cpu_t0, cpu_c_byte (r0)
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_rol_acc:
// cpu_t0: cpu_c_byte
  sll cpu_acc, 1
  or cpu_acc, cpu_t0
  srl t0, cpu_acc, 8
  sb t0, cpu_c_byte (r0)
  andi cpu_acc, 0xff
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_lsr_acc:
// cpu_t0: cpu_acc & 1 (carry)
  sb cpu_t0, cpu_c_byte (r0)
  srl cpu_acc, 1
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_ror_acc:
// cpu_t0: cpu_c_byte
  andi t0, cpu_acc, 1
  sb t0, cpu_c_byte (r0)

  srl cpu_acc, 1
  sll t1, cpu_t0, 7
  or cpu_acc, t1

  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

// Special operations

ex_php:
// cpu_t0: cpu_stack
// Cycle 2: Read next instruction (WONTFIX)
// Cycle 3: Push P, decrement S
  daddi cycle_balance, cpu_div

  get_flags(a0, t0, t1)
  ori a0, flagB
  sb a0, nes_ram + 0x100 (cpu_t0)
  addi cpu_t0, -1
  andi cpu_t0, 0xff

  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_stack (r0)

// clobbers t0 and t1, stack pointer is in cpu_t0
macro pull_flags() {
  lbu t0, nes_ram + 0x100 (cpu_t0)
// Delay slot?

// TODO as with ex_sei and ex_cli this should probably interface with the scheduler,
// unless we're always expecting interrupts?

  andi t1, t0, flagV|flagB|flagD|flagI
  ori t1, flag1
  sb t1, cpu_flags (r0)
  andi t1, t0, flagC
  sb t1, cpu_c_byte (r0)

  andi t1, t0, flagZ
  xori t1, flagZ
  sb t1, cpu_z_byte (r0)

// flagN is 0x80, this will make signed cpu_z_byte negative if set
  andi t1, t0, flagN
  sb t1, cpu_n_byte (r0)
}

ex_plp:
// cpu_t0: cpu_stack

// Cycle 2: Read next instruction (WONTFIX)
// Cycle 3: Increment S
  addi cpu_t0, 1
  andi cpu_t0, 0xff

  daddi cycle_balance, cpu_div * 2
// Cycle 4: Pull P

  pull_flags()
  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_stack (r0)

ex_pha:
// cpu_t0: cpu_stack

// Cycle 2: Read next instruction (WONTFIX)
// Cycle 3: Push A, decrement S
  daddi cycle_balance, cpu_div

  sb cpu_acc, nes_ram + 0x100 (cpu_t0)
  addi cpu_t0, -1
  andi cpu_t0, 0xff

  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_stack (r0)

ex_pla:
// cpu_t0: cpu_stack

// Cycle 2: Read next instruction (WONTFIX)
// Cycle 3: Increment S
// Cycle 4: Pull A
  daddi cycle_balance, cpu_div * 2

  addi cpu_t0, 1
  andi cpu_t0, 0xff

  lbu cpu_acc, nes_ram + 0x100 (cpu_t0)
  sb cpu_t0, cpu_stack (r0)

  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_rti:
// cpu_t0: cpu_stack

// Cycle 2: Read next instruction (WONTFIX)
// Cycle 3: Increment S
  addi cpu_t0, 1
  andi cpu_t0, 0xff

// Cycle 4: Pull flags, increment S
  pull_flags()
  addi cpu_t0, 1
  andi cpu_t0, 0xff

// Cycle 5: Pull low PC, increment S
  lbu cpu_t1, nes_ram + 0x100 (cpu_t0)
  addi cpu_t0, 1
  andi cpu_t0, 0xff

// Cycle 6: Pull high PC
  lbu cpu_t2, nes_ram + 0x100 (cpu_t0)
  sb cpu_t0, cpu_stack (r0)

  sll t0, cpu_t2, 2
  lw cpu_mpc, cpu_read_map (t0)
  sll t0, 8-2
  or cpu_t1, t0
  sw cpu_mpc, cpu_mpc_base (r0)

  addu cpu_mpc, cpu_t1

  j TestNextCycleAndFetchOpcode
  daddi cycle_balance, cpu_div * 5

ex_rts:
// cpu_t0: cpu_stack

// Cycle 2: Read next instruction (WONTFIX)
// Cycle 3: Increment S
  addi cpu_t0, 1
  andi cpu_t0, 0xff
// Cycle 4: Pull low PC, increment S
  lbu cpu_t1, nes_ram + 0x100 (cpu_t0)
  addi cpu_t0, 1
  andi cpu_t0, 0xff
// Cycle 5: Pull high PC
  lbu cpu_t2, nes_ram + 0x100 (cpu_t0)
  sb cpu_t0, cpu_stack (r0)

// Cycle 6: Increment PC
  addi cpu_t1, 1
  sll cpu_t2, 8
  add cpu_t2, cpu_t1
  andi cpu_t2, 0xffff
  srl t0, cpu_t2, 8
  sll t0, 2
  lw cpu_mpc, cpu_read_map (t0)
  daddi cycle_balance, cpu_div * 4
  sw cpu_mpc, cpu_mpc_base (r0)

  j FinishCycleAndFetchOpcode
  add cpu_mpc, cpu_t2

ex_jsr:
// cpu_t0: low byte of address

// Cycle 2: Fetch low address byte, increment PC
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addi cpu_mpc, 1

// Cycle 3: ??
// I'll take this an opportunity to recover the PC from cpu_mpc
  lw t0, cpu_mpc_base (r0)
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  subu cpu_t1, cpu_mpc, t0

// Cycle 4: Push high PC on stack, decrement S
  lbu cpu_t2, cpu_stack (r0)
  srl t0, cpu_t1, 8
  sb t0, nes_ram + 0x100 (cpu_t2)
  addi cpu_t2, -1

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  andi cpu_t2, 0xff

// Cycle 5: Push low PC on stack, decrement S
  sb cpu_t1, nes_ram + 0x100 (cpu_t2)
  addi cpu_t2, -1

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  sb cpu_t2, cpu_stack (r0)

// Cycle 6: Fetch high address byte, set PC
  lbu t0, 0 (cpu_mpc)
  set_pc_and_finish(cpu_t0, t0)

// TAY/TAX/TYA/TXA
ex_transfer_acc:
// The transfer has already been done, in all cases A has the transferred value
// Cycle 2, set flags
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

ex_tsx:
// The transfer is already done.
  sb cpu_x, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_x, cpu_z_byte (r0)

ex_inx_dex:
// The inc/dec has already been done, but hasn't been masked yet
// Cycle 2, set flags
  andi cpu_x, 0xff
  sb cpu_x, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_x, cpu_z_byte (r0)

// The inc/dec has already been done, but hasn't been masked yet
ex_iny_dey:
// Cycle 2, set flags
  andi cpu_y, 0xff
  sb cpu_y, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_y, cpu_z_byte (r0)

ex_jmp_abs:
// cpu_t0: low address byte
// Cycle 2, fetch low address byte, increment PC

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addi cpu_mpc, 1

// Cycle 3, fetch high address byte, set PC
// use load delay slot?
  lbu cpu_t1, 0 (cpu_mpc)
  set_pc_and_finish(cpu_t0, cpu_t1)

ex_jmp_absi:
// cpu_t0: low address byte
// Cycle 2, fetch low address, increment PC

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  addi cpu_mpc, 1

// Cycle 3, fetch high address byte
  lbu cpu_t1, 0(cpu_mpc)

  daddi cycle_balance, cpu_div

// Cycle 4, fetch low address
  daddi cycle_balance, cpu_div
// Cycle 5, fetch high address
// Not supporting I/O here
  sll cpu_t1, 2
  lw cpu_t2, cpu_read_map (cpu_t1)
  sll cpu_t1, 8-2
  or t0, cpu_t0, cpu_t1
  addu t0, cpu_t2

// No need to re-map as jmp indirect doesn't cross pages
  addi cpu_t0, 1
  andi cpu_t0, 0xff
  or t1, cpu_t0, cpu_t1
  addu t1, cpu_t2
  lbu cpu_t1, 0(t1)
  lbu cpu_t0, 0(t0)

  set_pc_and_finish(cpu_t0, cpu_t1)

ex_bmi:
// cpu_t0: cpu_n_byte, signed
// Delay slot?
  bgez cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_bpl:
// cpu_t0: cpu_n_byte, signed
// Delay slot?
  bltz cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_bcs:
// cpu_t0: cpu_c_byte
// Delay slot?
  beqz cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_beq:
// cpu_t0: cpu_z_byte
// Delay slot?
  bnez cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_bcc:
// cpu_t0: cpu_c_byte
// Delay slot?
  bnez cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_bne:
// cpu_t0: cpu_z_byte
// Delay slot?
  beqz cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_bvs:
// cpu_t0: cpu_flags
  andi cpu_t0, flagV
  beqz cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_bvc:
// cpu_t0: cpu_flags
  andi cpu_t0, flagV
  bnez cpu_t0, FinishCycleAndFetchOpcode
  addi cpu_mpc, 1
  j ex_taken_branch
  lb cpu_t0, -1 (cpu_mpc)

ex_taken_branch:
// cpu_t0: offset (signed)
// Cycle 2: Fetch offset (already done), increment PC (already done)
// Cycle 3: Fetch opcode of next instr (WONTFIX), add offset to low PC
  lw t0, cpu_mpc_base (r0)
  daddi cycle_balance, cpu_div * 2
  bgezal cycle_balance, Scheduler.YieldFromCPU
  subu cpu_t1, cpu_mpc, t0

  addu cpu_t2, cpu_t1, cpu_t0
  andi cpu_t2, 0xffff
// If we're still on the same page, no need to remap PC
  xor cpu_t1, cpu_t2
  andi t0, cpu_t1, 0xff00
  beqz t0, FetchOpcode
  addu cpu_mpc, cpu_t0

// Cycle 4: Fetch opcode of wrong next inst (WONTFIX), fix PCH
// TODO: There's probably no need to remap the PC here, either

  andi cpu_t1, cpu_t2, 0xff00

  srl cpu_t1, 8-2
  lw t0, cpu_read_map (cpu_t1)
// inc here and use TestNextCycleAndFetchOpcode to fill load delay slot
  daddi cycle_balance, cpu_div
  addu cpu_mpc, t0, cpu_t2

  j TestNextCycleAndFetchOpcode
  sw t0, cpu_mpc_base (r0)

ex_sec:
// cpu_t0: 1
  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_c_byte (r0)

ex_cli:
// cpu_t0: cpu_flags
// TODO: This should interface with the scheduler?
// load delay slot?
  andi cpu_t0, flagI^0xff
  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_flags (r0)

ex_sei:
// cpu_t0: cpu_flags
// TODO: This should interface with the scheduler?
// load delay slot?
  ori cpu_t0, flagI
  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_flags (r0)

ex_cld:
// cpu_t0: cpu_flags
// load delay slot?
  andi cpu_t0, flagD^0xff
  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_flags (r0)

ex_sed:
// cpu_t0: cpu_flags
// load delay slot?
  ori cpu_t0, flagD
  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_flags (r0)

ex_clv:
// cpu_t0: cpu_flags
// load delay slot?
  andi cpu_t0, flagV^0xff
  j FinishCycleAndFetchOpcode
  sb cpu_t0, cpu_flags (r0)

if {defined UNOFFICIAL_OPCODES} {
// Unofficial ops
// Most of these are based on the FCEUX implementation and
// tested against blargg's instr_test-v5.

// Addressing modes
addr_rw_absy:
  addr_fetch_lh_imm(cpu_t1, cpu_t2)
  j addr_rw_absx.cycle4
  addu t1, cpu_t1, cpu_y

addr_rw_ix:
// Cycle 2: Fetch pointer address, increment PC
// Cycle 3: Read from address, add X
// Cycle 4: Fetch effective address low
// Cycle 5: Fetch effective address high
  addr_fetch_ix(cpu_t1, cpu_t2)

// Cycle 6: Read from effective address
  sll cpu_t2, 2
  lw t0, cpu_read_map (cpu_t2)
  sll cpu_t2, 8-2
  or cpu_t1, cpu_t2
  move cpu_t2, cpu_t1

  bgez t0,+
  add t1, t0, cpu_t1

// TODO implement for read/write handlers
  syscall 1
+
  lbu cpu_t1, 0 (t1)

// Cycle 7: Write the value back to effective address (TODO),
// do the operation

// Execute
  jalr cpu_t0
  move a0, cpu_t1

  daddi cycle_balance, cpu_div * 2
  bgezal cycle_balance, Scheduler.YieldFromCPU
  move cpu_t0, a0

// Cycle 8: Write the new value
  move cpu_t1, cpu_t2

  andi t1, cpu_t1, 0xff00
  srl t1, 8-2
  lw t0, cpu_write_map (t1)

  bgez t0,+
  add t1, t0, cpu_t1

// TODO implement for read/write handlers
  syscall 1
+
  j FinishCycleAndFetchOpcode
  sb cpu_t0, 0 (t1)

addr_rw_iy:
// Cycle 2: Fetch pointer address, increment PC
  addr_fetch_imm(cpu_t2)

// Cycle 3: Fetch effective address low (ZP)
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  lbu cpu_t1, nes_ram (cpu_t2)

// Cycle 4: Fetch effective address high (ZP), add Y to low
  addi cpu_t2, 1
  andi cpu_t2, 0xff
  lbu cpu_t2, nes_ram (cpu_t2)

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  add cpu_t1, cpu_y

// Cycle 5: Read from wrong effective address (TODO)
  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  nop

// Cycle 6: Read from effective address
  sll cpu_t2, 8
  add cpu_t2, cpu_t1
  andi cpu_t2, 0xffff
  andi t2, cpu_t2, 0xff00
  srl t2, 8-2

  lw t0, cpu_read_map (t2)

  bgez t0,+
  add t1, t0, cpu_t2

// TODO implement for read/write handlers
  syscall 1
+
  lbu cpu_t1, 0 (t1)

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  nop

// Cycle 7: Write back (TODO), execute
  jalr cpu_t0
  move a0, cpu_t1

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  move cpu_t0, a0

// Cycle 8: Write new value
  move cpu_t1, cpu_t2

  andi t1, cpu_t1, 0xff00
  srl t1, 8-2
  lw t0, cpu_write_map (t1)

  bgez t0,+
  add t1, t0, cpu_t1

// TODO implement for read/write handlers
  syscall 1
+
  j FinishCycleAndFetchOpcode
  sb cpu_t0, 0 (t1)

// SHY aka SYA
// SHX aka SXA
addr_w_shxy:
// Cycle 2: Fetch low address byte, increment PC
// Cycle 3: Fetch high address byte, increment PC
  addr_fetch_lh_imm(cpu_t1, cpu_t2)

// Cycle 4: Read from wrong effective address (TODO?)
// cpu_t0 has X or Y to use for the AND. XOR swap to the other one.
  xor t0, cpu_x, cpu_y
  xor t0, cpu_t0

  sll cpu_t2, 8
  add cpu_t1, cpu_t2
  add cpu_t1, t0

  daddi cycle_balance, cpu_div
  bgezal cycle_balance, Scheduler.YieldFromCPU
  andi cpu_t1, 0xffff // not needed?

// Cycle 5: Write
  srl t0, cpu_t1, 8
  addi t0, 1
  and cpu_t0, t0
  andi cpu_t1, 0xff
  move cpu_t2, cpu_t0

  write_abs_no_carry_and_finish(cpu_t0, cpu_t1, cpu_t2)

// R execute
// ANC aka AAC
ex_anc:
  and cpu_acc, cpu_t1
  srl t0, cpu_acc, 7
  sb t0, cpu_c_byte (r0)
finish_acc_r:
  sb cpu_acc, cpu_n_byte (r0)
  j FinishCycleAndFetchOpcode
  sb cpu_acc, cpu_z_byte (r0)

// ALR aka ASR
ex_alr:
  and cpu_acc, cpu_t1
  j ex_lsr_acc
  andi cpu_t0, cpu_acc, 1

// TODO shorten?
ex_arr:
  and cpu_acc, cpu_t1

  lbu t3, cpu_c_byte (r0)
  srl t0, cpu_acc, 7
  sb t0, cpu_c_byte (r0)
  srl t0, cpu_acc, 1
  sll t3, 7

  lbu t1, cpu_flags (r0)
  andi t1, flagV^0xff
  xor t2, t0, cpu_acc
  andi t2, flagV
  or t1, t2
  sb t1, cpu_flags (r0)

  j finish_acc_r
  or cpu_acc, t0, t3

ex_lax:
  j ex_ldx
  move cpu_acc, cpu_t1

ex_axs:
  and cpu_x, cpu_acc
  sub cpu_x, cpu_t1
  sb cpu_x, cpu_n_byte (r0)
  sb cpu_x, cpu_z_byte (r0)
  sltiu t0, cpu_x, 0x100
  sb t0, cpu_c_byte (r0)
  j FinishCycleAndFetchOpcode
  andi cpu_x, 0xff

ex_xaa:
  j finish_acc_r
  andi cpu_acc, cpu_x, cpu_t1

// LAS aka LAR
ex_las:
// TODO untested besides timing
  and cpu_stack, cpu_t1
  move cpu_x, cpu_stack
  j finish_acc_r
  move cpu_acc, cpu_stack

// RMW execute
ex_slo:
  srl t0, a0, 7
  sb t0, cpu_c_byte (r0)
  sll a0, 1

  or cpu_acc, a0
finish_acc_rw:
  sb cpu_acc, cpu_n_byte (r0)
  jr ra
  sb cpu_acc, cpu_z_byte (r0)

ex_rla:
  lbu t0, cpu_c_byte (r0)
  sll a0, 1
  or a0, t0
  srl t0, a0, 8
  sb t0, cpu_c_byte (r0)

  j finish_acc_rw
  and cpu_acc, a0

ex_sre:
  andi t0, a0, 1
  srl a0, 1
  sb t0, cpu_c_byte (r0)

  j finish_acc_rw
  xor cpu_acc, a0

// TODO I hate to use all this space on RRA,
// but it's not natural to combine it with ADC since it needs to
// return through the addressing mode's write handler.
scope ex_rra: {
constant flags(t0)
constant carry(t1)
constant overflow(t2)

  lbu t0, cpu_c_byte (r0)
  andi carry, a0, 1
  srl a0, 1
  sll t0, 7
  or a0, t0

  lbu flags, cpu_flags (r0)
  xor overflow, a0, cpu_acc
  addu cpu_acc, a0
  addu cpu_acc, carry

  srl carry, cpu_acc, 8
  sb carry, cpu_c_byte (r0)
  andi cpu_acc, 0xff

// overflooooow
  xori overflow, 0x80
  xor t3, a0, cpu_acc
  and overflow, t3
  andi overflow, 0x80
  srl overflow, 1 // V = 0x40

  andi flags, flagV^0xff
  or flags, overflow
  sb flags, cpu_flags (r0)

  sb cpu_acc, cpu_n_byte (r0)
  jr ra
  sb cpu_acc, cpu_z_byte (r0)
}


// ISC aka ISB
// TODO shrinkme
scope ex_isc: {
constant flags(t0)
constant borrow(t1)
constant overflow(t2)
constant result(t3)
  addi a0, 1
  andi a0, 0xff

  lbu borrow, cpu_c_byte (r0)
  lbu flags, cpu_flags (r0)
  xori borrow, flagC
  xor overflow, a0, cpu_acc
  subu result, cpu_acc, a0
  subu result, borrow

  move borrow, result
  slti borrow, 0
  xori borrow, 1
  sb borrow, cpu_c_byte (r0)

// overflooooow
// reusing borrow for temp here
  xor borrow, result, cpu_acc
  and overflow, borrow
  andi overflow, 0x80
  srl overflow, 1 // V = 0x40

  andi flags, flagV^0xff
  or flags, overflow
  sb flags, cpu_flags (r0)

  andi cpu_acc, result, 0xff

  sb cpu_acc, cpu_n_byte (r0)
  jr ra
  sb cpu_acc, cpu_z_byte (r0)
}

ex_dcp:
  addi a0, -1
  andi a0, 0xff

  sub t1, cpu_acc, a0
  andi t0, t1, 0xff

  sb t0, cpu_n_byte (r0)
  sb t0, cpu_z_byte (r0)
  sltiu t1, 0x100
  jr ra
  sb t1, cpu_c_byte (r0)

// W execute
// These don't interface with the write addressing modes in the normal way

// AHX aka SHA aka AXA
ex_ahx_iy:
// TODO, only implemented for a timing test
  addiu cpu_mpc, 1
  j TestNextCycleAndFetchOpcode
  daddiu cycle_balance, cpu_div * 5

ex_ahx_absy:
// TAS aka SHS
ex_tas:
// TODO, only implemented for a timing test
  addiu cpu_mpc, 2
  j TestNextCycleAndFetchOpcode
  daddiu cycle_balance, cpu_div * 4
}

print "CPU kernel is ", pc() - FinishCycleAndFetchOpcode, " bytes \n"

// ****** Cold data

// TODO: this should be discarded after CPU is set up, if icache is an issue
// NOTE: Does not set PC, to do that properly requires something mapped to the
// reset vector.
scope InitCPU: {
  sw ra, 0(sp)
  addi sp, 8

// Set up TLB page for RAM
  jal TLB.AllocateVaddr
  lli a0, 0x2000  // align 8K (leaving room for unmapped guard page)

// Map RAM (0-0x800, mirrored 0x800-0x2000)
  lli t0, 0
  addi t1, a0, 0x800
  lli t2, 8

-;sw t1, cpu_read_map (t0)
  sw t1, cpu_write_map (t0)

  addi t3, t1, -0x800
  sw t3, cpu_read_map + 0x8 * 4 (t0)
  sw t3, cpu_write_map + 0x8 * 4 (t0)

  addi t3, -0x800
  sw t3, cpu_read_map + 0x10 * 4 (t0)
  sw t3, cpu_write_map + 0x10 * 4 (t0)

  addi t3, -0x800
  sw t3, cpu_read_map + 0x18 * 4 (t0)
  sw t3, cpu_write_map + 0x18 * 4 (t0)

  addi t2, -1
  bnez t2,-
  addi t0, 4

  if (nes_ram - low_page_base + low_page_ram_base - 0x800) & 0xfff != 0 {
    error "nes_ram-0x800 must be 4K aligned"
  }
  mtc0 a1, Index
  la a1, (nes_ram - low_page_base + low_page_ram_base - 0x800)
  jal TLB.Map4K
  nop

// Map PPU regs (0x2000-0x4000)
  lli t0, 0x20 * 4
  la_gp(t1, ppu_read_handler)
  la_gp(t2, ppu_write_handler)
  lli t3, 0x20

-;sw t1, cpu_read_map (t0)
  sw t2, cpu_write_map (t0)
  addi t3, -1
  bnez t3,-
  addi t0, 4

// Map other I/O (0x4000-0x6000)
  lli t0, 0x40 * 4
  la t1, io_read_handler
  la t2, io_write_handler
  li t3, 0x20

-;sw t1, cpu_read_map (t0)
  sw t2, cpu_write_map (t0)
  addi t3, -1
  bnez t3,-
  addi t0, 4

// Set up TLB page for cart RAM
  jal TLB.AllocateVaddr
  lli a0, 0x4000  // align 16K (leaving room for unmapped guard page)

// Map cart RAM (0x6000-0x8000)
  lli t0, 0x60 * 4
  lli t3, 0x20
  addi t1, a0, -0x6000

-;sw t1, cpu_read_map (t0)
  sw t1, cpu_write_map (t0)

  addi t3, -1
  bnez t3,-
  addi t0, 4

  la a1, nes_extra_ram & 0x1fff'ffff
  jal TLB.Map8K
  nop

// Trap unmapped ROM (0x8000-0x10000)
  lli t0, 0x80 * 4
  la t1, bad_read_handler
  la t2, bad_write_handler
  li t3, 0x80

-;sw t1, cpu_read_map (t0)
  sw t2, cpu_write_map (t0)
  addi t3, -1
  bnez t3,-
  addi t0, 4

// Clear RAM
// TODO: consider randomizing
  lli t0, nes_ram
  lli t1, 0x800
  addi t2, r0, -1
-;sd t2, 0(t0)
  addi t1, -8
  bnez t1,-
  addi t0, 8

// Initialize registers
  move cpu_acc, r0
  move cpu_x, r0
  move cpu_y, r0
  lli t0, 0xff
  sb t0, cpu_stack (r0)
  lli t0, flag1 | flagI
  sb t0, cpu_flags (r0)
  sb r0, cpu_n_byte (r0)
  sb r0, cpu_z_byte (r0)
  sb r0, cpu_c_byte (r0)

  sh r0, interrupt_pending(r0)

// Begin running task

  move a0, r0
  la_gp(a1, FetchOpcode)
  jal Scheduler.ScheduleTaskFromNow
  lli a2, cpu_inst_task

  lw ra, -8(sp)
  jr ra
  addi sp, -8
}

ResetCPU:
// TODO: there may need to be some mapper banking reset stuff here
// TODO: This really takes several cycles (6)
  lw t0, cpu_read_map + 0xff * 4 (r0)
  li t1, 0xfffc
  addu t0, t1
  lbu a0, 0(t0)

  j SetPC
  lbu a1, 1(t0)

macro take_interrupt(vector, setI, setB) {
// TODO may need to interface with scheduler?
// Cycle 1, 2: ??
// Cycle 3: Push high PC, decrement S

  lw t0, cpu_mpc_base (r0)
  addi cpu_t0, -1
  subu t0, cpu_mpc, t0

  srl t2, t0, 8

  sb t2, nes_ram + 0x100 + 1 (cpu_t0)
  andi cpu_t0, 0xff

// Cycle 4: Push low PC, decrement S
  sb t0, nes_ram + 0x100 (cpu_t0)

  addi cpu_t0, -1
  andi cpu_t0, 0xff
// Cycle 5: Push flags, decrement S
  lbu t0, cpu_c_byte (r0)
  lbu t2, cpu_flags (r0)
  lbu t1, cpu_z_byte (r0)
  or t0, t2
  bnez t1,+
  lb t1, cpu_n_byte (r0)
  ori t0, flagZ
+

if {setI} == 1 {
  ori t2, flagI
}

  bgez t1,+
  sb t2, cpu_flags (r0)
  ori t0, flagN
+

if {setB} == 1 {
  ori t0, flagB
}

  sb t0, nes_ram + 0x100 (cpu_t0)

  addi cpu_t0, -1
  andi cpu_t0, 0xff
  sb cpu_t0, cpu_stack (r0)
  
// Cycle 6, 7: Fetch PC from vector
  lw t0, cpu_read_map + 0xff * 4 (r0)
  lli t1, {vector}
  addu t0, t1
  lbu a0, 0(t0)
  lbu a1, 1(t0)

  j SetPC
  la_gp(ra, TestNextCycleAndFetchOpcode)
}

// TODO these shouldn't be with the cold data
TakeBRK:
  daddi cycle_balance, cpu_div * 6
  addi cpu_mpc, 1

  take_interrupt(0xfffe, 1, 1)

TakeInt:
  lbu t0, nmi_pending (r0)
  lb t1, irq_pending (r0)
  lbu t2, cpu_flags (r0)

  beqz t0,+
// Decrement nmi_pending to delay by one instruction also clear once NMI
// is taken.
  subiu t0, 1
  beqz t0, TakeNMI
  sb t0, nmi_pending (r0)

+
  andi t2, flagI

  beqz t2,+
  andi t3, t1, 0x7f
// Interrupt is currently masked
  j dont_take_int
  sb t3, irq_pending (r0)
+

  bnez t3,+
  nop
// There wasn't anything left pending, clear intDelayed
  j dont_take_int
  sb r0, irq_pending (r0)
+

  bltz t1, TakeIRQ
// Set flag to interrupt next instr
  ori t1, 0x80
  j dont_take_int
  sb t1, irq_pending (r0)

TakeIRQ:
if {defined LOG_CPU} || {defined LOG_IRQ} {
  jal PrintStr0
  la_gp(a0, irq_msg)

  jal PrintCPUInfo
  nop

  jal NewlineAndFlushDebug
  nop
}
  lbu cpu_t0, cpu_stack (r0)
  daddi cycle_balance, cpu_div * 7

  take_interrupt(0xfffe, 1, 0)

TakeNMI:
if {defined LOG_CPU} || {defined LOG_IRQ} {
  jal PrintStr0
  la_gp(a0, nmi_msg)

  jal PrintCPUInfo
  nop

  jal NewlineAndFlushDebug
  nop
}
  lbu cpu_t0, cpu_stack (r0)

  daddi cycle_balance, cpu_div * 7

  take_interrupt(0xfffa, 1, 0)


// cpu_t0 = opcode
handle_bad_opcode:
//DEBUG
  jal PrintStr0
  la_gp(a0, bad_opcode_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintCPUInfo
  addi cpu_mpc, -1
  addi cpu_mpc, 1

  j DisplayDebugAndHalt
  nop

bad_read_handler:
// cpu_t1: address

  jal PrintStr0
  la_gp(a0, bad_read_msg)

  move a0, cpu_t1
  jal  PrintHex
  lli a1, 4

  jal PrintCPUInfo
  nop

  j DisplayDebugAndHalt
  nop

bad_write_handler:
// cpu_t0: data
// cpu_t1: address
if {defined TRAP_BAD_WRITE} {
  jal PrintStr0
  la_gp(a0, bad_write_msg)

  move a0, cpu_t1
  jal PrintHex
  lli a1, 4

  jal PrintStr0
  la_gp(a0, val_msg)

  move a0, cpu_t0
  jal PrintHex
  lli a1, 2

  jal PrintCPUInfo
  nop

  j DisplayDebugAndHalt
  nop
} else {
  jr ra
  nop
}

PrintCPUInfo:
  addi sp, 8
  sw ra, -8(sp)

  jal PrintStr0
  la_gp(a0, at_pc_msg)

  get_pc(a0)
  jal PrintHex
  lli a1, 4

  jal PrintStr0
  la_gp(a0, flags_val_msg)

  get_flags(a0, t0, t1)
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, a_val_msg)

  move a0, cpu_acc
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, x_val_msg)

  move a0, cpu_x
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, y_val_msg)

  move a0, cpu_y
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, stack_val_msg)

  lbu a0, cpu_stack (r0)
  jal PrintHex
  lli a1, 2

  jal PrintStr0
  la_gp(a0, cycle_msg)

  ld a0, target_cycle (r0)
  jal PrintDec
  daddu a0, cycle_balance

  lw ra, -8(sp)
  jr ra
  addi sp, -8

bad_opcode_msg:
  db "Bad opcode: ",0
at_pc_msg:
  db " at PC=",0
a_val_msg:
  db ", A=",0
x_val_msg:
  db ", X=",0
y_val_msg:
  db ", Y=",0
flags_val_msg:
  db ", P=",0
stack_val_msg:
  db ", S=",0
cycle_msg:
  db ", cycle=",0
val_msg:
  db ", val=",0
nmi_msg:
  db "NMI",0
irq_msg:
  db "IRQ",0

bad_read_msg:
  db "Bad read from ",0
bad_write_msg:
  db "Bad write to ",0

align(4)
