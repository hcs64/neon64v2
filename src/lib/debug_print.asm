InitDebug:
  la_gp(t0, debug_buffer)
  jr ra
  ls_gp(sw t0, debug_buffer_cursor)

// Print decimal
// a0: 32-bit signed value
scope PrintDec: {
  constant val(a0)
  constant out(t0)
  constant tmp(t1)


  bgez a0, non_negative
  ls_gp(lw out, debug_buffer_cursor)

  lli tmp, '-'
  sb tmp, 0(out)
  addi out, 1
  ls_gp(sw out, debug_buffer_cursor)

  neg val

non_negative:
  {
    constant ten(t2)
    lli ten, 10
digits_loop:
    divu val, ten
    mfhi tmp // remainder
    mflo val // quotient
    addi tmp, '0'
    sb tmp, 0(out)
    bnez val, digits_loop
    addi out, 1
  }

  {
    constant tmp2(a0)
    constant out_start(t2)

    ls_gp(lw out_start, debug_buffer_cursor)
    ls_gp(sw out, debug_buffer_cursor)
reverse_loop:
    addi out, -1
    lbu tmp, 0(out)
    lbu tmp2, 0(out_start)
    sb tmp, 0(out_start)

    addi out_start, 1
    subu tmp, out, out_start
    bgtz tmp, reverse_loop
    sb tmp2, 0(out)
  }

  jr ra
  nop
}

// Print hexadecimal
// a0: value
// a1: length to print
scope PrintHex: {
  constant val(a0)
  constant len(a1)
  constant out(t0)
  constant dgts(t1)
  constant tmp(t2)

  ls_gp(lw out, debug_buffer_cursor)
  la dgts, digits

  // seek to the end to write backwards
  add out, len
  addi tmp, out, 1
  ls_gp(sw tmp, debug_buffer_cursor)

loop:
  addi  len, -1
  andi  tmp, val, 0xf
  add   tmp, dgts
  lbu   tmp, 0(tmp)
  dsrl  val, 4
  sb    tmp, 0(out)
  bnez  len, loop
  addi  out, -1

  lli   tmp, '$'
  sb    tmp, 0(out)

  jr ra
  nop
}

// a0: string
// a1: length
scope PrintStr: {
  constant str(a0)
  constant len(a1)
  constant out(t0)
  constant byte(t1)

  ls_gp(lw out, debug_buffer_cursor)

loop:
  lbu  byte, 0(str)
  addi str, 1
  sb   byte, 0(out)
  addi len, -1
  bnez len, loop
  addi out, 1

  jr ra
  ls_gp(sw out, debug_buffer_cursor)
}

// a0: string
// a1: length
scope PrintStr0Pad: {
  constant str(a0)
  constant len(a1)
  constant out(t0)
  constant byte(t1)

  ls_gp(lw out, debug_buffer_cursor)

copy_loop:
  lbu  byte, 0(str)
  addi str, 1
  beqz byte,+
  sb   byte, 0(out)
  addi len, -1
  j copy_loop
  addi out, 1
+

  beqz len,+
  lli byte, ' '
pad_loop:
  sb  byte, 0(out)
  addi len, -1
  bgtz len, pad_loop
  addi out, 1
+
  jr ra
  ls_gp(sw out, debug_buffer_cursor)
}

// a0: null-terminated string
scope PrintStr0: {
  constant str(a0)
  constant out(t0)
  constant byte(t1)

  ls_gp(lw out, debug_buffer_cursor)

loop:
  lbu   byte, 0(str)
  addi  str, 1
  sb    byte, 0(out)
  bnezl byte, loop
  addi  out, 1

  jr ra
  ls_gp(sw out, debug_buffer_cursor)
}

// Newline is needed for cen64 to output
NewlineAndFlushDebug:
  move a1, ra

  jal PrintStr0
  la_gp(a0, newline)

  jal FlushDebug
  nop

  jr a1
  nop

scope FlushDebug: {
  constant in(t0)
  constant in_len(t1)
  constant out(t2)
  constant word(t3)
  constant count(t4)

  ls_gp(lw in_len, debug_buffer_cursor)
  la_gp(in, debug_buffer)
  // reset cursor
  ls_gp(sw in, debug_buffer_cursor)
  lui   out, ISV_BASE
  sub   in_len, in
  move  count, in_len

loop:
  ld    word, 0(in)
  sd    word, ISV_DBG_BUF(out)
  addi  count, -8
  addi  out, 8
  bgtz  count, loop
  addi  in, 8

  lui   out, ISV_BASE
  jr ra
  sw    in_len, ISV_DBG_LEN(out)
}

ResetDebug:
  la_gp(t0, debug_buffer)
  jr ra
  ls_gp(sw t0, debug_buffer_cursor)

digits:;  db "0123456789abcdef"
space:;   db " ", 0
newline:; db "\n", 0
align(4)

  begin_bss()

  align(8)
constant debug_buffer_size(1024)
debug_buffer:;        fill debug_buffer_size
  align(4)
debug_buffer_cursor:; fill 4

  end_bss()
