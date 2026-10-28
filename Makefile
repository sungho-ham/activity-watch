APP_NAME := awtoday
APP_BUNDLE := build/$(APP_NAME).app
EXECUTABLE := awtoday-popup
CONTENTS := $(APP_BUNDLE)/Contents
MACOS := $(CONTENTS)/MacOS
SOURCE := AwTodayPopup.swift $(wildcard Sources/*.swift)
SWIFT_FLAGS := -parse-as-library -target arm64-apple-macos13.0
.DEFAULT_GOAL := app

.PHONY: build app run open clean test live-check model-check previews install

build: build/$(EXECUTABLE)

build/$(EXECUTABLE): $(SOURCE)
	mkdir -p build
	swiftc $(SWIFT_FLAGS) $(SOURCE) -o $@

app: build/$(EXECUTABLE) Info.plist
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(MACOS)"
	cp build/$(EXECUTABLE) "$(MACOS)/$(EXECUTABLE)"
	cp Info.plist "$(CONTENTS)/Info.plist"
	codesign --force --sign - "$(APP_BUNDLE)"

test: build/core-tests
	build/core-tests

build/core-tests: Sources/TimeCore.swift Sources/ActivityWatchAPI.swift Sources/FileStore.swift Sources/PopupLayout.swift Tests/CoreTests.swift
	mkdir -p build
	swiftc $(SWIFT_FLAGS) $^ -o $@

live-check: build/core-tests
	build/core-tests --live

build/render-preview: $(wildcard Sources/*.swift) Tests/RenderPreview.swift
	mkdir -p build
	swiftc $(SWIFT_FLAGS) $^ -o $@

previews: build/render-preview
	build/render-preview build/previews

build/model-checks: Sources/TimeCore.swift Sources/ActivityWatchAPI.swift Sources/FileStore.swift Sources/PopupLayout.swift Sources/AppModel.swift Tests/ModelChecks.swift
	mkdir -p build
	swiftc $(SWIFT_FLAGS) $^ -o $@

model-check: build/model-checks
	build/model-checks

install: app
	bash Scripts/install.sh

run: app
	open "$(APP_BUNDLE)"

open: run

clean:
	rm -rf build
