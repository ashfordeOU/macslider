.PHONY: build test app package run clean

build:
	swift build

test:
	swift test

app:
	scripts/build-app.sh

package: app
	scripts/package.sh

run: app
	open dist/Monorail.app

clean:
	rm -rf .build dist
