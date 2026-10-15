#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Mac Authenticator.app"
APP_VERSION=$(tr -d '\n\r' < VERSION)
APP_ARCH=${APP_ARCH:-$(uname -m)}
case "$APP_ARCH" in arm64|x86_64) ;; *) echo 'Unsupported architecture' >&2; exit 1 ;; esac
codesign --verify --deep --strict "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/MacAuthenticator")" = "$APP_ARCH"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$APP_VERSION"
RELEASE_DIR="$PWD/dist/releases"
STEM="MacAuthenticator-$APP_VERSION-$APP_ARCH"
mkdir -p "$RELEASE_DIR"
PACKAGE_TEMP=$(mktemp -d)
trap 'rm -rf "$PACKAGE_TEMP"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/$STEM.zip"
ditto "$APP" "$PACKAGE_TEMP/Mac Authenticator.app"
ln -s /Applications "$PACKAGE_TEMP/Applications"
hdiutil create -quiet -ov -format UDZO -volname 'Mac Authenticator' -srcfolder "$PACKAGE_TEMP" "$RELEASE_DIR/$STEM.dmg"
hdiutil verify "$RELEASE_DIR/$STEM.dmg"
# Verify the downloadable ZIP, not just the pre-archive bundle.
mkdir "$PACKAGE_TEMP/unpacked"
ditto -x -k "$RELEASE_DIR/$STEM.zip" "$PACKAGE_TEMP/unpacked"
codesign --verify --deep --strict "$PACKAGE_TEMP/unpacked/Mac Authenticator.app"
cmp "$APP/Contents/MacOS/MacAuthenticator" "$PACKAGE_TEMP/unpacked/Mac Authenticator.app/Contents/MacOS/MacAuthenticator"
(cd "$RELEASE_DIR" && shasum -a 256 "$STEM.zip" "$STEM.dmg" > "$STEM.sha256")
printf 'Packaged: %s/{%s.zip,%s.dmg}\n' "$RELEASE_DIR" "$STEM" "$STEM"
