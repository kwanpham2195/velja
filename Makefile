INSTALL_DIR ?= /Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

.PHONY: build test e2e app run install snapshots icon clean

## Debug build of every target.
build:
	swift build

## Unit tests for VeljaCore (works with only the Command Line Tools).
test:
	./scripts/test.sh

## End-to-end tests: the real app, real Launch Services, and a fake browser. See scripts/e2e.sh.
e2e:
	./scripts/e2e.sh

## Release app bundle at build/Velja.app.
app:
	./scripts/build-app.sh

## Build the app bundle and open it.
run: app
	open build/Velja.app

## Quit a running copy, replace $(INSTALL_DIR)/Velja.app, register it with Launch Services, and open it.
install: app
	-pkill -x Velja
	rm -rf "$(INSTALL_DIR)/Velja.app"
	ditto build/Velja.app "$(INSTALL_DIR)/Velja.app"
	"$(LSREGISTER)" -f "$(INSTALL_DIR)/Velja.app"
	open "$(INSTALL_DIR)/Velja.app"

## Render the settings tabs and the browser picker to /tmp/velja-snapshots (debug build only).
snapshots: build
	rm -rf /tmp/velja-snapshots
	.build/debug/Velja --ui-snapshots /tmp/velja-snapshots

## Regenerate Resources/AppIcon.icns from scripts/generate-app-icon.swift.
icon:
	./scripts/generate-app-icon.sh

clean:
	rm -rf .build build
