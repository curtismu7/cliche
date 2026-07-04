.PHONY: build test app run clean

build:
	swift build

test:
	swift run clipshot-selftest

app:
	Scripts/make-app.sh

run: app
	open build/ClipShot.app

clean:
	rm -rf .build build
