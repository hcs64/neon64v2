.PHONY: all loader pkg clean clean-tools clean-all

TOOLS=tools/chksum64 tools/bass

# Path relative to src/
BASS=../tools/bass
CHKSUM64=./tools/chksum64

ERR_EMBED=-d 'ERR_EMBED1=../pkg/roms/nestify7.nes' -d 'ERR_EMBED2=../pkg/roms/efp6.nes'
NTSC_BIN=MODE_NTSC.bin
RESIDENT_BASE=0x80001000
NTSC_ROM_OFFSET=0x40000
PAL_BIN=MODE_PAL.bin
PAL_ROM_OFFSET=0x80000
NTSC_BASS_CMD=$(BASS) neon64.asm -d 'NTSC_NES=1' -d 'ROM_OFFSET=$(NTSC_ROM_OFFSET)' -d 'RESIDENT_BASE=$(RESIDENT_BASE)' $(ERR_EMBED) -d 'OUTPUT_FILE=$(NTSC_BIN)'
PAL_BASS_CMD=$(BASS) neon64.asm -d 'PAL_NES=1' -d 'ROM_OFFSET=$(PAL_ROM_OFFSET)' -d 'RESIDENT_BASE=$(RESIDENT_BASE)' -d 'OUTPUT_FILE=$(PAL_BIN)'
LOADER_BASS_CMD=$(BASS) src/loader.asm -d 'NTSC_BIN=$(NTSC_BIN)' -d 'NTSC_ROM_OFFSET=$(NTSC_ROM_OFFSET)' -d 'PAL_BIN=$(PAL_BIN)' -d 'PAL_ROM_OFFSET=$(PAL_ROM_OFFSET)' -d 'RESIDENT_BASE=$(RESIDENT_BASE)' -o neon64bu.rom

loader: $(TOOLS)
	rm -f src/OVL_*.bin
	cd src ; $(NTSC_BASS_CMD) -sym ntsc.sym
	rm -f src/OVL_*.bin
	cd src ; $(PAL_BASS_CMD) -sym pal.sym
	rm -f src/OVL_*.bin
	./src/$(LOADER_BASS_CMD)
	$(CHKSUM64) neon64bu.rom

all: loader

clean-all: clean clean-tools
	rm -f neon64bu.rom

pkg: ntsc pal
	zip --junk-paths neon64v2XXXX.zip pkg/README.txt LICENSE.txt neon64bu.rom neon64bu_pal.rom

clean:
	rm -f src/MODE_NTSC.bin src/MODE_PAL.bin src/ntsc.sym src/pal.sym src/OVL_*.bin neon64v2XXXX.zip || true

tools/chksum64: tools/chksum64.c

tools/bass:
	git submodule init
	git submodule update
	$(MAKE) -C tools/bass-src/bass/
	cp tools/bass-src/bass/bass tools/bass

clean-tools:
	rm -f tools/chksum64 tools/bass
	$(MAKE) -C tools/bass-src/bass/ clean
