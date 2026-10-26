#!/bin/bash
# Builds OpenSynapse.app (universal when both architectures are available) and signs it ad hoc.
# Usage: scripts/build-app.sh [output-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
APP="$OUT/OpenSynapse.app"
VERSION="0.1.1"
# Reverse-DNS identifier for the app; change it here if you publish under another name.
BUNDLE_ID="com.guokaili.OpenSynapseMac"

cd "$ROOT"
ARCH_FLAGS=(--arch arm64 --arch x86_64)
if ! swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} >/dev/null 2>&1; then
    # Universal builds need full Xcode on some setups; fall back to the host architecture.
    ARCH_FLAGS=()
fi
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/OpenSynapseMac" "$APP/Contents/MacOS/OpenSynapse"
cp -R "$BIN_DIR/OpenSynapseMac_RazerCore.bundle" "$APP/Contents/Resources/"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>OpenSynapse</string>
    <key>CFBundleDisplayName</key><string>OpenSynapse</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>OpenSynapse</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Guokai Li. Port of OpenSynapse (MIT). Not affiliated with Razer Inc.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"
