#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WORK_DIR="$ROOT/.build/AppDistribution"
LOCK_DIR="$WORK_DIR/Package.lock"
ICON_WORK_DIR="$WORK_DIR/IconGeneration"
DERIVED_DATA="$WORK_DIR/DerivedData"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/ProductivityTime.app"
PACKAGED_APP="$WORK_DIR/ProductivityTime.app"
DMG_CONTENTS="$WORK_DIR/DiskImageContents"
PACKAGED_DMG="$WORK_DIR/ProductivityTime-1.0.dmg"
DIST_DIR="$ROOT/dist"
FINAL_APP="$DIST_DIR/ProductivityTime-1.0.app"
FINAL_DMG="$DIST_DIR/ProductivityTime-1.0.dmg"
OWNERSHIP_MARKER="$DIST_DIR/.ProductivityTime-1.0-package-owned"
PUBLISH_APP="$DIST_DIR/.ProductivityTime-1.0.app.$$.tmp"
PUBLISH_DMG="$DIST_DIR/.ProductivityTime-1.0.dmg.$$.tmp"

mkdir -p "$WORK_DIR" "$DIST_DIR"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "Another packaging run is already using $WORK_DIR; refusing to run concurrently." >&2
    exit 2
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap 'rm -rf "$PUBLISH_APP" "$PUBLISH_DMG"; rm -rf "$LOCK_DIR"' EXIT

if [[ -e "$FINAL_APP" || -e "$FINAL_DMG" ]]; then
    if [[ ! -f "$OWNERSHIP_MARKER" ]] || [[ "$(cat "$OWNERSHIP_MARKER")" != "com.ismailucrn.ProductivityTime package-macos.sh" ]]; then
        echo "Refusing to replace existing dist artifacts without this script's ownership marker:" >&2
        echo "  $FINAL_APP" >&2
        echo "  $FINAL_DMG" >&2
        echo "Choose another output path or move those files first." >&2
        exit 2
    fi
fi

mkdir -p "$WORK_DIR/Temporary"
export TMPDIR="$WORK_DIR/Temporary"

mkdir -p "$ICON_WORK_DIR"
xcrun swiftc \
    -module-cache-path "$WORK_DIR/SwiftModuleCache" \
    -framework AppKit \
    -o "$WORK_DIR/GenerateAppIcon" \
    "$ROOT/scripts/GenerateAppIcon.swift"
"$WORK_DIR/GenerateAppIcon" "$ICON_WORK_DIR"
cp "$ICON_WORK_DIR/ProductivityTime.icns" "$ROOT/ProductivityTime/Resources/ProductivityTime.icns"
cp "$ICON_WORK_DIR/ProductivityTime-Icon-Preview.png" "$ROOT/ProductivityTime/Resources/ProductivityTime-Icon-Preview.png"

xcodebuild \
    -project ProductivityTime.xcodeproj \
    -scheme ProductivityTime \
	-configuration Release \
	-destination 'generic/platform=macOS' \
	-derivedDataPath "$DERIVED_DATA" \
	ARCHS='arm64 x86_64' \
	ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CLANG_MODULE_CACHE_PATH="$WORK_DIR/ClangModuleCache" \
    SWIFT_MODULE_CACHE_PATH="$WORK_DIR/SwiftModuleCache" \
    build

rm -rf "$PACKAGED_APP"
ditto "$APP_SOURCE" "$PACKAGED_APP"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PACKAGED_APP/Contents/Info.plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile ProductivityTime.icns' "$PACKAGED_APP/Contents/Info.plist"
else
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string ProductivityTime.icns' "$PACKAGED_APP/Contents/Info.plist"
fi
codesign --force --deep --options runtime \
    --entitlements "$ROOT/ProductivityTime/Resources/ProductivityTime.entitlements" \
    --sign - "$PACKAGED_APP"
codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"

EXECUTABLE="$PACKAGED_APP/Contents/MacOS/ProductivityTime"
ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
    echo "Expected a universal arm64/x86_64 executable, got: $ARCHITECTURES" >&2
    exit 1
fi
ICON_FILE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PACKAGED_APP/Contents/Info.plist")"
if [[ "$ICON_FILE" != "ProductivityTime.icns" || ! -f "$PACKAGED_APP/Contents/Resources/ProductivityTime.icns" ]]; then
    echo "The app bundle is missing its configured ProductivityTime icon." >&2
    exit 1
fi
codesign -d --entitlements :- "$PACKAGED_APP" > "$WORK_DIR/EmbeddedEntitlements.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :com.apple.security.automation.apple-events' "$WORK_DIR/EmbeddedEntitlements.plist" >/dev/null

rm -rf "$DMG_CONTENTS"
mkdir -p "$DMG_CONTENTS"
ditto "$PACKAGED_APP" "$DMG_CONTENTS/ProductivityTime.app"
ln -s /Applications "$DMG_CONTENTS/Applications"
rm -f "$PACKAGED_DMG"
hdiutil create \
    -volname 'Productivity Time' \
    -srcfolder "$DMG_CONTENTS" \
    -format UDZO \
    -ov "$PACKAGED_DMG"
hdiutil verify "$PACKAGED_DMG"

MOUNT_DIR="$WORK_DIR/MountedImage"
mkdir -p "$MOUNT_DIR"
MOUNT_OUTPUT="$(hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$PACKAGED_DMG")"
if [[ ! -d "$MOUNT_DIR/ProductivityTime.app" || "$(readlink "$MOUNT_DIR/Applications")" != "/Applications" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null
    echo "The disk image does not contain the app and Applications shortcut." >&2
    exit 1
fi
hdiutil detach "$MOUNT_DIR" >/dev/null

ditto "$PACKAGED_APP" "$PUBLISH_APP"
cp "$PACKAGED_DMG" "$PUBLISH_DMG"
rm -rf "$FINAL_APP"
mv "$PUBLISH_APP" "$FINAL_APP"
mv -f "$PUBLISH_DMG" "$FINAL_DMG"
printf '%s\n' 'com.ismailucrn.ProductivityTime package-macos.sh' > "$OWNERSHIP_MARKER"

echo "Created $FINAL_APP"
echo "Created $FINAL_DMG"
echo "Architectures: $ARCHITECTURES"
echo "Signature: ad hoc, verified"
