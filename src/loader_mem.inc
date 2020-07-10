constant NTSC_LOADER(0x8000'0400)
constant PAL_LOADER(0x8000'0800)
constant RESIDENT_BASE(0x8000'1000)

constant NTSC_ROM_OFFSET(0x4'0000) // 256K
constant PAL_ROM_OFFSET(0x8'0000) // 512K

if {defined NTSC_NES} {
  constant ROM_OFFSET(NTSC_ROM_OFFSET)
} else if {defined PAL_NES} {
  constant ROM_OFFSET(PAL_ROM_OFFSET)
}
