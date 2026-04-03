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
	mkdir -p dist
	cp daemon/.build/release/local-runner dist/local-runner-daemon
	cp cli/lr dist/lr
	cd dist && tar czf local-runner-$(VERSION)-arm64.tar.gz local-runner-daemon lr
	@echo "Created dist/local-runner-$(VERSION)-arm64.tar.gz"

# Install daemon as LaunchAgent (requires release build)
install: build
	cd cli && bun run index.ts install

# Clean build artifacts
clean:
	cd daemon && swift package clean
	rm -f cli/lr
