#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="HotCorners"
BUNDLE_NAME="Hot Corners.app"
BUILD_DIR=".build/release"
DIST_DIR="dist"
BUNDLE_PATH="$DIST_DIR/$BUNDLE_NAME"
ZIP_PATH="$DIST_DIR/HotCorners.zip"

PUBLISH=false
if [[ "${1:-}" == "--release" ]]; then
    PUBLISH=true
fi

# No hand-maintained version numbers: the commit count is the build number
# (monotonically increasing), the commit hash identifies the exact source.
GIT_SHA="$(git rev-parse HEAD)"
GIT_SHORT="$(git rev-parse --short HEAD)"
BUILD_NUMBER="$(git rev-list --count HEAD)"
GIT_DATE="$(git log -1 --format=%cd --date=format:%Y.%m.%d)"
GIT_SUBJECT="$(git log -1 --format=%s)"

echo "Building release binary… (build $BUILD_NUMBER, $GIT_SHORT)"
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
    <string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key>
    <string>$GIT_DATE</string>
    <key>GitCommit</key>
    <string>$GIT_SHA</string>
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

echo "Zipping…"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE_PATH" "$ZIP_PATH"

echo "Done: $BUNDLE_PATH (build $BUILD_NUMBER)"

if [[ "$PUBLISH" == true ]]; then
    if [[ -n "$(git status --porcelain -- Sources Resources Package.swift build.sh)" ]]; then
        echo "Refusing to publish: uncommitted changes in the sources." >&2
        exit 1
    fi
    if ! git merge-base --is-ancestor HEAD "origin/$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null; then
        echo "Refusing to publish: HEAD is not pushed to origin." >&2
        exit 1
    fi
    echo "Publishing release build-$BUILD_NUMBER…"
    gh release create "build-$BUILD_NUMBER" "$ZIP_PATH" \
        --title "Build $BUILD_NUMBER · $GIT_SHORT" \
        --notes "$GIT_SUBJECT"
fi
