constant rom_cart_addr(0x1000'0000)
constant sram_cart_addr(0x0800'0000)

macro pi_wait(pi_base, tmp) {
-
  lw {tmp}, PI_STATUS ({pi_base})
  andi {tmp}, 0b11 // DMA or I/O busy
  bnez {tmp},-
  nop
}

scope PI {

// Note: a1 and a2 should be aligned to 32 bytes (ICACHE_LINE)
// a0: PI space address
// a1: DRAM address
// a2: Length
ReadSyncInvalidateIDCache:
  addi t0, a2, -ICACHE_LINE
  add t1, a1, t0

-
  cache inst_hit_invalidate, 0 (t1)
  addi t1, -ICACHE_LINE
  bnez t0,-
  addi t0, -ICACHE_LINE

// fall through

// Note: a1 and a2 should be aligned to 16 bytes (DCACHE_LINE)
// a0: PI space address
// a1: DRAM address
// a2: Length
ReadSyncInvalidateDCache:
  addi t0, a2, -DCACHE_LINE
  add t1, a1, t0

-
  cache data_hit_invalidate, 0 (t1)
  addi t1, -DCACHE_LINE
  bnez t0,-
  addi t0, -DCACHE_LINE

// fall through

// Note: Does not invalidate cache
// a0: PI space address
// a1: DRAM address
// a2: Length
ReadSync:
  lui t0, PI_BASE

pi_wait(t0, t1)

  sw a0, PI_CART_ADDR(t0)
  sw a1, PI_DRAM_ADDR(t0)
  addi t1, a2, -1
  sw t1, PI_WR_LEN(t0)

pi_wait(t0, t1)

  jr ra
  nop

}
