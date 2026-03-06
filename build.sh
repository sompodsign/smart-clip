#!/bin/bash
# SmartClip — Build Script
# Creates a release DMG and .app bundle

set -e

# Abort if SmartClip is currently running
if pgrep -x "SmartClip" > /dev/null 2>&1; then
    echo "❌ SmartClip is currently running. Please quit it before building/reinstalling."
    exit 1
fi

# Ensure Rust is available
source "$HOME/.cargo/env" 2>/dev/null || true

echo "🔨 Building SmartClip..."
echo ""

cd "$(dirname "$0")/clipvault"

# Build release
npm run tauri build

echo ""
echo "✅ Build complete!"
echo ""

# Copy DMG to root directory
cp src-tauri/target/release/bundle/dmg/*.dmg ../
echo "📦 DMG copied to: $(cd .. && pwd)/"
ls -lh ../*.dmg
echo ""

# Open the DMG folder in Finder
open src-tauri/target/release/bundle/dmg/
