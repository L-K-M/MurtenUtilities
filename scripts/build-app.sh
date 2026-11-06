#!/bin/bash
# Builds dist/MurtenUtilities.app from the SwiftPM package, generates the icon
# from the committed master, copies Info.plist into the bundle, signs it and
# verifies the signature.
#
#   scripts/build-app.sh [--debug] [--universal]
#
# --debug builds the Debug configuration (scripts/build.sh --debug reaches this
# through lkm-build's swiftpm kind). --universal builds a fat arm64+x86_64
# binary; the default is the host architecture, which is faster for local runs.
# MU_BUILD_DIR and/or MU_OUTPUT_DIR override the build and output directories.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${MU_BUILD_DIR:-$PROJECT_ROOT/.build}"
OUTPUT_DIR="${MU_OUTPUT_DIR:-$PROJECT_ROOT/dist}"
APP_PATH="$OUTPUT_DIR/MurtenUtilities.app"

CONFIGURATION=release
ARCH_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIGURATION=debug ;;
    --universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
    *) echo "error: unknown option '$arg' (expected --debug or --universal)" >&2; exit 2 ;;
  esac
done

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"

cd "$PROJECT_ROOT"
swift build --configuration "$CONFIGURATION" --scratch-path "$BUILD_DIR" --cache-path "$BUILD_DIR/package-cache" --disable-sandbox ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --scratch-path "$BUILD_DIR" --cache-path "$BUILD_DIR/package-cache" --disable-sandbox --show-bin-path ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"})"

# Assemble from scratch so bundles removed from the package do not linger.
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/MurtenUtilities" "$APP_PATH/Contents/MacOS/MurtenUtilities"

# Shortking's hotkey probes run in this short-lived helper, never in the app,
# so a crash mid-sweep cannot leave a combination registered. ProbeRunner finds
# it with Bundle.main.url(forAuxiliaryExecutable:). Nested code is signed
# before the bundle that contains it.
SHORTKING_PROBE="$APP_PATH/Contents/MacOS/shortking-probe"
cp "$BIN_DIR/ShortkingProbe" "$SHORTKING_PROBE"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$CODE_SIGN_IDENTITY" "$SHORTKING_PROBE"
else
    codesign --force --sign - "$SHORTKING_PROBE"
fi

# SwiftPM resource bundles (one per target with resources) go to
# Contents/Resources, where code signing expects them. SwiftPM's generated
# Bundle.module looks at the bundle root instead, so modules load resources
# through their own accessor (docs/migrating-a-module.md, Resources).
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -type d -exec cp -R {} "$APP_PATH/Contents/Resources/" \;
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

# Regenerate the iconset from the committed master so the shipped icon always
# matches scripts/generate-app-icon.sh → assets/MurtenUtilities-icon.png.
swift "$PROJECT_ROOT/scripts/make-icon.swift" "$PROJECT_ROOT/assets/MurtenUtilities-icon.png" "$BUILD_DIR/MurtenUtilities.iconset"
/usr/bin/iconutil -c icns "$BUILD_DIR/MurtenUtilities.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

# Set CODE_SIGN_IDENTITY for a stable Apple Development or Developer ID identity.
# Ad-hoc signing (no hardened runtime) is sufficient for a local build; signed
# builds embed the Apple Events entitlement below.
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    # The hardened runtime blocks Apple Events unless entitled.
    codesign --force --options runtime --entitlements "$PROJECT_ROOT/Resources/MurtenUtilities.entitlements" \
        --sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
else
    codesign --force --sign - "$APP_PATH"
fi
codesign --verify --strict --verbose=2 "$APP_PATH"
printf '\nBuilt %s\n' "$APP_PATH"
