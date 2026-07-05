.PHONY: build test app run clean

build:
	swift build

test:
	swift run cliche-selftest

app:
	Scripts/make-app.sh

run: app
	open build/Cliche.app

clean:
	rm -rf .build build
