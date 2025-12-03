#!/usr/bin/env bash
# ABOUTME: Build and install Barik to /Applications
# ABOUTME: Handles quitting running instance, building, and relaunching

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="Barik.app"
DEST="/Applications/$APP_NAME"

echo "Building Barik..."
cd "$SCRIPT_DIR"
xcodebuild -scheme Barik -configuration Release -derivedDataPath "$BUILD_DIR" build | grep -E "(Building|Compiling|Linking|BUILD)" || true

if ! [ -d "$BUILD_DIR/Build/Products/Release/$APP_NAME" ]; then
    echo "Build failed - app not found"
    exit 1
fi

echo "Stopping running instance..."
pkill -x Barik 2>/dev/null || true
sleep 1

echo "Installing to /Applications..."
rm -rf "$DEST"
cp -R "$BUILD_DIR/Build/Products/Release/$APP_NAME" "$DEST"

echo "Launching Barik..."
open "$DEST"

echo "Done!"
