// Ref opcodes:
// http://www.6502.org/tutorials/6502opcodes.html
// http://www.oxyron.de/html/opcodes02.html
// https://www.nesdev.org/6502_cpu.txt

macro check_index(evaluate code) {
  if pc() - opcode_table != {code} * 8 {
    error "Table out of sync"
  }
}

macro read_op(evaluate code, _name, op1, op2) {
  check_index({code})
  j {op1}
  la_gp(cpu_t0, {op2})
}

macro write_op(evaluate code, _name, addr_mode, reg) {
  check_index({code})
  j {addr_mode}
  move cpu_t0, {reg}
}

macro stack_op(evaluate code, _name, op) {
  check_index({code})
  j {op}
  lbu cpu_t0, cpu_stack (r0)
}

// TODO: see if I can find a way to make use of this wasted space
macro bad_op(evaluate code) {
  check_index({code})
  j handle_bad_opcode
  lli cpu_t0, {code}
}

// Unofficial opcode wrappers, enabled only with UNOFFICIAL_OPCODES defined.
macro read_unop(code, _name, op1, op2) {
if {defined UNOFFICIAL_OPCODES} {
read_op({code}, {_name}, {op1}, {op2})
} else {
bad_op({code})
}
}

macro un_noop(code) {
if {defined UNOFFICIAL_OPCODES} {
check_index({code})
  j ex_nop
  nop
} else {
bad_op({code})
}
}

// Note: For ops that don't use the normal addressing modes,
// or for Stores (write_op), I try to include some of the
// work in the delay slot of the jump to the ex_*, usually
// loading something into cpu_t0.

opcode_table:
stack_op( 0x00, "BRK",                    TakeBRK)
read_op(  0x01, "ORA iX",   addr_r_ix,    ex_ora)
bad_op(   0x02)
read_unop(0x03, "SLO iX",   addr_rw_ix,   ex_slo)
read_unop(0x04, "NOP ZP",   addr_r_zp,    ex_nop)
read_op(  0x05, "ORA ZP",   addr_r_zp,    ex_ora)
read_op(  0x06, "ASL ZP",   addr_rw_zp,   ex_asl)
read_unop(0x07, "SLO ZP",   addr_rw_zp,   ex_slo)
stack_op( 0x08, "PHP",                    ex_php)
read_op(  0x09, "ORA imm",  addr_r_imm,   ex_ora)
// 0x0a: ASL acc
  j ex_asl_acc
  srl cpu_t0, cpu_acc, 7
read_unop(0x0b, "ANC imm",  addr_r_imm,   ex_anc)
read_unop(0x0c, "NOP abs",  addr_r_abs,   ex_nop)
read_op(  0x0d, "ORA abs",  addr_r_abs,   ex_ora)
read_op(  0x0e, "ASL abs",  addr_rw_abs,  ex_asl)
read_unop(0x0f, "SLO abs",  addr_rw_abs,  ex_slo)
// 0x10: BPL
  j ex_bpl
  lb cpu_t0, cpu_n_byte (r0)
read_op(  0x11, "ORA iY",   addr_r_iy,    ex_ora)
bad_op(   0x12)
read_unop(0x13, "SLO iY",   addr_rw_iy,   ex_slo)
read_unop(0x14, "NOP ZX",   addr_r_zx,    ex_nop)
read_op(  0x15, "ORA ZX",   addr_r_zx,    ex_ora)
read_op(  0x16, "ASL ZX",   addr_rw_zx,   ex_asl)
read_unop(0x17, "SLO ZX",   addr_rw_zx,   ex_slo)
// 0x18: CLC
  j FinishCycleAndFetchOpcode
  sb r0, cpu_c_byte (r0)
