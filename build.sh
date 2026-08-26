#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="HotCorners"
BUNDLE_NAME="Hot Corners.app"
BUILD_DIR=".build/release"
DIST_DIR="dist"
BUNDLE_PATH="$DIST_DIR/$BUNDLE_NAME"

echo "Building release binary…"
swift build -c release

echo "Assembling app bundle…"
rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$BUNDLE_PATH/Contents/MacOS/$APP_NAME"
cp "Resources/AppIcon.icns" "$BUNDLE_PATH/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Hot Corners</string>
    <key>CFBundleDisplayName</key>
    <string>Hot Corners</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.hotcorners</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

echo "Ad-hoc signing…"
codesign --force --deep --sign - "$BUNDLE_PATH"

echo "Done: $BUNDLE_PATH"
