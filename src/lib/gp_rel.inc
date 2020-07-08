// gp-relative addressing

// The including file must have macros reopen_output_file and close_output_file,
// they can't be here or there will be issues if this is in different directory.
// It must also define a constant gp_base.

macro check_gp(evaluate addr) {
  if {addr} - gp_base > 0x7fff || {addr} - gp_base < -0x8000 {
    print {addr}, "\n"
    error "gp-relative out of range"
  }
}

// gp-relative lX/lXu/sX
macro ls_gp(op_reg, evaluate addr) {
  check_gp({addr})
  {op_reg}, {addr} - gp_base (gp)
}

// gp-relative la
macro la_gp(evaluate reg, evaluate addr) {
  check_gp({addr})
  addi  {reg}, gp, {addr} - gp_base
}

macro gp_init() {
  la    gp, gp_base
}