read_op(  0x19, "ORA absY", addr_r_absy,  ex_ora)
un_noop(  0x1a)
read_unop(0x1b, "SLO absY", addr_rw_absy, ex_slo)
read_unop(0x1c, "NOP absX", addr_r_absx,  ex_nop)
read_op(  0x1d, "ORA absX", addr_r_absx,  ex_ora)
read_op(  0x1e, "ASL absX", addr_rw_absx, ex_asl)
read_unop(0x1f, "SLO absX", addr_rw_absx, ex_slo)

// 0x20: JSR
  j ex_jsr
  lbu cpu_t0, 0 (cpu_mpc)
read_op(  0x21, "AND iX",   addr_r_ix,    ex_and)
bad_op(   0x22)
read_unop(0x23, "RLA iX",   addr_rw_ix,   ex_rla)
read_op(  0x24, "BIT ZP",   addr_r_zp,    ex_bit)
read_op(  0x25, "AND ZP",   addr_r_zp,    ex_and)
read_op(  0x26, "ROL ZP",   addr_rw_zp,   ex_rol)
read_unop(0x27, "RLA ZP",   addr_rw_zp,   ex_rla)
stack_op( 0x28, "PLP",                    ex_plp)
read_op(  0x29, "AND imm",  addr_r_imm,   ex_and)
// 0x2a: ROL acc
  j ex_rol_acc
  lbu cpu_t0, cpu_c_byte (r0)
read_unop(0x2b, "ANC imm",  addr_r_imm,   ex_anc)
read_op(  0x2c, "BIT abs",  addr_r_abs,   ex_bit)
read_op(  0x2d, "AND abs",  addr_r_abs,   ex_and)
read_op(  0x2e, "ROL abs",  addr_rw_abs,  ex_rol)
read_unop(0x2f, "RLA abs",  addr_rw_abs,  ex_rla)

// 0x30: BMI
  j ex_bmi
  lb cpu_t0, cpu_n_byte (r0)
read_op(  0x31, "AND iY",   addr_r_iy,    ex_and)
bad_op(   0x32)
read_unop(0x33, "RLA iY",   addr_rw_iy,   ex_rla)
read_unop(0x34, "NOP ZX",   addr_r_zx,    ex_nop)
read_op(  0x35, "AND ZX",   addr_r_zx,    ex_and)
read_op(  0x36, "ROL ZX",   addr_rw_zx,   ex_rol)
read_unop(0x37, "RLA ZX",   addr_rw_zx,   ex_rla)
// 0x38: SEC
  j ex_sec
  lli cpu_t0, 1
read_op(  0x39, "AND absY", addr_r_absy,  ex_and)
un_noop(  0x3a)
read_unop(0x3b, "RLA absY", addr_rw_absy, ex_rla)
read_unop(0x3c, "NOP absX", addr_r_absx,  ex_nop)
read_op(  0x3d, "AND absX", addr_r_absx,  ex_and)
read_op(  0x3e, "ROL absX", addr_rw_absx, ex_rol)
read_unop(0x3f, "RLA absX", addr_rw_absx, ex_rla)

stack_op( 0x40, "RTI",                    ex_rti)
read_op(  0x41, "EOR iX",   addr_r_ix,    ex_eor)
bad_op(   0x42)
read_unop(0x43, "SRE iX",   addr_rw_ix,   ex_sre)
read_unop(0x44, "NOP ZP",   addr_r_zp,    ex_nop)
read_op(  0x45, "EOR ZP",   addr_r_zp,    ex_eor)
read_op(  0x46, "LSR ZP",   addr_rw_zp,   ex_lsr)
read_unop(0x47, "SRE ZP",   addr_rw_zp,   ex_sre)
stack_op( 0x48, "PHA",                    ex_pha)
read_op(  0x49, "EOR imm",  addr_r_imm,   ex_eor)
// 0x4a: LSR acc
  j ex_lsr_acc
  andi cpu_t0, cpu_acc, 1
read_unop(0x4b, "ALR imm",  addr_r_imm,   ex_alr)
// 0x4c: JMP abs
  j ex_jmp_abs
  lbu cpu_t0, 0 (cpu_mpc)
