.PHONY: all ntsc ntsc_sym pal pkg clean clean-tools clean-all

TOOLS=tools/chksum64 tools/bass

# Path relative to src/
BASS=../tools/bass
CHKSUM64=./tools/chksum64

ERR_EMBED=-d 'ERR_EMBED1=../pkg/roms/nestify7.nes' -d 'ERR_EMBED2=../pkg/roms/efp6.nes'
NTSC_BASS_CMD=$(BASS) neon64.asm -d 'NTSC_NES=1' $(ERR_EMBED) -d 'OUTPUT_FILE=../neon64bu.rom'

ntsc: $(TOOLS)
	rm -f src/OVL_*.bin
	cd src ; $(NTSC_BASS_CMD)
	$(CHKSUM64) neon64bu.rom

ntsc-sym:
	rm -f src/OVL_*.bin
	cd src ; $(NTSC_BASS_CMD) -sym neon64.sym
	$(CHKSUM64) neon64bu.rom
	sort src/neon64.sym > src/neon64.sym.sorted
	mv src/neon64.sym.sorted src/neon64.sym

all: ntsc pal

clean-all: clean clean-tools

pal: $(TOOLS)
	rm -f src/OVL_*.bin
	cd src ; $(BASS) neon64.asm -d 'PAL_NES=1' -d 'OUTPUT_FILE=../neon64bu_pal.rom'
	$(CHKSUM64) neon64bu_pal.rom

pkg: ntsc pal
	zip --junk-paths neon64v2XXXX.zip pkg/README.txt LICENSE.txt neon64bu.rom neon64bu_pal.rom

clean:
	rm -f neon64bu.rom neon64bu_pal.rom src/neon64.sym src/OVL_*.bin neon64v2XXXX.zip || true

tools/chksum64: tools/chksum64.c

tools/bass:
	git submodule init
	git submodule update
	$(MAKE) -C tools/bass-src/bass/
	cp tools/bass-src/bass/bass tools/bass

clean-tools:
	rm -f tools/chksum64 tools/bass
	$(MAKE) -C tools/bass-src/bass/ clean
