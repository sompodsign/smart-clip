#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/SmartClip.app"
pkill -x SmartClip 2>/dev/null || true
sleep 1
swift build -c release 2>&1 | tail -3
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/SmartClip "$APP/Contents/MacOS/SmartClip"
cp SmartClip/Info.plist "$APP/Contents/Info.plist"
cp -R .build/arm64-apple-macosx/release/Sparkle.framework "$APP/Contents/Frameworks/"
test -d .build/release/SmartClip_SmartClip.bundle && cp -R .build/release/SmartClip_SmartClip.bundle "$APP/Contents/Resources/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/SmartClip"
echo "✅ Installed to $APP"
open "$APP"
