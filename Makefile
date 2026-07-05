.PHONY: build test app run install dist clean

build:
	swift build

test:
	swift run cliche-selftest

app:
	Scripts/make-app.sh

run: app
	open build/Cliche.app

# Rebuild, replace the installed copy, and relaunch it.
install: app
	-pkill -f 'Cliche.app/Contents/MacOS/Cliche'
	sleep 1
	ditto build/Cliche.app ~/Applications/Cliche.app
	open ~/Applications/Cliche.app

# Shareable zip for other Macs (app + installer + readme).
dist:
	Scripts/make-dist.sh

clean:
	rm -rf .build build
