DEV_FLAGS = -Xswiftc -DDEV

.PHONY: daemon web test clean install

# Run daemon in foreground (for development)
daemon:
	-@pkill -f 'local-runner$$' 2>/dev/null || true
	cd daemon && swift build $(DEV_FLAGS)
	daemon/.build/debug/local-runner

# Open Web UI in browser (dev mode — connects to dev daemon)
web:
	cd cli && LOCAL_RUNNER_DEV=1 bun run index.ts

# Run tests
test:
	cd daemon && swift test

# Build daemon release binary
build:
	cd daemon && swift build -c release

# Install daemon as LaunchAgent (requires release build)
install: build
	cd cli && bun run index.ts install

# Clean build artifacts
clean:
	cd daemon && swift package clean
