#!/bin/bash

set -euo pipefail

APP_NAME="UniGlo"
APP_IDENTIFIER="com.unifiled.controller"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-1}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

if [[ -z "$SPARKLE_FEED_URL" ]]; then
    echo "error: SPARKLE_FEED_URL is required" >&2
    exit 1
fi

if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
    echo "error: SPARKLE_PUBLIC_ED_KEY is required" >&2
    exit 1
fi

echo "Building app..."
swift build -c release

APP_BUNDLE="$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES" "$FRAMEWORKS"

cp .build/release/UniFiLEDControllerApp "$MACOS/$APP_NAME"

if [[ -f "AppIcon.icns" ]]; then
    cp AppIcon.icns "$RESOURCES/"
fi

SPARKLE_FRAMEWORK_SRC=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK_SRC" ]]; then
    echo "error: Sparkle framework not found at $SPARKLE_FRAMEWORK_SRC" >&2
    exit 1
fi

ditto "$SPARKLE_FRAMEWORK_SRC" "$FRAMEWORKS/Sparkle.framework"

/usr/bin/install_name_tool -add_rpath "@loader_path/../Frameworks" "$MACOS/$APP_NAME" 2>/dev/null || true

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>SUFeedURL</key>
    <string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key>
    <string>$SPARKLE_PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUEnableInstallerLauncherService</key>
    <true/>
    <key>SUAllowsAutomaticUpdates</key>
    <true/>
</dict>
</plist>
EOF

echo "App bundle created: $APP_BUNDLE"
echo "Run: SPARKLE_FEED_URL=... SPARKLE_PUBLIC_ED_KEY=... ./build_app.sh"
