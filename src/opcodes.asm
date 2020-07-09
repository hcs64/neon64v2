// Ref opcodes: http://www.6502.org/tutorials/6502opcodes.html

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

// Note: For ops that don't use the normal addressing modes,
// or for Stores (write_op), I try to include some of the
// work in the delay slot of the jump to the ex_*, usually
// loading something into cpu_t0.

opcode_table:
stack_op( 0x00, "BRK",                    TakeBRK)
read_op(  0x01, "ORA iX",   addr_r_ix,    ex_ora)
bad_op(   0x02)
bad_op(   0x03)
bad_op(   0x04)
read_op(  0x05, "ORA ZP",   addr_r_zp,    ex_ora)
read_op(  0x06, "ASL ZP",   addr_rw_zp,   ex_asl)
bad_op(   0x07)
stack_op( 0x08, "PHP",                    ex_php)
read_op(  0x09, "ORA imm",  addr_r_imm,   ex_ora)
// 0x0a: ASL acc
  j ex_asl_acc
  srl cpu_t0, cpu_acc, 7
bad_op(   0x0b)
bad_op(   0x0c)
read_op(  0x0d, "ORA abs",  addr_r_abs,   ex_ora)
read_op(  0x0e, "ASL abs",  addr_rw_abs,  ex_asl)
bad_op(   0x0f)
// 0x10: BPL
  j ex_bpl
  lb cpu_t0, cpu_n_byte (r0)
read_op(  0x11, "ORA iY",   addr_r_iy,    ex_ora)
bad_op(   0x12)
bad_op(   0x13)
bad_op(   0x14)
read_op(  0x15, "ORA ZX",   addr_r_zx,    ex_ora)
read_op(  0x16, "ASL ZX",   addr_rw_zx,   ex_asl)
bad_op(   0x17)
// 0x18: CLC
  j FinishCycleAndFetchOpcode
  sb r0, cpu_c_byte (r0)
read_op(  0x19, "ORA absY", addr_r_absy,  ex_ora)
bad_op(   0x1a)
bad_op(   0x1b)
bad_op(   0x1c)
read_op(  0x1d, "ORA absX", addr_r_absx,  ex_ora)
read_op(  0x1e, "ASL absX", addr_rw_absx, ex_asl)
bad_op(   0x1f)

// 0x20: JSR
  j ex_jsr
  lbu cpu_t0, 0 (cpu_mpc)
read_op(  0x21, "AND iX",   addr_r_ix,    ex_and)
bad_op(   0x22)
bad_op(   0x23)
read_op(  0x24, "BIT ZP",   addr_r_zp,    ex_bit)
read_op(  0x25, "AND ZP",   addr_r_zp,    ex_and)
read_op(  0x26, "ROL ZP",   addr_rw_zp,   ex_rol)
bad_op(   0x27)
stack_op( 0x28, "PLP",                    ex_plp)
read_op(  0x29, "AND imm",  addr_r_imm,   ex_and)
// 0x2a: ROL acc
  j ex_rol_acc
  lbu cpu_t0, cpu_c_byte (r0)
bad_op(   0x2b)
read_op(  0x2c, "BIT abs",  addr_r_abs,   ex_bit)
read_op(  0x2d, "AND abs",  addr_r_abs,   ex_and)
read_op(  0x2e, "ROL abs",  addr_rw_abs,  ex_rol)
bad_op(   0x2f)

// 0x30: BMI
  j ex_bmi
  lb cpu_t0, cpu_n_byte (r0)
read_op(  0x31, "AND iY",   addr_r_iy,    ex_and)
bad_op(   0x32)
bad_op(   0x33)
bad_op(   0x34)
read_op(  0x35, "AND ZX",   addr_r_zx,    ex_and)
read_op(  0x36, "ROL ZX",   addr_rw_zx,   ex_rol)
bad_op(   0x37)
// 0x38: SEC
  j ex_sec
  lli cpu_t0, 1
read_op(  0x39, "AND absY", addr_r_absy,  ex_and)
bad_op(   0x3a)
bad_op(   0x3b)
bad_op(   0x3c)
read_op(  0x3d, "AND absX", addr_r_absx,  ex_and)
read_op(  0x3e, "ROL absX", addr_rw_absx, ex_rol)
bad_op(   0x3f)

