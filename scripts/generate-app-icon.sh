#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${MU_BUILD_DIR:-$PROJECT_ROOT/.build}"
mkdir -p "$BUILD_DIR"

xcrun swiftc -parse-as-library \
    "$PROJECT_ROOT/Sources/MurtenShell/Artwork/ToolDrawing.swift" \
    "$PROJECT_ROOT/Sources/MurtenShell/Artwork/SuiteIconDrawing.swift" \
    "$PROJECT_ROOT/media-sources/icon.swift" \
    -o "$BUILD_DIR/generate-app-icon"
"$BUILD_DIR/generate-app-icon" "$PROJECT_ROOT/assets/MurtenUtilities-icon.png"
