//define PRINT_OVL()
//define LOG_OVL()

// This is probably trickier than it has to be.

define OVL_BEGUN(0)
define OVL_OLD_OUTPUT_FILE()
define OVL_REGION_COUNT(0)
define OVL_COUNT(0)
variable OVL_BSS_START(0)
variable OVL_CUR_CODE_SIZE(0)
variable OVL_CUR_BSS_SIZE(0)

macro begin_overlay_region(label) {
  align_icache()

  global define OVL_BEGUN(0)
  global define OVL_OLD_OUTPUT_FILE({OUTPUT_FILE})
  global define OVL_REGION_LABEL({label})
  global variable OVL_CODE_START(pc())
  global variable OVL_BSS_START(bss_pc)
  global variable OVL_CODE_SIZE(0)
  global variable OVL_BSS_SIZE(0)
}
macro begin_overlay(label) {
  if {OVL_BEGUN} == 1 {
    end_overlay()
  }
  pushvar origin
  pushvar base
  global define OUTPUT_FILE("OVL_{OVL_REGION_LABEL}_{label}.bin")
  define local_label({OVL_REGION_LABEL})
  global define OVL_FILES_{OVL_COUNT}("OVL_{OVL_REGION_LABEL}_{label}.bin")
  global evaluate OVL_CODE_STARTS_{OVL_COUNT}(OVL_CODE_START)
  global define OVL_INDEX_{OVL_REGION_LABEL}_{label}({OVL_COUNT})

  output {OUTPUT_FILE}
  origin 0
  base OVL_CODE_START

  global define OVL_BEGUN(1)
}

macro end_overlay() {
  if {OVL_BEGUN} != 1 {
    error "end when not begun"
  }

  align_file(ICACHE_LINE)

  if origin() > OVL_CODE_SIZE {
    global variable OVL_CODE_SIZE(origin())
  }
  if bss_pc - OVL_BSS_START > OVL_BSS_SIZE {
    global variable OVL_BSS_SIZE(bss_pc - OVL_BSS_START)
  }

  global evaluate OVL_CODE_SIZES_{OVL_COUNT}(origin())

  global define OUTPUT_FILE({OVL_OLD_OUTPUT_FILE})
  output {OVL_OLD_OUTPUT_FILE}
  pullvar base
  pullvar origin
  global variable bss_pc(OVL_BSS_START)

  global evaluate OVL_COUNT({OVL_COUNT}+1)

  global define OVL_BEGUN(0)
}

macro end_overlay_region() {
  if {OVL_BEGUN} == 1 {
    end_overlay()
  }
  if {defined PRINT_OVL} {
    print "Overlay region "{OVL_REGION_LABEL}": "
    print "code @",pc()," size=",OVL_CODE_SIZE,", bss @",bss_pc," size=",OVL_BSS_SIZE,"\n"
  }

{OVL_REGION_LABEL}:
  fill OVL_CODE_SIZE, 0

begin_bss()
  fill OVL_BSS_SIZE
end_bss()

  global evaluate OVL_REGION_COUNT({OVL_REGION_COUNT}+1)
}

macro emit_overlays() {
  evaluate _rep_i(0)
  while {_rep_i} < {OVL_COUNT} {
    // TODO: I think alignment for PI DMA is only really 2 on the cartbus side?
    align(8)

    // HACK file sizes are 0 on an early pass?
    evaluate ovl_end_origin(origin() + {OVL_CODE_SIZES_{_rep_i}})
OVL_LABELS_{_rep_i}:
    insert {OVL_FILES_{_rep_i}}

    origin {ovl_end_origin}

    evaluate _rep_i({_rep_i}+1)
  }
}

macro load_overlay_from_rom(region_label, overlay_label) {
  if {defined PRINT_OVL} {
    print "loading overlay {region_label}_{overlay_label}, index ", {OVL_INDEX_{region_label}_{overlay_label}}, "\n"
  }
  jal LoadOverlay
  lli a0, {OVL_INDEX_{region_label}_{overlay_label}}
}

// a0: index
LoadOverlay:
if {defined LOG_OVL} {
  addi sp, 16
  sw a0, -8 (sp)
  sw ra, -16 (sp)

  jal PrintHex
  lli a1, 2

  lw a0, -8 (sp)
  sll t0, a0, 2
  add t0, gp
  lw a0, overlay_code_index_rom_addrs - gp_base (t0)
  jal PrintHex
  lli a1, 8

  lw a0, -8 (sp)
  sll t0, a0, 2
  add t0, gp
  lw a0, overlay_code_index_ram_addrs - gp_base (t0)
  jal PrintHex
  lli a1, 8

  lw a0, -8 (sp)
  sll t0, a0, 1
  add t0, gp
  lhu a0, overlay_code_index_sizes - gp_base (t0)
  jal PrintHex
  lli a1, 4

  jal NewlineAndFlushDebug
  nop

  lw a0, -8 (sp)
  lw ra, -16 (sp)
  addi sp, -16
}

  sll t0, a0, 2
  sll t1, a0, 1
  add t0, gp
  add t1, gp
  lw a0, overlay_code_index_rom_addrs - gp_base (t0)
  lw a1, overlay_code_index_ram_addrs - gp_base (t0)
// Tail call
  j PI.ReadSyncInvalidateIDCache
  lhu a2, overlay_code_index_sizes - gp_base (t1)

macro emit_overlay_index() {
overlay_code_index_ram_addrs:
evaluate _rep_i(0)
while {_rep_i} < {OVL_COUNT} {
  dw {OVL_CODE_STARTS_{_rep_i}}
  evaluate _rep_i({_rep_i}+1)
}

overlay_code_index_rom_addrs:
evaluate _rep_i(0)
while {_rep_i} < {OVL_COUNT} {
  dw OVL_LABELS_{_rep_i}
  evaluate _rep_i({_rep_i}+1)
}

overlay_code_index_sizes:
evaluate _rep_i(0)
while {_rep_i} < {OVL_COUNT} {
  dh {OVL_CODE_SIZES_{_rep_i}}
  evaluate _rep_i({_rep_i}+1)
}
}

align(4)