stack_op( 0x40, "RTI",                    ex_rti)
read_op(  0x41, "EOR iX",   addr_r_ix,    ex_eor)
bad_op(   0x42)
bad_op(   0x43)
bad_op(   0x44)
read_op(  0x45, "EOR ZP",   addr_r_zp,    ex_eor)
read_op(  0x46, "LSR ZP",   addr_rw_zp,   ex_lsr)
bad_op(   0x47)
stack_op( 0x48, "PHA",                    ex_pha)
read_op(  0x49, "EOR imm",  addr_r_imm,   ex_eor)
// 0x4a: LSR acc
  j ex_lsr_acc
  andi cpu_t0, cpu_acc, 1
bad_op(   0x4b)
// 0x4c: JMP abs
  j ex_jmp_abs
  lbu cpu_t0, 0 (cpu_mpc)
read_op(  0x4d, "EOR abs",  addr_r_abs,   ex_eor)
read_op(  0x4e, "LSR abs",  addr_rw_abs,  ex_lsr)
bad_op(   0x4f)

// 0x50: BVC
  j ex_bvc
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x51, "EOR iY",   addr_r_iy,    ex_eor)
bad_op(   0x52)
bad_op(   0x53)
bad_op(   0x54)
read_op(  0x55, "EOR ZX",   addr_r_zx,    ex_eor)
read_op(  0x56, "LSR ZX",   addr_rw_zx,   ex_lsr)
bad_op(   0x57)
// 0x58: CLI
  j ex_cli
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x59, "EOR absY", addr_r_absy,  ex_eor)
bad_op(   0x5a)
bad_op(   0x5b)
bad_op(   0x5c)
read_op(  0x5d, "EOR absX", addr_r_absx,  ex_eor)
read_op(  0x5e, "LSR absX", addr_rw_absx, ex_lsr)
bad_op(   0x5f)

stack_op( 0x60, "RTS",                    ex_rts)
read_op(  0x61, "ADC iX",   addr_r_ix,    ex_adc)
bad_op(   0x62)
bad_op(   0x63)
bad_op(   0x64)
read_op(  0x65, "ADC ZP",   addr_r_zp,    ex_adc)
read_op(  0x66, "ROR ZP",   addr_rw_zp,   ex_ror)
bad_op(   0x67)
stack_op( 0x68, "PLA",                    ex_pla)
read_op(  0x69, "ADC imm",  addr_r_imm,   ex_adc)
// 0x6a: ROR acc
  j ex_ror_acc
  lbu cpu_t0, cpu_c_byte (r0)
bad_op(   0x6b)
// 0x6c: JMP (abs)
  j ex_jmp_absi
  lbu cpu_t0, 0 (cpu_mpc)
read_op(  0x6d, "ADC abs",  addr_r_abs,   ex_adc)
read_op(  0x6e, "ROR abs",  addr_rw_abs,  ex_ror)
bad_op(   0x6f)

// 0x70: BVS
  j ex_bvs
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x71, "ADC iY",   addr_r_iy,    ex_adc)
bad_op(   0x72)
bad_op(   0x73)
bad_op(   0x74)
read_op(  0x75, "ADC ZX",   addr_r_zx,    ex_adc)
read_op(  0x76, "ROR ZX",   addr_rw_zx,   ex_ror)
bad_op(   0x77)
// 0x78: SEI
  j ex_sei
  lbu cpu_t0, cpu_flags (r0)
read_op(  0x79, "ADC absY", addr_r_absy,  ex_adc)
bad_op(   0x7a)
bad_op(   0x7b)
bad_op(   0x7c)
read_op(  0x7d, "ADC absX", addr_r_absx,  ex_adc)
read_op(  0x7e, "ROR absX", addr_rw_absx, ex_ror)
bad_op(   0x7f)

