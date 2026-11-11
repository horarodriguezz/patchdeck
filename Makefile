# Patchdeck — build from source on Fedora / Ubuntu.
PREFIX ?= $(HOME)/.local
APP_DIR := $(PREFIX)/lib/patchdeck
BIN_DIR := $(PREFIX)/bin
BUNDLE  := build/linux/x64/release/bundle
FLUTTER ?= flutter

.PHONY: all deps build run test analyze install uninstall clean

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

install: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)" "$(BIN_DIR)" "$(PREFIX)/share/applications" "$(PREFIX)/share/icons/hicolor/scalable/apps"
	cp -r $(BUNDLE)/. "$(APP_DIR)/"
	ln -sf "$(APP_DIR)/patchdeck" "$(BIN_DIR)/patchdeck"
	sed 's|@BINDIR@|$(BIN_DIR)|' linux/packaging/dev.patchdeck.Patchdeck.desktop > "$(PREFIX)/share/applications/dev.patchdeck.Patchdeck.desktop"
	cp linux/packaging/dev.patchdeck.Patchdeck.svg "$(PREFIX)/share/icons/hicolor/scalable/apps/"
	-update-desktop-database "$(PREFIX)/share/applications" 2>/dev/null
	@echo "Instalado en $(APP_DIR). Ejecuta: patchdeck"

uninstall:
	rm -rf "$(APP_DIR)" "$(BIN_DIR)/patchdeck" \
	  "$(PREFIX)/share/applications/dev.patchdeck.Patchdeck.desktop" \
	  "$(PREFIX)/share/icons/hicolor/scalable/apps/dev.patchdeck.Patchdeck.svg"

clean:
	$(FLUTTER) clean
