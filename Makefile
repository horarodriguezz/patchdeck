# Patchdeck — build from source on Fedora / Ubuntu.
PREFIX ?= $(HOME)/.local
BUNDLE  := build/linux/x64/release/bundle
FLUTTER ?= flutter

.PHONY: all deps build run test analyze install install-all uninstall clean

all: build

deps:
	./scripts/install-deps.sh

build:
	$(FLUTTER) pub get
	$(FLUTTER) build linux --release

run:
	$(FLUTTER) run -d linux

test:
	$(FLUTTER) test

analyze:
	$(FLUTTER) analyze

install:
	./scripts/install.sh --skip-deps --prefix "$(PREFIX)"

install-all:
	./scripts/install.sh

uninstall:
	./scripts/install.sh --uninstall --prefix "$(PREFIX)"

clean:
	$(FLUTTER) clean