bad_op(   0x80)
write_op( 0x81, "STA iX",   addr_w_ix,    cpu_acc)
bad_op(   0x82)
bad_op(   0x83)
write_op( 0x84, "STY ZP",   addr_w_zp,    cpu_y)
write_op( 0x85, "STA ZP",   addr_w_zp,    cpu_acc)
write_op( 0x86, "STX ZP",   addr_w_zp,    cpu_x)
bad_op(   0x87)
// 0x88: DEY
  j ex_iny_dey
  addiu cpu_y, -1
bad_op(   0x89)
// 0x8a: TXA
  j ex_transfer_acc
  move cpu_acc, cpu_x
bad_op(   0x8b)
write_op( 0x8c, "STY abs",  addr_w_abs,   cpu_y)
write_op( 0x8d, "STA abs",  addr_w_abs,   cpu_acc)
write_op( 0x8e, "STX abs",  addr_w_abs,   cpu_x)
bad_op(   0x8f)

// 0x90: BCC
  j ex_bcc
  lbu cpu_t0, cpu_c_byte (r0)
write_op( 0x91, "STA iY",   addr_w_iy,    cpu_acc)
bad_op(   0x92)
bad_op(   0x93)
write_op( 0x94, "STY ZX",   addr_w_zx,    cpu_y)
write_op( 0x95, "STA ZX",   addr_w_zx,    cpu_acc)
write_op( 0x96, "STX ZY",   addr_w_zy,    cpu_x)
bad_op(   0x97)
// 0x98: TYA
  j ex_transfer_acc
  move cpu_acc, cpu_y
write_op( 0x99, "STA absY", addr_w_absy,  cpu_acc)
// 0x9a: TXS
  j FinishCycleAndFetchOpcode
  sb cpu_x, cpu_stack (r0)
bad_op(   0x9b)
bad_op(   0x9c)
write_op( 0x9d, "STA absX", addr_w_absx,  cpu_acc)
bad_op(   0x9e)
bad_op(   0x9f)

read_op(  0xa0, "LDY imm",  addr_r_imm,   ex_ldy)
read_op(  0xa1, "LDA IX",   addr_r_ix,    ex_lda)
read_op(  0xa2, "LDX imm",  addr_r_imm,   ex_ldx)
bad_op(   0xa3)
read_op(  0xa4, "LDY ZP",   addr_r_zp,    ex_ldy)
read_op(  0xa5, "LDA ZP",   addr_r_zp,    ex_lda)
read_op(  0xa6, "LDX ZP",   addr_r_zp,    ex_ldx)
bad_op(   0xa7)
// 0xa8: TAY
  j ex_transfer_acc
  move cpu_y, cpu_acc
read_op(    0xa9, "LDA imm",  addr_r_imm,   ex_lda)
// 0xaa: TAX
  j ex_transfer_acc
  move cpu_x, cpu_acc
bad_op(   0xab)
read_op(  0xac, "LDY abs",  addr_r_abs,   ex_ldy)
read_op(  0xad, "LDA abs",  addr_r_abs,   ex_lda)
read_op(  0xae, "LDX abs",  addr_r_abs,   ex_ldx)
bad_op(   0xaf)

// 0xb0: BCS
  j ex_bcs
  lbu cpu_t0, cpu_c_byte (r0)
read_op(  0xb1, "LDA IY",   addr_r_iy,    ex_lda)
bad_op(   0xb2)
bad_op(   0xb3)
read_op(  0xb4, "LDY ZX",   addr_r_zx,    ex_ldy)
read_op(  0xb5, "LDA ZX",   addr_r_zx,    ex_lda)
read_op(  0xb6, "LDX ZY",   addr_r_zy,    ex_ldx)
bad_op(   0xb7)
// 0xb8: CLV
  j ex_clv
  lbu cpu_t0, cpu_flags (r0)
read_op(  0xb9, "LDA absY", addr_r_absy,  ex_lda)
// 0xba: TSX
  j ex_tsx
  lbu cpu_x, cpu_stack (r0)
bad_op(   0xbb)
read_op(  0xbc, "LDY absX", addr_r_absx,  ex_ldy)
read_op(  0xbd, "LDA absX", addr_r_absx,  ex_lda)
read_op(  0xbe, "LDX absY", addr_r_absy,  ex_ldx)
bad_op(   0xbf)