read_op(  0x4d, "EOR abs",  addr_r_abs,   ex_eor)
read_op(  0x4e, "LSR abs",  addr_rw_abs,  ex_lsr)
read_unop(0x4f, "SRE abs",  addr_rw_abs,  ex_sre)

// 0x50: BVC
  j ex_bvc
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x51, "EOR iY",   addr_r_iy,    ex_eor)
bad_op(   0x52)
read_unop(0x53, "SRE iY",   addr_rw_iy,   ex_sre)
read_unop(0x54, "NOP ZX",   addr_r_zx,    ex_nop)
read_op(  0x55, "EOR ZX",   addr_r_zx,    ex_eor)
read_op(  0x56, "LSR ZX",   addr_rw_zx,   ex_lsr)
read_unop(0x57, "SRE ZX",   addr_rw_zx,   ex_sre)
// 0x58: CLI
  j ex_cli
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x59, "EOR absY", addr_r_absy,  ex_eor)
un_noop(  0x5a)
read_unop(0x5b, "SRE absY", addr_rw_absy, ex_sre)
read_unop(0x5c, "NOP absX", addr_r_absx,  ex_nop)
read_op(  0x5d, "EOR absX", addr_r_absx,  ex_eor)
read_op(  0x5e, "LSR absX", addr_rw_absx, ex_lsr)
read_unop(0x5f, "SRE absX", addr_rw_absx, ex_sre)

stack_op( 0x60, "RTS",                    ex_rts)
read_op(  0x61, "ADC iX",   addr_r_ix,    ex_adc)
bad_op(   0x62)
read_unop(0x63, "RRA iX",   addr_rw_ix,   ex_rra)
read_unop(0x64, "NOP ZP",   addr_r_zp,    ex_nop)
read_op(  0x65, "ADC ZP",   addr_r_zp,    ex_adc)
read_op(  0x66, "ROR ZP",   addr_rw_zp,   ex_ror)
read_unop(0x67, "RRA ZP",   addr_rw_zp,   ex_rra)
stack_op( 0x68, "PLA",                    ex_pla)
read_op(  0x69, "ADC imm",  addr_r_imm,   ex_adc)
// 0x6a: ROR acc
  j ex_ror_acc
  lbu cpu_t0, cpu_c_byte (r0)
read_unop(0x6b, "ARR imm",  addr_r_imm,   ex_arr)
// 0x6c: JMP (abs)
  j ex_jmp_absi
  lbu cpu_t0, 0 (cpu_mpc)
read_op(  0x6d, "ADC abs",  addr_r_abs,   ex_adc)
read_op(  0x6e, "ROR abs",  addr_rw_abs,  ex_ror)
read_unop(0x6f, "RRA abs",  addr_rw_abs,  ex_rra)

// 0x70: BVS
  j ex_bvs
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x71, "ADC iY",   addr_r_iy,    ex_adc)
bad_op(   0x72)
read_unop(0x73, "RRA iY",   addr_rw_iy,   ex_rra)
read_unop(0x74, "NOP ZX",   addr_r_zx,    ex_nop)
read_op(  0x75, "ADC ZX",   addr_r_zx,    ex_adc)
read_op(  0x76, "ROR ZX",   addr_rw_zx,   ex_ror)
read_unop(0x77, "RRA ZX",   addr_rw_zx,   ex_rra)
// 0x78: SEI
  j ex_sei
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x79, "ADC absY", addr_r_absy,  ex_adc)
un_noop(  0x7a)
read_unop(0x7b, "RRA absY", addr_rw_absy, ex_rra)
read_unop(0x7c, "NOP absX", addr_r_absx,  ex_nop)
read_op(  0x7d, "ADC absX", addr_r_absx,  ex_adc)
read_op(  0x7e, "ROR absX", addr_rw_absx, ex_ror)
read_unop(0x7f, "RRA absX", addr_rw_absx, ex_rra)

