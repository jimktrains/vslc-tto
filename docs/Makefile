MD_SRC=$(wildcard src/*.md)

pdf: datasheet.pdf

datasheet.pdf: info.md
	cd ..; tt/tt_tool.py --print-warnings --create-pdf
	mv ../datasheet.* .

info.md: $(MD_SRC)
	mdbook build
	for i in book/*; do cat $$i >> info.md; echo "\n" >> info.md; done

clean:
	rm book/* info.md
