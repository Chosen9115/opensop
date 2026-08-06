# Makefile — regenerate the C2 comparison video from demo.sh
# Usage: make demo
#
# Prerequisites:
#   pip install --user --break-system-packages asciinema
#   cargo install --git https://github.com/asciinema/agg agg
#   ffmpeg (via system package manager)

DEMO_DIR   := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
CAST       := $(DEMO_DIR)comparison.cast
GIF        := $(DEMO_DIR)comparison.gif
MP4        := $(DEMO_DIR)comparison.mp4
DEMO_SH    := $(DEMO_DIR)demo.sh
FRAMES_DIR := $(DEMO_DIR)frames
AGG        := $(shell which agg 2>/dev/null || echo $(HOME)/.cargo/bin/agg)

.PHONY: demo gif mp4 frames clean

## demo: full pipeline — record cast, render gif, export mp4, extract frames
demo: gif mp4 frames

## cast: (re)record the asciinema cast from demo.sh
$(CAST): $(DEMO_SH)
	asciinema rec --overwrite --cols 100 --rows 32 \
	  -c "bash $(DEMO_SH)" \
	  $(CAST)

cast: $(CAST)

## gif: render the cast to an animated GIF (0.5x speed = ~50s from ~25s cast)
$(GIF): $(CAST)
	$(AGG) \
	  --cols 100 --rows 32 \
	  --font-size 16 \
	  --speed 0.5 \
	  $(CAST) $(GIF)

gif: $(GIF)

## mp4: convert GIF to MP4 for embed use
$(MP4): $(GIF)
	ffmpeg -y -i $(GIF) \
	  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
	  -c:v libx264 -pix_fmt yuv420p -movflags +faststart \
	  $(MP4)

mp4: $(MP4)

## frames: extract 3 still PNGs for reviewer preview
frames: $(GIF)
	@mkdir -p $(FRAMES_DIR)
	ffmpeg -y -i $(GIF) -vf "select=eq(n\,2)"  -vframes 1 -q:v 2 $(FRAMES_DIR)/frame03.png 2>/dev/null
	ffmpeg -y -i $(GIF) -vf "select=eq(n\,16)" -vframes 1 -q:v 2 $(FRAMES_DIR)/frame17.png 2>/dev/null
	ffmpeg -y -i $(GIF) -vf "select=eq(n\,29)" -vframes 1 -q:v 2 $(FRAMES_DIR)/frame30.png 2>/dev/null

## clean: remove rendered artifacts (keeps demo.sh and comparison.cast)
clean:
	rm -f $(GIF) $(MP4) $(FRAMES_DIR)/*.png

## help: show this help
help:
	@grep -E '^##' $(MAKEFILE_LIST) | sed 's/^## //'
