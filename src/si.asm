// TODO Controller detection
scope SI {

Init:
  jr ra
  ls_gp(sw r0, si_completion_vector)

Interrupt:
  ls_gp(lw k0, si_completion_vector)
  beqz k0,+
  ls_gp(sw r0, si_completion_vector)

  ls_gp(sd a0, exception_regs + a0*8)
  ls_gp(sd a1, exception_regs + a1*8)
  ls_gp(sd a2, exception_regs + a2*8)
  ls_gp(sd t0, exception_regs + t0*8)
  ls_gp(sd ra, exception_regs + ra*8)

// Schedule to run in the interrupt task
  ls_gp(sw k0, si_callback)

  lli a0, 0 // Run immediately
  la_gp(a1, IntCallbackTask)
  jal Scheduler.ScheduleTask
  lli a2, int_cb_task

  ls_gp(ld a0, exception_regs + a0*8)
  ls_gp(ld a1, exception_regs + a1*8)
  ls_gp(ld a2, exception_regs + a2*8)
  ls_gp(ld t0, exception_regs + t0*8)
  ls_gp(ld ra, exception_regs + ra*8)
+
  jr k1
  nop

StartReadControllers:
  la_gp(t1, read_con_commands)
  cache data_hit_write_back, 0x00 (t1)
  cache data_hit_write_back, 0x10 (t1)
  cache data_hit_write_back, 0x20 (t1)
  cache data_hit_write_back, 0x30 (t1)

  lui t0, SI_BASE
-
  lw t1, SI_STATUS (t0)
  andi t1, 0b11 // DMA or I/O busy
  bnez t1,-
  nop

  la t1, read_con_commands&0x1fff'ffff
  sw t1, SI_DRAM_ADDR (t0)
  lui t1, PIF_BASE & 0x1fff
  ori t1, PIF_RAM
  sw t1, SI_PIF_ADDR_WR64B (t0)

  jr ra
  nop

// Does not wait for results
ReadBackControllers:
  la_gp(t1, read_con_buf)
  cache data_hit_invalidate, 0x00 (t1)
  cache data_hit_invalidate, 0x10 (t1)
  cache data_hit_invalidate, 0x20 (t1)
  cache data_hit_invalidate, 0x30 (t1)

  lui t0, SI_BASE
-
  lw t1, SI_STATUS (t0)
  andi t1, 0b11 // DMA or I/O busy
  bnez t1,-
  nop

  la t1, read_con_buf&0x1fff'ffff
  sw t1, SI_DRAM_ADDR (t0)
  lui t1, PIF_BASE & 0x1fff
  ori t1, PIF_RAM
  jr ra
  sw t1, SI_PIF_ADDR_RD64B (t0)

ExecPIF:
// a0: block to execute
// a1: destination for result
// TODO wait for idle?
  lui t0, SI_BASE

  cache data_hit_write_back, 0x00 (a0)
  cache data_hit_write_back, 0x10 (a0)
  cache data_hit_write_back, 0x20 (a0)
  cache data_hit_write_back, 0x30 (a0)

  lui t2, 0x1fff
  ori t2, 0xffff
  and a0, t2

  lui t1, PIF_BASE & 0x1fff
  ori t1, PIF_RAM
  sw a0, SI_DRAM_ADDR (t0)
  sw t1, SI_PIF_ADDR_WR64B (t0)

  cache data_hit_invalidate, 0x00 (a1)
  cache data_hit_invalidate, 0x10 (a1)
  cache data_hit_invalidate, 0x20 (a1)
  cache data_hit_invalidate, 0x30 (a1)

-
  lw t3, SI_STATUS (t0)
  andi t3, 0b11 // DMA or I/O busy
  bnez t3,-
  nop
  
  and a1, t2
  sw a1, SI_DRAM_ADDR (t0)
  sw t1, SI_PIF_ADDR_RD64B (t0)

-
  lw t3, SI_STATUS (t0)
  andi t3, 0b11
  bnez t3,-
  nop

  jr ra
  nop
}

align_dcache()
align(8)
read_con_commands:
  dw      0xff010401,0xffffffff
  dw      0xff010401,0xffffffff
  dw      0xfe000000,0
  dw      0,0
  dw      0,0
  dw      0,0
  dw      0,0
  dw      0,1
align_dcache()

begin_bss()
si_completion_vector:; dw 0
align_dcache()
read_con_buf:
  fill 64
align_dcache()
end_bss()
