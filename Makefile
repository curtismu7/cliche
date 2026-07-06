.PHONY: build test app run install dist release clean

build:
	swift build

test:
	swift run cliche-selftest

app:
	Scripts/make-app.sh

run: app
	open build/Cliche.app

# Rebuild, replace ~/Applications/Cliche.app, and relaunch it.
install: app
	-pkill -f 'Cliche.app/Contents/MacOS/Cliche'
	sleep 1
	mkdir -p $(HOME)/Applications
	rm -rf /Applications/Cliche.app
	ditto build/Cliche.app $(HOME)/Applications/Cliche.app
	open $(HOME)/Applications/Cliche.app

# Shareable zip for other Macs (app + installer + readme).
dist:
	Scripts/make-dist.sh

# Bump VERSION, commit, then: tags + pushes + publishes a GitHub release.
release:
	Scripts/release.sh

clean:
	rm -rf .build build
