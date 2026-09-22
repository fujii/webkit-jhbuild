# Convenience wrappers around jhbuild for this moduleset.

JHBUILD := jhbuild
JH_BUILDRC := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))jhbuildrc
TOP_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: all build clean list requirements

all: build

build:
	$(JHBUILD) -f $(JH_BUILDRC) --no-interact build

# `jhbuild clean` only runs `ninja clean` per module and errors on modules whose
# build directory does not exist, so remove the build dirs outright instead.
clean:
	rm -rf $(TOP_DIR)build $(TOP_DIR)install

list:
	$(JHBUILD) -f $(JH_BUILDRC) list

requirements:
	./install-requirements-dnf
