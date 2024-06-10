scope TLB {
Init:
// Set TLB to known state
// Initially set all pages invalid global, 512K from 0x40'0000
  mtc0 r0, PageMask // 4K pages (in pairs)
  lli t0, 1
  mtc0 t0, EntryLo0
  mtc0 t0, EntryLo1
  scope {
    constant hi_addr(t0)
    constant count(t1)
    constant index(t2)

    la hi_addr, 0x40'0000
    lli count, 32
    lli index, 0
-;  mtc0 index, Index
    mtc0 hi_addr, EntryHi
// tlbwi hazard with mtc0 EntryHi: 7-(5+1) = 1, one addi should be enough
    addi count, -1
    addi index, 1
    tlbwi
    bnez count,-
    addi hi_addr, 1<<13 // VPN2 += 8k
  }

// TLB index 0
// Low page (0-8k)
  mtc0 r0, PageMask // 4K pages (in pairs)
  mtc0 r0, Index
  lli t0, low_page_base
  mtc0 t0, EntryHi
// First page of pair
// Cached (5-3), writeable (dirty, 2), valid (1), global (0)
  la t0, ((low_page_ram_base >> 12) << 6) | (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo0
// Second page of pair
// Cached (5-3), writeable (dirty, 2), valid (1), global (0)
  la t0, (((low_page_ram_base + tlb_page_size) >> 12) << 6) | (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo1
  nop // tlbwi hazard with mtc0 EntryLo1, 7-(5+1) = 1
  tlbwi

// TLB index 1
// Non-negative address space for all of RDRAM (8MB-16MB)
  la t0, (0x80'0000-1)&0x1ff'e000 // Mask is 24-13
  mtc0 t0, PageMask
  lli t0, 1
  mtc0 t0, Index
// Starts at 8MB
  la t0, tlb_rdram
  mtc0 t0, EntryHi
// First page of pair, 0, cached, writeable, valid, global
  la t0, (0 << 6) | (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo0
// Second page of pair, 4MB
  la t0, ((0x40'0000 >> 12) << 6) | (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo1
  nop // tlbwi hazard with mtc0 EntryLo1
  tlbwi

// TLB index 2
// Non-negative, read-only address space for all of RDRAM (16MB-24MB)
  la t0, (0x80'0000-1)&0x1ff'e000 // Mask is 24-13
  mtc0 t0, PageMask
  lli t0, 1
  mtc0 t0, Index
// Starts at 16MB
  la t0, tlb_ro_rdram
  mtc0 t0, EntryHi
// First page of pair, 0, not dirty = not writeable, cached, valid, global
  la t0, (0 << 6) | (%011 << 3) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo0
// Second page of pair, 4MB
  la t0, ((0x40'0000 >> 12) << 6) | (%011 << 3) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo1
  nop // tlbwi hazard with mtc0 EntryLo1
  tlbwi

// Allow for dynamic allocation later
  lli t0, 3
  ls_gp(sw t0, next_tlb_index)

  la t0, tlb_free
  jr ra
  ls_gp(sw t0, next_tlb_vaddr)

// Input:
//   a0: alignment
// Output:
//   a0: Vaddr
//   a1: TLB entry index to use (pre-loaded into cop0 Index)
// Align the virtual address, and leave that much space again for the next one.
// Also reserves the TLB entry index, this is left in a1 and written to cop0 Index.
AllocateVaddr:
  ls_gp(lwu a1, next_tlb_index)
  ls_gp(lwu t0, next_tlb_vaddr)
  mtc0 a1, Index
  addiu t1, a1, 1
  ls_gp(sw t1, next_tlb_index)

  move t1, a0 // save alignment in t1 as we will reuse a0
  addiu t2, t1, -1  // alignment-1, remainder mask
  addu a0, t0, t2   // vaddr+alignment-1
  and t2, a0        // mask out remainder
  xor a0, t2        // round down for current address
  add t2, a0, t1    // round up for next addres

  jr ra
  ls_gp(sw t2, next_tlb_vaddr)

// TODO should interrupts be masked while updating mappings so the cop0 regs don't get mussed?

// All args will be preserved in Map*

// Note: The Map* routines protect a caller's load/store from a potential TLB
// hazard with tlbwi. This requires 8 - (4+1) = 3 instructions before the next
// load/store TLB use. Experimentally just using `tlbwi; jr ra; nop` is
// sufficient, but for safety, and because this is hell to debug when it comes
// up, a full 3 instructions are interposed here: `tlbwi; nop; jr ra; nop`
//
// WARNING: 5 instructions are needed before an instruction fetch can use the
// TLB, so it will not be safe to return from Map* to e.g. TLB index 1 or 2
// (mapped above). This isn't an issue yet because the TLB is not used for MIPS
// instructions.

// Maps one 4K page, only first half of pair is used
// Index: TLB entry index
// a0: virtual address (8K aligned)
// a1: physical address (4K aligned)
Map4K:
  mtc0 r0, PageMask // No bits are masked for 4K
  mtc0 a0, EntryHi
// Low page of pair, cached, writeable, valid, global
  srl t0, a1, 12-6
  ori t0, (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo0
// High page of pair, invalid global
  lli t0, (1 << 0)
  mtc0 t0, EntryLo1
  nop   // tlbwi hazard with mtc0 EntryLo1
  tlbwi
  nop   // Load/Store hazard 1
  jr ra // " 2
  nop   // " 3

// Maps two 4K pages
// Index: TLB entry index
// a0: virtual address (8K aligned)
// a1: physical address 0 (4K aligned)
// a2: physical address 1 (for Map4K_2, 4K aligned)
Map8K:
  addi a2, a1, 0x1000
Map4K_2:
  mtc0 r0, PageMask // No bits are masked for 4K
  mtc0 a0, EntryHi
// Low page of pair, cached, writeable, valid, global
  srl t0, a1, 12-6
  ori t0, (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo0
// High page of pair,cached, writeable, valid, global
  srl t0, a2, 12-6
  ori t0, (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo1
  nop   // tlbwi hazard with mtc0 EntryLo1
  tlbwi
  nop   // Load/Store hazard 1
  jr ra // " 2
  nop   // " 3

// Maps one 16K page, only first half of pair is used
// a0: virtual address (32K aligned)
// a1: physical address (4K aligned?)
// Index: TLB entry index
Map16K:
  lli t0, (0x8000-1)&0x1ff'e000 // Mask is 24-13
  mtc0 t0, PageMask
  mtc0 a0, EntryHi
// Low page of pair, cached, writeable, valid, global
  srl t0, a1, 12-6
  ori t0, (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo0
// High page of pair, invalid global
  lli t0, (1 << 0)
  mtc0 t0, EntryLo1
  nop   // tlbwi hazard with mtc0 EntryLo1
  tlbwi
  nop   // Load/Store hazard 1
  jr ra // " 2
  nop   // " 3

// Map two 16K pages
// a0: virtual address (32K aligned)
// a1: physical address 0 (4K aligned?)
// a2: physical address 1 (for Map16K_2, 4K aligned?)
// Index: TLB entry index
Map32K:
  addi a2, a1, 0x4000
Map16K_2:
  lli t0, (0x8000-1)&0x1ff'e000 // Mask is 24-13
  mtc0 t0, PageMask
  mtc0 a0, EntryHi
// Low page of pair, cached, writeable, valid, global
  srl t0, a1, 12-6
  ori t0, (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo0
// High page of pair, cached, writeable, valid, global
  srl t0, a2, 12-6
  ori t0, (%011 << 3) | (1 << 2) | (1 << 1) | (1 << 0)
  mtc0 t0, EntryLo1
  nop   // tlbwi hazard with mtc0 EntryLo1
  tlbwi
  nop   // Load/Store hazard 1
  jr ra // " 2
  nop   // " 3

}

begin_bss()
next_tlb_vaddr:
  dw 0
next_tlb_index:
  dw 0
end_bss()
