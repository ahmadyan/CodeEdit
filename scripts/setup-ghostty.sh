#!/bin/bash
#
# Setup script for GhosttyKit framework
# This script builds or downloads the libghostty static library required for
# the Ghostty terminal backend feature.
#
# Requirements:
#   - Zig 0.13.0 or later (brew install zig)
#   - Ghostty source code (will be cloned if not present)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRAMEWORK_DIR="$PROJECT_DIR/CodeEdit/Frameworks/GhosttyKit.xcframework"
GHOSTTY_DIR="${GHOSTTY_SOURCE:-$PROJECT_DIR/../ghostty-reference}"

echo "==> Setting up GhosttyKit framework..."

# Check if the library already exists
if [ -f "$FRAMEWORK_DIR/macos-arm64/libghostty-fat.a" ]; then
    SIZE=$(ls -lh "$FRAMEWORK_DIR/macos-arm64/libghostty-fat.a" | awk '{print $5}')
    echo "==> GhosttyKit library already exists ($SIZE)"
    echo "    To rebuild, delete: $FRAMEWORK_DIR/macos-arm64/libghostty-fat.a"
    exit 0
fi

# Check for Zig
if ! command -v zig &> /dev/null; then
    echo "Error: Zig is required but not installed."
    echo "Install with: brew install zig"
    exit 1
fi

ZIG_VERSION=$(zig version)
echo "==> Using Zig $ZIG_VERSION"

# Check for Ghostty source
if [ ! -d "$GHOSTTY_DIR" ]; then
    echo "==> Ghostty source not found at $GHOSTTY_DIR"
    echo "    Cloning ghostty-org/ghostty..."
    git clone https://github.com/ghostty-org/ghostty.git "$GHOSTTY_DIR"
fi

# Build GhosttyKit
echo "==> Building GhosttyKit.xcframework..."
cd "$GHOSTTY_DIR"

zig build \
    -Dapp-runtime=none \
    -Demit-xcframework \
    -Dxcframework-target=universal \
    -Doptimize=ReleaseFast

# Copy the static library
echo "==> Copying static library to framework..."
mkdir -p "$FRAMEWORK_DIR/macos-arm64"
cp "$GHOSTTY_DIR/macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a" \
   "$FRAMEWORK_DIR/macos-arm64/"

# Verify
if [ -f "$FRAMEWORK_DIR/macos-arm64/libghostty-fat.a" ]; then
    SIZE=$(ls -lh "$FRAMEWORK_DIR/macos-arm64/libghostty-fat.a" | awk '{print $5}')
    echo "==> Successfully installed GhosttyKit ($SIZE)"
else
    echo "Error: Failed to install GhosttyKit"
    exit 1
fi
