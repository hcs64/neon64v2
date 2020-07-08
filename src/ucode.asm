// Memory layout and init for RSP

align(8)

// Initial DMEM (data)
InitialDMEM:
pushvar base
base 0
include "ucode_tables.asm"
print 4096-pc(), " bytes left in DMEM data\n"
pullvar base

// Active DMEM (bss)
pushvar base
pushvar origin
close_output_file()
base 0

fill resident_dmem_size

dmem_bss:

// Scheduler
// What to run on the CPU when this has finished (nothing if 0)
dmem_completion_vector:;  dw 0

constant ppu_rsp_task(0)
constant apu_rsp_task(1)

constant num_rsp_tasks(2)

dmem_cycle_counts:; fill 4*num_rsp_tasks
dmem_task_ras:; fill 2*num_rsp_tasks

dmem_no_work_count:; db 0
dmem_work_left:; db 0
align(4)
dmem_running_task:; db 0

align(4)
// PPU RDRAM adresses
dmem_src_pos:;    dw 0
dmem_dst_bg_pos:; dw 0
dmem_dst_sp_pos:; dw 0

// Interface with CPU for conv_src_buffer
dmem_conv_buf_read:; dw 0
dmem_conv_buf_write:; dw 0
dmem_frames_finished:; dw 0

dmem_which_framebuffer:; db 0

align(4)

// AI and alist FIFOs are designed to utilize num-3 buffers to simplify
// synchronization. When read == write, the buffer is empty and nothing can be
// read. When (write + 3) % num == read, the buffer is full and nothing can be
// written.
// An atomic write is done by the CPU or RSP to acquire or release a buffer.

// APU AI buffer vars
// Last buffer that has not yet been read by the AI, unless read==write.
// This is not necessarily the next one the AI interrupt will play, that is
// next_abuf_to_play.
dmem_abuf_read:;  dw 0
// Next buffer to be written by the SP.
dmem_abuf_write:; dw 0
// current byte position in the audio buffer in RDRAM
dmem_abuf_pos:;   dw 0
dmem_flush_abuf:;   dw 0

// APU alist buffer vars
dmem_alist_write:;  dw 0
dmem_alist_read:;   dw 0

align(8)
// alist entry buffer
dmem_alist_entry:
  fill alist_entry_size

// APU synthesis vars
align(4)
dmem_other:; dw 0
dmem_p1_timer:; dw 0
dmem_p2_timer:; dw 0
dmem_tri_timer:; dw 0
dmem_noise_timer:; dw 0
dmem_dmc_timer:; dw 0

dmem_abuf_samples_left:; dh 0
dmem_noise_reg:; dh 0

dmem_p1_phase:; db 0
dmem_p2_phase:; db 0
dmem_tri_phase:; db 0
dmem_dmc_level:; db 0
dmem_dmc_cur:; db 0

align(4)

align(16)
dmem_src:
  fill conv_src_size

align(16)
// Different things go in dmem_dst, but the expanded sprite lines are the largest
dmem_dst:
  fill 0x80 + conv_dst_sp_size

align(4)
dmem_bss_end:

print 4096-pc(), " bytes left in DMEM bss (PPU)\n"
if 4096-pc() < 0 {
  error "out of space in DMEM bss (PPU)"
}
print 4096-(dmem_dst+abuf_samples*4), " bytes left in DMEM bss (APU)\n"
if 4096-(dmem_dst+abuf_samples*4) < 0 {
  error "out of space in DMEM bss (APU)"
}

reopen_output_file()
pullvar origin
pullvar base

// IMEM
align(8)
scope Ucode: {

pushvar base
base 0x0000

arch n64.rsp
Boot:
-
  mfc0 t0, C0_DMA_FULL
  bnez t0,-
  nop

  mtc0 r0, C0_MEM_ADDR
  la a0, InitialDMEM
  mtc0 a0, C0_DRAM_ADDR
  lli t0, 0x1000-1
  mtc0 t0, C0_RD_LEN

-
  mfc0 t0, C0_DMA_BUSY
  bnez t0,-
  nop

// InitPPU needs to load values that would be overwritten by the bss init loop
  jal InitPPU
  nop

  lli t0, dmem_bss
  lli t1, dmem_bss_end-4
-
  sw r0, 0 (t0)
  bne t0, t1,-
  addi t0, 4

// InitAPU and InitPPU2 needsto write values into bss after it has been initialized
  jal InitAPU
  nop
  jal InitPPU2
  nop
  j InitScheduler
  nop

include "ucode_ppu.asm"
include "ucode_apu.asm"
include "ucode_scheduler.asm"

align(8)
print 4096-pc(), " bytes left in IMEM\n"
if 4096-pc() < 0 {
  error "out of space in IMEM"
}

pullvar base
End:
}
arch n64.cpu
align(4)