read_unop(0x80, "NOP imm",  addr_r_imm,   ex_nop)
write_op( 0x81, "STA iX",   addr_w_ix,    cpu_acc)
read_unop(0x82, "NOP imm",  addr_r_imm,   ex_nop)
if {defined UNOFFICIAL_OPCODES} {
// 0x83: SAX iX
  j addr_w_ix
  and cpu_t0, cpu_acc, cpu_x
} else {
bad_op(   0x83)
}
write_op( 0x84, "STY ZP",   addr_w_zp,    cpu_y)
write_op( 0x85, "STA ZP",   addr_w_zp,    cpu_acc)
write_op( 0x86, "STX ZP",   addr_w_zp,    cpu_x)
if {defined UNOFFICIAL_OPCODES} {
// 0x87: SAX ZP
  j addr_w_zp
  and cpu_t0, cpu_acc, cpu_x
} else {
bad_op(   0x87)
}
// 0x88: DEY
  j ex_iny_dey
  addiu cpu_y, -1
read_unop(0x89, "NOP imm",  addr_r_imm,   ex_nop)
// 0x8a: TXA
  j ex_transfer_acc
  move cpu_acc, cpu_x
read_unop(0x8b, "XAA imm",  addr_r_imm,   ex_xaa)
write_op( 0x8c, "STY abs",  addr_w_abs,   cpu_y)
write_op( 0x8d, "STA abs",  addr_w_abs,   cpu_acc)
write_op( 0x8e, "STX abs",  addr_w_abs,   cpu_x)
if {defined UNOFFICIAL_OPCODES} {
// 0x8f: SAX abs
  j addr_w_abs
  and cpu_t0, cpu_acc, cpu_x
} else {
bad_op(   0x8f)
}

// 0x90: BCC
  j ex_bcc
  lbu cpu_t0, cpu_c_byte (r0)
write_op( 0x91, "STA iY",   addr_w_iy,    cpu_acc)
bad_op(   0x92)
if {defined UNOFFICIAL_OPCODES} {
// 0x93: AHX iY
  j ex_ahx_iy ; nop
} else {
bad_op(   0x93)
}
write_op( 0x94, "STY ZX",   addr_w_zx,    cpu_y)
write_op( 0x95, "STA ZX",   addr_w_zx,    cpu_acc)
write_op( 0x96, "STX ZY",   addr_w_zy,    cpu_x)
if {defined UNOFFICIAL_OPCODES} {
// 0x97: SAX ZY
  j addr_w_zy
  and cpu_t0, cpu_acc, cpu_x
} else {
bad_op(   0x97)
}

// 0x98: TYA
  j ex_transfer_acc
  move cpu_acc, cpu_y
write_op( 0x99, "STA absY", addr_w_absy,  cpu_acc)
// 0x9a: TXS
  j FinishCycleAndFetchOpcode
  sb cpu_x, cpu_stack (r0)
if {defined UNOFFICIAL_OPCODES} {
// 0x9b: TAS
  j ex_tas ; nop
// 0x9c: SHY absX
  j addr_w_shxy
  move cpu_t0, cpu_y
} else {
bad_op(   0x9b)
bad_op(   0x9c)
}
write_op( 0x9d, "STA absX", addr_w_absx,  cpu_acc)
if {defined UNOFFICIAL_OPCODES} {
// 0x9e: SHX absY
  j addr_w_shxy
  move cpu_t0, cpu_x
// 0x9f: AHX abxY
  j ex_ahx_absy ; nop
} else {
bad_op(   0x9e)
bad_op(   0x9f)
}