read_op(  0xc0, "CPY imm",  addr_r_imm,   ex_cpy)
read_op(  0xc1, "CMP IX",   addr_r_ix,    ex_cmp)
bad_op(   0xc2)
bad_op(   0xc3)
read_op(  0xc4, "CPY ZP",   addr_r_zp,    ex_cpy)
read_op(  0xc5, "CMP ZP",   addr_r_zp,    ex_cmp)
read_op(  0xc6, "DEC ZP",   addr_rw_zp,   ex_dec)
bad_op(   0xc7)
// 0xc8: INY
  j ex_iny_dey
  addiu cpu_y, 1
read_op(  0xc9, "CMP imm",  addr_r_imm,   ex_cmp)
// 0xca: DEX
  j ex_inx_dex
  addiu cpu_x, -1
bad_op(   0xcb)
read_op(  0xcc, "CPY abs",  addr_r_abs,   ex_cpy)
read_op(  0xcd, "CMP abs",  addr_r_abs,   ex_cmp)
read_op(  0xce, "DEC abs",  addr_rw_abs,  ex_dec)
bad_op(   0xcf)

// 0xd0
  j ex_bne
  lbu cpu_t0, cpu_z_byte (r0)
read_op(  0xd1, "CMP IY",   addr_r_iy,    ex_cmp)
bad_op(   0xd2)
bad_op(   0xd3)
bad_op(   0xd4)
read_op(  0xd5, "CMP ZX",   addr_r_zx,    ex_cmp)
read_op(  0xd6, "DEC ZX",   addr_rw_zx,   ex_dec)
bad_op(   0xd7)
// 0xd8: CLD
  j ex_cld
  lbu cpu_t0, cpu_flags (r0)
read_op(  0xd9, "CMP absY", addr_r_absy,  ex_cmp)
bad_op(   0xda)
bad_op(   0xdb)
bad_op(   0xdc)
read_op(  0xdd, "CMP absX", addr_r_absx,  ex_cmp)
read_op(  0xde, "DEC absX", addr_rw_absx, ex_dec)
bad_op(   0xdf)

read_op(  0xe0, "CPX imm",  addr_r_imm,   ex_cpx)
read_op(  0xe1, "SBC IX",   addr_r_ix,    ex_sbc)
bad_op(   0xe2)
bad_op(   0xe3)
read_op(  0xe4, "CPX ZP",   addr_r_zp,    ex_cpx)
read_op(  0xe5, "SBC ZP",   addr_r_zp,    ex_sbc)
read_op(  0xe6, "INC ZP",   addr_rw_zp,   ex_inc)
bad_op(   0xe7)
// 0xe8: INX
  j ex_inx_dex
  addi cpu_x, 1
read_op(  0xe9, "SBC imm",  addr_r_imm,   ex_sbc)
// 0xea: NOP
  j FinishCycleAndFetchOpcode
  nop
bad_op(   0xeb)
read_op(  0xec, "CPX abs",  addr_r_abs,   ex_cpx)
read_op(  0xed, "SBC abs",  addr_r_abs,   ex_sbc)
read_op(  0xee, "INC abs",  addr_rw_abs,  ex_inc)
bad_op(   0xef)

// 0xf0: BEQ
  j ex_beq
  lbu cpu_t0, cpu_z_byte (r0)
read_op(  0xf1, "SBC IY",   addr_r_iy,    ex_sbc)
bad_op(   0xf2)
bad_op(   0xf3)
bad_op(   0xf4)
read_op(  0xf5, "SBC ZX",   addr_r_zx,    ex_sbc)
read_op(  0xf6, "INC ZX",   addr_rw_zx,   ex_inc)
bad_op(   0xf7)
// 0xf8: SED
  j ex_sed
  lbu cpu_t0, cpu_flags (r0)
read_op(  0xf9, "SBC absY", addr_r_absy,  ex_sbc)
bad_op(   0xfa)
bad_op(   0xfb)
bad_op(   0xfc)
read_op(  0xfd, "SBC absX", addr_r_absx,  ex_sbc)
read_op(  0xfe, "INC absX", addr_rw_absx, ex_inc)
bad_op(   0xff)

check_index(0x100)
