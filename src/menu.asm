constant max_menu_items(8)
constant exit_menu_flag(1)

scope Menu: {
Init:
  ls_gp(sh r0, prev_buttons)
  ls_gp(sb r0, profile_bars_enabled)
  ls_gp(sb r0, menu_enabled)
  jr ra
  nop

// a0: current buttons
ProcessButtons:
  addi sp, 8
  sw ra, -8 (sp)

  ls_gp(lhu t1, prev_buttons)
  srl t0, a0, 16
// Treat L&R (shoulder) together as a single button
  andi t2, t0, 0b0011'0000
  andi t0, 0b0011'0000^0xffff
  srl t3, t2, 1
  and t3, t2
  or t0, t3
  ls_gp(sh t0, prev_buttons)

// All released?
  bnez t0,+
  ls_gp(lbu t2, menu_exit_requested)
  beqz t2,+
  nop
  ls_gp(sb r0, menu_exit_requested)
  ls_gp(sb r0, menu_enabled)
+

// Find changes
  xor t1, t0
// Find newly-pressed
  and t1, t0
  beqz t1, presses_end
  nop

  ls_gp(lbu t2, menu_enabled)
  ls_gp(lbu t4, menu_item_count)
  beqz t2, in_menu_end
  ls_gp(lbu t3, selected_menu_item)

  andi t0, t1, 0x2400 // Down, Z (pseudo-select)
  beqz t0, not_down
  andi t0, t1, 0x800 // Up 

  addi t3, 1
  beql t3, t4,+
  lli t3, 0
+
  j presses_end
  ls_gp(sb t3, selected_menu_item)

not_down:
  beqz t0, not_up
  andi t0, t1, 0x9000 // A, Start, anything that looks like activation

  bnez t3,+
  subi t3, 1
  addi t3, t4, -1
+
  j presses_end
  ls_gp(sb t3, selected_menu_item)
not_up:

  beqz t0, not_activate
  nop
  sll t3, 3
  la_gp(t0, active_menu_items)
  add t0, t3

  lhu t1, 0 (t0) // flags
  andi t1, exit_menu_flag
  beqz t1,+
  lli t1, 1
  ls_gp(sb t1, menu_exit_requested)
+

// TODO it's going to be tricky to handle anything too complicated in here,
// I may want to make it simple to set flags.
  lh t1, 4 (t0) // procedure
  add t1, gp
  jr t1
  la_gp(ra, presses_end)

not_activate:

in_menu_end:
  andi t0, t1, 0x10 // L&R
  beqz t0, toggle_end
  ls_gp(lbu t0, menu_enabled)
  xori t0, 1

  beqz t0, toggle_end
  ls_gp(sb t0, menu_enabled)
  j BuildMain
  la_gp(ra, presses_end)
toggle_end:

presses_end:
  lw ra, -8 (sp)
  jr ra
  addi sp, -8

BuildMain:
  addi sp, 8
  sw ra, -8 (sp)

  jal StartBuild
  nop

  la_gp(t0, MainHeader)
  ls_gp(sw t0, menu_header_proc)

  jal AddItem
  la_gp(a0, dismiss_menu_item)

  ls_gp(lbu t0, flags6)
  andi t0, 0b10 // persistent memory present
  beqz t0,+
  nop
  jal AddItem
  la_gp(a0, save_ram_sram_menu_item)
+

  jal AddItem
  la_gp(a0, debug_menu_item)

  jal AddItem
  la_gp(a0, about_menu_item)

  jal FinishBuild
  nop

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

BuildDebug:
  addi sp, 8
  sw ra, -8 (sp)

  jal StartBuild
  nop

  la_gp(t0, DebugHeader)
  ls_gp(sw t0, menu_header_proc)

  jal AddItem
  la_gp(a0, debug_menu_back_item)

if {defined PROFILE_BARS} {
  jal AddItem
  la_gp(a0, toggle_profile_bars_menu_item)
}

  la_gp(t0, DebugFooter)
  ls_gp(sw t0, menu_footer_proc)

  jal FinishBuild
  nop

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

BuildAbout:
  addi sp, 8
  sw ra, -8 (sp)

  jal StartBuild
  nop

  la t0, (margin + (1 + 8*width)*8)*2
  ls_gp(sw t0, menu_fb_offset)

  la_gp(t0, AboutHeader)
  ls_gp(sw t0, menu_header_proc)

  jal AddItem
  la_gp(a0, ok_menu_item)

  jal FinishBuild
  nop

  ls_gp(sh r0, about_menu_scroll)

  lw ra, -8 (sp)
  jr ra
  addi sp, -8

Display:
  ls_gp(lbu t0, menu_enabled)
  bnez t0,+
  nop
  jr ra
  nop
+

  addi sp, 16
  sw ra, -16 (sp)

  jal ResetDebug
  nop

  ls_gp(lw t0, menu_header_proc)
  beqz t0,+
  nop
  jalr t0
  nop
+
  jal PrintStr0
  la_gp(a0, menu_frame_header_msg)

// assume at least one menu item
  lli t0, 0
-
  ls_gp(lbu t1, selected_menu_item)
  bne t0, t1,+
  la_gp(a0, not_selected_msg)
  la_gp(a0, selected_msg)
+
  jal PrintStr0
  sb t0, -8 (sp)

  lbu t0, -8 (sp)

  sll t0, 3
  la_gp(t1, active_menu_items)
  add t1, t0
  lh a0, 2 (t1) // message
  ls_gp(lbu a1, menu_min_width)
  jal PrintStr0Pad
  add a0, gp

  lbu t0, -8 (sp)
  ls_gp(lbu t1, selected_menu_item)
  bne t0, t1,+
  la_gp(a0, not_selected_end_msg)
  la_gp(a0, selected_end_msg)
+
  jal PrintStr0
  nop

  ls_gp(lbu t1, menu_item_count)
  lbu t0, -8 (sp)
  addi t0, 1
  bne t0, t1,-
  nop

  jal PrintStr0
  la_gp(a0, menu_frame_footer_msg)

  ls_gp(lw t0, menu_footer_proc)
  beqz t0,+
  nop
  jalr t0
  nop
+

  lui a0, VI_BASE
  lw a0, VI_ORIGIN (a0)
	ls_gp(lw t0, menu_fb_offset)
  add a0, t0
  lui t0, 0xa000
  or a0, t0
  jal VI.PrintDebugToScreen
  nop

  jal ResetDebug
  nop

  lw ra, -16 (sp)
  jr ra
  addi sp, -16

StartBuild:
  li t0, 10
  ls_gp(sb t0, menu_min_width)

  la t0, (margin + (4 + 8*width)*8)*2
	ls_gp(sw t0, menu_fb_offset)

  ls_gp(sw r0, menu_header_proc)
  ls_gp(sw r0, menu_footer_proc)
  ls_gp(sw r0, active_menu_items)
  jr ra
  ls_gp(sb r0, menu_item_count)

AddItem:
  ls_gp(lbu t1, menu_item_count)
  la_gp(t0, active_menu_items)
  ld t2, 0 (a0)
  sll t3, t1, 3
  add t0, t3
  sd t2, 0 (t0)
  addi t1, 1
  jr ra
  ls_gp(sb t1, menu_item_count)

FinishBuild:
  ls_gp(sb r0, menu_exit_requested)
  jr ra
  ls_gp(sb r0, selected_menu_item)

Stub:
  jr ra
  nop

ToggleProfileBars:
  ls_gp(lbu t0, profile_bars_enabled)
  xori t0, 1
  jr ra
  ls_gp(sb t0, profile_bars_enabled)

MainHeader:
// Tail call
  j PrintStr0
  la_gp(a0, startup_message)

AboutHeader:
  addi sp, 8
  sw ra, -8(sp)

  la_gp(a0, n64_header + 0x20)
  jal PrintStr0
  lli a1, 20

  jal PrintStr0
  la_gp(a0, copyright_message)

  ls_gp(lhu t1, about_menu_scroll)
  la_gp(a0, license_message)
  srl t1, 3
  add a0, t1

  jal PrintStr
  lli a1, 30

  jal PrintStr0
  la_gp(a0, newline)

  ls_gp(lhu t1, about_menu_scroll)
  addi t1, 1
  srl t2, t1, 3
  lli t0, license_message_end - license_message
  bne t2, t0,+
  nop
  lli t1, 0
+
  ls_gp(sh t1, about_menu_scroll)

  lw ra, -8(sp)
  jr ra
  addi sp, -8

DebugHeader:
// Tail call
  j PrintStr0
  la_gp(a0, debug_menu_header_msg)

DebugFooter:
// Tail call
  j PrintHeaderInfo
  nop
}