read_op(  0xa0, "LDY imm",  addr_r_imm,   ex_ldy)
read_op(  0xa1, "LDA iX",   addr_r_ix,    ex_lda)
read_op(  0xa2, "LDX imm",  addr_r_imm,   ex_ldx)
read_unop(0xa3, "LAX iX",   addr_r_ix,    ex_lax)
read_op(  0xa4, "LDY ZP",   addr_r_zp,    ex_ldy)
read_op(  0xa5, "LDA ZP",   addr_r_zp,    ex_lda)
read_op(  0xa6, "LDX ZP",   addr_r_zp,    ex_ldx)
read_unop(0xa7, "LAX ZP",   addr_r_zp,    ex_lax)
// 0xa8: TAY
  j ex_transfer_acc
  move cpu_y, cpu_acc
read_op(  0xa9, "LDA imm",  addr_r_imm,   ex_lda)
// 0xaa: TAX
  j ex_transfer_acc
  move cpu_x, cpu_acc
read_unop(0xab, "LAX imm",  addr_r_imm,   ex_lax)
read_op(  0xac, "LDY abs",  addr_r_abs,   ex_ldy)
read_op(  0xad, "LDA abs",  addr_r_abs,   ex_lda)
read_op(  0xae, "LDX abs",  addr_r_abs,   ex_ldx)
read_unop(0xaf, "LAX abs",  addr_r_abs,   ex_lax)

// 0xb0: BCS
  j ex_bcs
  lbu cpu_t0, cpu_c_byte (r0)
read_op(  0xb1, "LDA iY",   addr_r_iy,    ex_lda)
bad_op(   0xb2)
read_unop(0xb3, "LAX iY",   addr_r_iy,    ex_lax)
read_op(  0xb4, "LDY ZX",   addr_r_zx,    ex_ldy)
read_op(  0xb5, "LDA ZX",   addr_r_zx,    ex_lda)
read_op(  0xb6, "LDX ZY",   addr_r_zy,    ex_ldx)
read_unop(0xb7, "LAX ZY",   addr_r_zy,    ex_lax)
// 0xb8: CLV
  j ex_clv
  lbu cpu_t0, cpu_flags (r0)
read_op(  0xb9, "LDA absY", addr_r_absy,  ex_lda)
// 0xba: TSX
  j ex_tsx
  lbu cpu_x, cpu_stack (r0)
read_unop(0xbb, "LAS absX", addr_r_absy,  ex_las)
read_op(  0xbc, "LDY absX", addr_r_absx,  ex_ldy)
read_op(  0xbd, "LDA absX", addr_r_absx,  ex_lda)
read_op(  0xbe, "LDX absY", addr_r_absy,  ex_ldx)
read_unop(0xbf, "LAX absY", addr_r_absy,  ex_lax)

read_op(  0xc0, "CPY imm",  addr_r_imm,   ex_cpy)
read_op(  0xc1, "CMP iX",   addr_r_ix,    ex_cmp)
read_unop(0xc2, "NOP imm",  addr_r_imm,   ex_nop)
read_unop(0xc3, "DCP iX",   addr_rw_ix,   ex_dcp)
read_op(  0xc4, "CPY ZP",   addr_r_zp,    ex_cpy)
read_op(  0xc5, "CMP ZP",   addr_r_zp,    ex_cmp)
read_op(  0xc6, "DEC ZP",   addr_rw_zp,   ex_dec)
read_unop(0xc7, "DCP ZP",   addr_rw_zp,   ex_dcp)
// 0xc8: INY
  j ex_iny_dey
  addiu cpu_y, 1
read_op(  0xc9, "CMP imm",  addr_r_imm,   ex_cmp)
// 0xca: DEX
  j ex_inx_dex
  addiu cpu_x, -1
read_unop(0xcb, "AXS imm",  addr_r_imm,   ex_axs)
read_op(  0xcc, "CPY abs",  addr_r_abs,   ex_cpy)
read_op(  0xcd, "CMP abs",  addr_r_abs,   ex_cmp)
read_op(  0xce, "DEC abs",  addr_rw_abs,  ex_dec)
read_unop(0xcf, "DCP abs",  addr_rw_abs,  ex_dcp)

// 0xd0
  j ex_bne
  lbu cpu_t0, cpu_z_byte (r0)
