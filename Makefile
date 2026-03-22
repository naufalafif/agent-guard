.PHONY: build run release clean lint format check

APP_NAME := AgentGuard
APP_BUNDLE := $(APP_NAME).app
BUILD_DIR := .build/release
DIST_DIR := dist

# --- Build ---

build:
	swift build

release:
	swift build -c release
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP_BUNDLE)/Contents/
	codesign --force --sign - $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

run: build
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp .build/debug/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP_BUNDLE)/Contents/
	killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.5
	open $(APP_BUNDLE)

# --- Release packaging ---

dist: release
	mkdir -p $(DIST_DIR)
	ditto -c -k --sequesterRsrc --keepParent $(APP_BUNDLE) $(DIST_DIR)/$(APP_NAME).zip
	@echo "Packaged $(DIST_DIR)/$(APP_NAME).zip"

# --- Quality ---

lint:
	@echo "--- SwiftLint ---"
	@if command -v swiftlint >/dev/null; then \
		swiftlint lint --strict Sources/; \
	else \
		echo "swiftlint not installed (brew install swiftlint)"; \
	fi

format:
	@echo "--- swift-format ---"
	@if command -v swift-format >/dev/null; then \
		swift-format format --in-place --recursive Sources/; \
	else \
		echo "swift-format not installed (brew install swift-format)"; \
	fi

format-check:
	@echo "--- swift-format check ---"
	@swift-format lint --strict --recursive Sources/

check: build lint format-check
	@echo "All checks passed"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) $(DIST_DIR)
