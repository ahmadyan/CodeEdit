# GhosttyKit Framework

This directory contains the GhosttyKit.xcframework for GPU-accelerated terminal rendering via [libghostty](https://github.com/ghostty-org/ghostty).

## Setup

The static library (`libghostty-fat.a`) is not included in the repository due to its size (~130MB). To enable the Ghostty terminal backend:

### Option 1: Use the setup script (recommended)

```bash
./scripts/setup-ghostty.sh
```

This will:
1. Check for Zig installation (required for building)
2. Clone the Ghostty source if not present
3. Build the xcframework
4. Copy the static library to this directory

### Option 2: Manual build

1. Install Zig: `brew install zig`
2. Clone Ghostty: `git clone https://github.com/ghostty-org/ghostty.git`
3. Build the framework:
   ```bash
   cd ghostty
   zig build -Dapp-runtime=none -Demit-xcframework -Dxcframework-target=universal -Doptimize=ReleaseFast
   ```
4. Copy the library:
   ```bash
   cp macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a \
      /path/to/CodeEdit/CodeEdit/Frameworks/GhosttyKit.xcframework/macos-arm64/
   ```

### Option 3: Copy from existing Ghostty build

If you already have Ghostty built:

```bash
cp /path/to/ghostty/macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a \
   CodeEdit/Frameworks/GhosttyKit.xcframework/macos-arm64/
```

## Usage

Once the library is in place:
1. Build CodeEdit normally
2. Go to Settings → Terminal → Experimental
3. Enable "Use Ghostty Backend"
4. Restart CodeEdit

## Files

- `Info.plist` - Framework metadata
- `macos-arm64/Headers/` - C headers for libghostty API
- `macos-arm64/libghostty-fat.a` - Static library (not in repo, must be built/obtained)
