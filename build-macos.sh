#!/bin/bash
# Build Ghostty.app (this sidebar fork) on macOS 26.x "Tahoe" with Zig 0.15.2.
#
# WHY THIS SCRIPT EXISTS
# Zig 0.15.2 (the version Ghostty 1.3.x pins) cannot link against the macOS 26.5
# SDK's libSystem.tbd — its Mach-O linker fails on __availability_version_check
# and friends. Pristine upstream Ghostty fails to `zig build` here too; it is a
# toolchain/SDK version gap, not a fork problem.
#
# The workaround has three moving parts, all handled below idempotently:
#   1. Patch Zig's std so getSdk() honors $SDKROOT (so the SDK can be found
#      without a working `xcrun`).
#   2. Run `zig build` with a *broken* DEVELOPER_DIR so Zig links every native
#      binary (build runner, host helpers, dylibs) against its *bundled*
#      libSystem stub, and point SDKROOT at an OVERLAY SDK whose libSystem.tbd
#      is that bundled (parseable) stub while headers/frameworks symlink to the
#      real SDK. (The Xcode tool steps — libtool/ranlib/metal/xcodebuild — pin
#      DEVELOPER_DIR back to real Xcode; see the `build:` commit.)
#   3. Build the macOS .app with real Xcode via xcodebuild (its real ld handles
#      the 26.5 SDK fine).
#
# Drop all of this once Zig links the macOS 26 SDK natively (newer Zig).
set -euo pipefail

ZIG_DIR="${ZIG_DIR:-$HOME/.zig-0.15.2}"
XCODE_DEV="${XCODE_DEV:-/Applications/Xcode.app/Contents/Developer}"
REPO="${REPO:-$(cd "$(dirname "$0")" && pwd)}"
OVERLAY="${OVERLAY:-$HOME/.ghostty-build/sdkoverlay}"
ZIG="$ZIG_DIR/zig"

echo "==> Ghostty (sidebar fork) macOS build"
echo "    zig:   $ZIG"
echo "    xcode: $XCODE_DEV"
echo "    repo:  $REPO"

# --- 0. sanity ---------------------------------------------------------------
[ -x "$ZIG" ] || { echo "ERROR: zig 0.15.2 not found at $ZIG (set ZIG_DIR)"; exit 1; }
[ -d "$XCODE_DEV" ] || { echo "ERROR: Xcode not found at $XCODE_DEV (set XCODE_DEV)"; exit 1; }
REAL_SDK="$(DEVELOPER_DIR="$XCODE_DEV" xcrun --sdk macosx --show-sdk-path)"
BUNDLED_TBD="$ZIG_DIR/lib/libc/darwin/libSystem.tbd"
DARWIN_ZIG="$ZIG_DIR/lib/std/zig/system/darwin.zig"

# --- 1. patch Zig std getSdk() to honor SDKROOT (idempotent) -----------------
if ! grep -q 'SDKROOT' "$DARWIN_ZIG"; then
  echo "==> patching Zig std getSdk() to honor SDKROOT"
  perl -0pi -e 's/(const argv = &\[_\]\[\]const u8\{ "xcrun", "--sdk", sdk, "--show-sdk-path" \};)/if (target.os.tag.isDarwin()) {\n        if (std.posix.getenv("SDKROOT")) |sdkroot| {\n            if (sdkroot.len > 0) return allocator.dupe(u8, sdkroot) catch null;\n        }\n    }\n    $1/' "$DARWIN_ZIG"
  grep -q 'SDKROOT' "$DARWIN_ZIG" && echo "    patched." || { echo "ERROR: patch failed"; exit 1; }
else
  echo "==> Zig std getSdk() already honors SDKROOT (ok)"
fi

# --- 2. (re)build the overlay SDK (idempotent) -------------------------------
echo "==> building overlay SDK at $OVERLAY"
mirror() { local src="$1" dst="$2" skip=" $3 "; mkdir -p "$dst"; local e n
  for e in "$src"/*; do [ -e "$e" ] || continue; n="$(basename "$e")"
    case "$skip" in *" $n "*) continue;; esac; ln -sfn "$e" "$dst/$n"; done; }
rm -rf "$OVERLAY"; mkdir -p "$(dirname "$OVERLAY")"
mirror "$REAL_SDK" "$OVERLAY" "usr"
mirror "$REAL_SDK/usr" "$OVERLAY/usr" "lib"
mirror "$REAL_SDK/usr/lib" "$OVERLAY/usr/lib" "libSystem.tbd libSystem.B.tbd"
cp "$BUNDLED_TBD" "$OVERLAY/usr/lib/libSystem.tbd"
cp "$BUNDLED_TBD" "$OVERLAY/usr/lib/libSystem.B.tbd"

# --- 3. Metal toolchain check ------------------------------------------------
if ! DEVELOPER_DIR="$XCODE_DEV" xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  echo "==> Metal toolchain missing; downloading (one-time, ~700MB)…"
  DEVELOPER_DIR="$XCODE_DEV" xcodebuild -downloadComponent MetalToolchain
fi

# --- 4. build the native GhosttyKit.xcframework ------------------------------
echo "==> zig build: GhosttyKit.xcframework (native, bundled-libSystem)"
cd "$REPO"
DEVELOPER_DIR=/nonexistent SDKROOT="$OVERLAY" PATH="$ZIG_DIR:$PATH" \
  "$ZIG" build -Demit-xcframework=true -Dxcframework-target=native -Demit-macos-app=false
[ -d "$REPO/macos/GhosttyKit.xcframework" ] || { echo "ERROR: xcframework not produced"; exit 1; }

# --- 5. build Ghostty.app with real Xcode ------------------------------------
echo "==> xcodebuild: Ghostty.app (arm64)"
cd "$REPO/macos"
DEVELOPER_DIR="$XCODE_DEV" xcodebuild -project Ghostty.xcodeproj -target Ghostty \
  -configuration Debug -arch arm64 ONLY_ACTIVE_ARCH=YES build

APP="$REPO/macos/build/Debug/Ghostty.app"
echo ""
echo "==> DONE. App: $APP"
echo "    launch:  open '$APP'"
