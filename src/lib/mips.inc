// MIPS 4300 CPU Registers
constant r0(0)

// COP0 registers:
constant Index($00)
constant Random($01)
constant EntryLo0($02)
constant EntryLo1($03)
constant Context($04)
constant PageMask($05)
constant Wired($06)
//constant *RESERVED*($07)
constant BadVAddr($08)
constant Count($09)
constant EntryHi($0A)
constant Compare($0B)
constant Status($0C)
constant Cause($0D)
constant EPC($0E)
constant PRevID($0F)
constant Config($10)
constant LLAddr($11)
constant WatchLo($12)
constant WatchHi($13)
constant XContext($14)
//constant *RESERVED*($15)
//constant *RESERVED*($16)
//constant *RESERVED*($17)
//constant *RESERVED*($18)
//constant *RESERVED*($19)
constant PErr($1A)
constant CacheErr($1B)
constant TagLo($1C)
constant TagHi($1D)
constant ErrorEPC($1E)
//constant *RESERVED*($1F)

// MIPS 4300 CP1 Floating Point Unit (FPU) Registers (COP1)
constant f0(0)
constant f1(1)
constant f2(2)
constant f3(3)
constant f4(4)
constant f5(5)
constant f6(6)
constant f7(7)
constant f8(8)
constant f9(9)
constant f10(10)
constant f11(11)
constant f12(12)
constant f13(13)
constant f14(14)
constant f15(15)
constant f16(16)
constant f17(17)
constant f18(18)
constant f19(19)
constant f20(20)
constant f21(21)
constant f22(22)
constant f23(23)
constant f24(24)
constant f25(25)
constant f26(26)
constant f27(27)
constant f28(28)
constant f29(29)
constant f30(30)
constant f31(31)

constant DCACHE_LINE(16)
constant ICACHE_LINE(32)

// Alignment
macro align(evaluate size) { // Align Byte Amount
  while (pc() % {size}) {
    db 0
  }
}
macro align_file(evaluate size) {
  while (origin() % {size}) {
    db 0
  }
}

macro align_dcache() {
  align(DCACHE_LINE)
}

macro align_icache() {
  align(ICACHE_LINE)
}

macro assert_pc_alignment(evaluate size) {
  if pc() % size != 0 {
    print "pc=", pc(), " alignment=", {size}
    error "not aligned"
  }
}

// Cache ops
constant data_create_dirty_exclusive(1|(3<<2))
constant inst_hit_invalidate(0|(4<<2))
constant data_hit_invalidate(1|(4<<2))
constant data_hit_write_back_invalidate(1|(5<<2))
constant inst_fill(0|(5<<2))
constant inst_hit_write_back(0|(6<<2))
constant data_hit_write_back(1|(6<<2))

// Conveniences
macro la_hi(reg, evaluate addr) {
  lui {reg}, {addr}>>16
}

macro la_lo(reg, evaluate addr) {
  ori {reg}, {addr}&0xffff
}