macro menu_item(name, msg, proc, flags) {
{name}:
  dh {flags}
  dh {msg} - gp_base
  dh {proc} - gp_base
  dh 0
}
align(8)
menu_item(ok_menu_item, ok_menu_msg, Menu.Stub, exit_menu_flag)
menu_item(dismiss_menu_item, dismiss_menu_msg, Menu.Stub, exit_menu_flag)
menu_item(save_ram_sram_menu_item, save_ram_sram_menu_msg, SaveExtraRAMToSRAM, exit_menu_flag)
menu_item(debug_menu_item, debug_menu_msg, Menu.BuildDebug, 0)

menu_item(debug_menu_back_item, back_msg, Menu.BuildMain, 0)
menu_item(toggle_profile_bars_menu_item, toggle_profile_bars_menu_msg, Menu.ToggleProfileBars, 0)
menu_item(about_menu_item, about_menu_msg, Menu.BuildAbout, 0)

constant ch_box_h(196)
constant ch_box_v(179)
constant ch_box_ur(191)
constant ch_box_dl(192)
constant ch_box_dr(217)
constant ch_box_ul(218)
constant ch_invert(255)

dismiss_menu_msg:
  db "Exit Menu",0
ok_menu_msg:
  db "OK",0
save_ram_sram_menu_msg:
  db "Save",0
debug_menu_msg:
  db "Debug...",0
about_menu_msg:
  db "About...",0
not_selected_msg:
  db ch_box_v, "    ",0
not_selected_end_msg:
  db ch_box_v,"\n",0
selected_msg:
  db ch_box_v, ch_invert, ">>> ", 0
selected_end_msg:
  db ch_invert,ch_box_v,"\n",0

menu_frame_header_msg:
  db ch_box_ul
  fill 10+4, ch_box_h
  db ch_box_ur,"\n",0

menu_frame_footer_msg:
  db ch_box_dl
  fill 10+4, ch_box_h
  db ch_box_dr,"\n",0

debug_menu_header_msg:
  db " Debug Menu     \n",0
back_msg:
  db "Back",0
toggle_profile_bars_menu_msg:
  db "Profile",0

align(4)

begin_bss()
align(8)
active_menu_items:; fill 8*max_menu_items

menu_header_proc:; dw 0
menu_footer_proc:; dw 0
menu_fb_offset:; dw 0

prev_buttons:; dh 0
about_menu_scroll:; dh 0

profile_bars_enabled:; db 0
menu_enabled:; db 0
menu_exit_requested:; db 0
menu_item_count:; db 0
menu_min_width:; db 0
selected_menu_item:; db 0
align(4)
end_bss()
