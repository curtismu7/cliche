.PHONY: build test app run install clean

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

clean:
	rm -rf .build build
