variable bss_pc(bss_base)

macro begin_bss() {
  pushvar base
  pushvar origin
  close_output_file()
  base bss_pc
}

// XXX does not work in a scope!
macro end_bss() {
  global variable bss_pc(pc())
  reopen_output_file()
  pullvar origin
  pullvar base
}
