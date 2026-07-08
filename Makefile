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
	-pkill -f 'Cliche.app/Contents/MacOS/Cliche'
	sleep 1
	rm -rf $(HOME)/Applications/Cliche.app
	rm -rf $(INSTALL_PATH) || sudo rm -rf $(INSTALL_PATH)
	ditto build/Cliche.app $(INSTALL_PATH) || sudo ditto build/Cliche.app $(INSTALL_PATH)
	open $(INSTALL_PATH)

# Shareable zip for other Macs (app + installer + readme).
dist:
	Scripts/make-dist.sh

# Bump VERSION, commit, then: tags + pushes + publishes a GitHub release.
release:
	Scripts/release.sh

clean:
	rm -rf .build build
