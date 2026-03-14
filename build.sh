#!/bin/bash
set -euo pipefail

echo "🔨 Building SmartClip..."

# Check if SmartClip is running
if pgrep -x "SmartClip" > /dev/null; then
    echo "⚠️  SmartClip is running. Killing..."
    pkill -x "SmartClip" || true
    sleep 1
fi

# Build release
swift build -c release

echo "✅ Build complete!"
echo "📦 Binary at: .build/release/SmartClip"
echo ""
echo "To run: .build/release/SmartClip"
