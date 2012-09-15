.PHONY: clean

SHELL := /bin/bash
pkgIndex.tcl: *.exp *.tcl
	@echo 'pkg_mkIndex -verbose ./ *.exp *.tcl' | tee >(tclsh) | cat

*.exp:
*.tcl:

clean:
	-rm -f pkgIndex.tcl
