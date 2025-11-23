# Gas Meter Digit Recognition Makefile
#
# Usage: make           - process all 370*.png files
#        make INPUT=x.png - process a single file
# Output: .txt files with recognized digits

# Digit crop positions (x, y, width, height)
DIGIT1_POS = 370 1350 150 200
DIGIT2_POS = 620 1350 150 200
DIGIT3_POS = 870 1350 150 200
DIGIT4_POS = 1110 1350 150 200
DIGIT5_POS = 1360 1350 150 200
DIGIT6_POS = 1620 1350 150 200
DIGIT7_POS = 1860 1350 150 200
DIGIT8_POS = 2130 1350 150 200

TEMPLATE_DIR = templates
CROP = opam exec -- dune exec -- ./crop_image.exe
RECOGNIZE = opam exec -- dune exec -- ./recognize.exe

# Find all 370*.png files and derive output .txt files
INPUTS = $(wildcard 370*.png)
OUTPUTS = $(INPUTS:.png=.txt)

# Temp directory for cropped digits
TMPDIR = tmp_digits

.PHONY: all clean build

all: build $(OUTPUTS)

build:
	opam exec -- dune build ./crop_image.exe ./recognize.exe

# Pattern rule to process any .png into .txt
%.txt: %.png | $(TMPDIR)
	@echo "Processing $<..."
	@# Crop all 8 digits
	@$(CROP) $< $(DIGIT1_POS) $(TMPDIR)/d1.png
	@$(CROP) $< $(DIGIT2_POS) $(TMPDIR)/d2.png
	@$(CROP) $< $(DIGIT3_POS) $(TMPDIR)/d3.png
	@$(CROP) $< $(DIGIT4_POS) $(TMPDIR)/d4.png
	@$(CROP) $< $(DIGIT5_POS) $(TMPDIR)/d5.png
	@$(CROP) $< $(DIGIT6_POS) $(TMPDIR)/d6.png
	@$(CROP) $< $(DIGIT7_POS) $(TMPDIR)/d7.png
	@$(CROP) $< $(DIGIT8_POS) $(TMPDIR)/d8.png
	@# Recognize each digit and combine results
	@( \
		for i in 1 2 3 4 5 6 7 8; do \
			$(RECOGNIZE) $(TEMPLATE_DIR) $(TMPDIR)/d$$i.png 2>/dev/null | \
			grep "Recognized:" | sed 's/Recognized: \(.\).*/\1/' | tr -d '\n'; \
		done; \
		echo \
	) > $@
	@echo "Result: $$(cat $@)"

$(TMPDIR):
	@mkdir -p $(TMPDIR)

clean:
	rm -rf $(TMPDIR) *.txt
