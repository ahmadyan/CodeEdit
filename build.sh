#!/bin/bash
# Build and sign CodeEdit without sandbox (matches official release behavior)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_PATH="$BUILD_DIR/Build/Products/Debug/CodeEdit.app"

echo "=== Building CodeEdit ==="
xcodebuild -scheme CodeEdit \
  -derivedDataPath "$BUILD_DIR" \
  -skipPackagePluginValidation \
  build 2>&1 | grep -E "(error:|warning:|BUILD)" | tail -20

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Build failed - app not found at $APP_PATH"
  exit 1
fi

echo ""
echo "=== Re-signing without sandbox ==="
# Create entitlements that disable sandbox (matches official release)
cat > /tmp/codeedit-nosandbox.entitlements << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>com.apple.security.app-sandbox</key>
        <false/>
        <key>com.apple.security.cs.allow-jit</key>
        <true/>
        <key>com.apple.security.cs.disable-library-validation</key>
        <true/>
        <key>com.apple.security.get-task-allow</key>
        <true/>
</dict>
</plist>
EOF

codesign --force --sign - --entitlements /tmp/codeedit-nosandbox.entitlements "$APP_PATH"

echo ""
echo "=== Build complete ==="
echo "App location: $APP_PATH"
echo ""
echo "To launch: open \"$APP_PATH\""
echo "To launch with folder: open \"$APP_PATH\" --args /path/to/folder"