read_op(  0xd1, "CMP iY",   addr_r_iy,    ex_cmp)
bad_op(   0xd2)
read_unop(0xd3, "DCP iY",   addr_rw_iy,   ex_dcp)
read_unop(0xd4, "NOP ZX",   addr_r_zx,    ex_nop)
read_op(  0xd5, "CMP ZX",   addr_r_zx,    ex_cmp)
read_op(  0xd6, "DEC ZX",   addr_rw_zx,   ex_dec)
read_unop(0xd7, "DCP ZX",   addr_rw_zx,   ex_dcp)
// 0xd8: CLD
  j ex_cld
  lbu cpu_t0, cpu_flags (r0)
read_op(  0xd9, "CMP absY", addr_r_absy,  ex_cmp)
un_noop(  0xda)
read_unop(0xdb, "DCP absY", addr_rw_absy, ex_dcp)
read_unop(0xdc, "NOP absX", addr_r_absx,  ex_nop)
read_op(  0xdd, "CMP absX", addr_r_absx,  ex_cmp)
read_op(  0xde, "DEC absX", addr_rw_absx, ex_dec)
read_unop(0xdf, "DCP absX", addr_rw_absx, ex_dcp)

read_op(  0xe0, "CPX imm",  addr_r_imm,   ex_cpx)
read_op(  0xe1, "SBC iX",   addr_r_ix,    ex_sbc)
read_unop(0xe2, "NOP imm",  addr_r_imm,   ex_nop)
read_unop(0xe3, "ISC iX",   addr_rw_ix,   ex_isc)
read_op(  0xe4, "CPX ZP",   addr_r_zp,    ex_cpx)
read_op(  0xe5, "SBC ZP",   addr_r_zp,    ex_sbc)
read_op(  0xe6, "INC ZP",   addr_rw_zp,   ex_inc)
read_unop(0xe7, "ISC ZP",   addr_rw_zp,   ex_isc)
// 0xe8: INX
  j ex_inx_dex
  addi cpu_x, 1
read_op(  0xe9, "SBC imm",  addr_r_imm,   ex_sbc)
// 0xea: NOP
  j ex_nop ; nop
read_unop(0xeb, "SBC imm",  addr_r_imm,   ex_sbc)
read_op(  0xec, "CPX abs",  addr_r_abs,   ex_cpx)
read_op(  0xed, "SBC abs",  addr_r_abs,   ex_sbc)
read_op(  0xee, "INC abs",  addr_rw_abs,  ex_inc)
read_unop(0xef, "ISC abs",  addr_rw_abs,  ex_isc)

// 0xf0: BEQ
  j ex_beq
  lbu cpu_t0, cpu_z_byte (r0)
read_op(  0xf1, "SBC iY",   addr_r_iy,    ex_sbc)
bad_op(   0xf2)
read_unop(0xf3, "ISC iY",   addr_rw_iy,   ex_isc)
read_unop(0xf4, "NOP ZX",   addr_r_zx,    ex_nop)
read_op(  0xf5, "SBC ZX",   addr_r_zx,    ex_sbc)
read_op(  0xf6, "INC ZX",   addr_rw_zx,   ex_inc)
read_unop(0xf7, "ISC ZX",   addr_rw_zx,   ex_isc)
// 0xf8: SED
  j ex_sed
  lbu cpu_t0, cpu_flags (r0)
read_op(  0xf9, "SBC absY", addr_r_absy,  ex_sbc)
un_noop(  0xfa)
read_unop(0xfb, "ISC absY", addr_rw_absy, ex_isc)
read_unop(0xfc, "NOP absX", addr_r_absx,  ex_nop)
read_op(  0xfd, "SBC absX", addr_r_absx,  ex_sbc)
read_op(  0xfe, "INC absX", addr_rw_absx, ex_inc)
read_unop(0xff, "ISC absX", addr_rw_absx, ex_isc)

check_index(0x100)
