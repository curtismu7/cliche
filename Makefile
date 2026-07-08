.PHONY: build test app run install dist release clean

build:
	swift build

test:
	swift run cliche-selftest

app:
	Scripts/make-app.sh

run: app
	open build/Cliche.app

# Rebuild, replace /Applications/Cliche.app, and relaunch it.
INSTALL_PATH := /Applications/Cliche.app

install: app
	Scripts/install-cleanup.sh
	ditto build/Cliche.app $(INSTALL_PATH) || sudo ditto build/Cliche.app $(INSTALL_PATH)
	xattr -dr com.apple.quarantine $(INSTALL_PATH) 2>/dev/null || true
	open $(INSTALL_PATH)
	Scripts/postinstall-hint.sh

# Shareable zip for other Macs (app + installer + readme).
dist:
	Scripts/make-dist.sh

# Bump VERSION, commit, then: tags + pushes + publishes a GitHub release.
release:
	Scripts/release.sh

clean:
	rm -rf .build build
