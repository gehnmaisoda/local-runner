VERSION := $(shell cat VERSION)
DEV_FLAGS = -Xswiftc -DDEV

.PHONY: daemon web test clean install sync-version dist

# Generate Version.swift from VERSION file
sync-version:
	@echo 'public enum AppVersion { public static let current = "$(VERSION)" }' \
		> daemon/Sources/Core/Version.swift

# Run daemon in foreground (for development)
daemon: sync-version
	-@pkill -f 'local-runner$$' 2>/dev/null || true
	cd daemon && swift build $(DEV_FLAGS)
	daemon/.build/debug/local-runner

# Open Web UI in browser (dev mode — connects to dev daemon)
web:
	cd cli && LOCAL_RUNNER_DEV=1 bun run index.ts

# Run tests
test: sync-version
	cd daemon && swift test

# Build daemon release binary
build: sync-version
	cd daemon && swift build -c release

# Build CLI single binary
cli-build:
	cd cli && bun build --compile index.ts --outfile lr \
		--define '__EMBEDDED_VERSION__="$(VERSION)"'

# Build release archive for distribution
dist: build cli-build
	mkdir -p dist/LocalRunner.app/Contents/MacOS
	cp daemon/.build/release/local-runner dist/LocalRunner.app/Contents/MacOS/local-runnerd
	printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0">\n\
<dict>\n\
    <key>CFBundleDisplayName</key>\n\
    <string>Local Runner</string>\n\
    <key>CFBundleName</key>\n\
    <string>Local Runner</string>\n\
    <key>CFBundleIdentifier</key>\n\
    <string>com.gehnmaisoda.local-runner</string>\n\
    <key>CFBundleVersion</key>\n\
    <string>$(VERSION)</string>\n\
    <key>CFBundleExecutable</key>\n\
    <string>local-runnerd</string>\n\
    <key>LSBackgroundOnly</key>\n\
    <true/>\n\
</dict>\n\
</plist>' > dist/LocalRunner.app/Contents/Info.plist
	codesign --force --sign - dist/LocalRunner.app
	cp cli/lr dist/lr
	cd dist && tar czf local-runner-$(VERSION)-arm64.tar.gz LocalRunner.app lr
	@echo "Created dist/local-runner-$(VERSION)-arm64.tar.gz"

# Install daemon as LaunchAgent (requires release build)
install: build
	cd cli && bun run index.ts install

# Clean build artifacts
clean:
	cd daemon && swift package clean
	rm -f cli/lr
	rm -rf dist
