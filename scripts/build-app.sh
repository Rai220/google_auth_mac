#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_VERSION=$(tr -d '\n\r' < VERSION)
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'VERSION must be MAJOR.MINOR.PATCH' >&2; exit 1
fi
APP_ARCH=${APP_ARCH:-$(uname -m)}
case "$APP_ARCH" in arm64|x86_64) ;; *) echo 'Unsupported architecture' >&2; exit 1 ;; esac
BUILD_PATH=".build/package-$APP_ARCH"
swift build -c release --product MacAuthenticator --arch "$APP_ARCH" --scratch-path "$BUILD_PATH"
BIN_PATH=$(swift build -c release --arch "$APP_ARCH" --scratch-path "$BUILD_PATH" --show-bin-path)
APP="$PWD/dist/Mac Authenticator.app"
# Recreate only this generated bundle, never an installed application or vault.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/AppIcon.iconset
cp "$BIN_PATH/MacAuthenticator" "$APP/Contents/MacOS/MacAuthenticator"
cp -R Resources/en.lproj Resources/ru.lproj "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
swift scripts/icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.macauthenticator.app "$APP"
codesign --verify --deep --strict "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/MacAuthenticator")" = "$APP_ARCH"
printf 'Built: %s (%s, %s)\n' "$APP" "$APP_VERSION" "$APP_ARCH"
