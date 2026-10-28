#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/VidgetYo.xcodeproj"
SCHEME="VidgetYo"
CONFIGURATION="Release"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
APP_NAME="VidgetYo.app"
VOLUME_NAME="VidgetYo"
VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PROJECT/project.pbxproj" | head -1)"
DMG_NAME="VidgetYo-${VERSION}-macOS27-arm64.dmg"

# Optional environment variables:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE="notarytool-keychain-profile"
#   TEAM_ID="XXXXXXXXXX"
# If SIGN_IDENTITY is unset, the app is ad-hoc signed for local use.

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: This script must run on macOS."
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: Xcode is not available."
  exit 1
fi

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
echo "Using macOS SDK: ${SDK_VERSION:-unknown}"
echo "Version: ${VERSION}"

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

echo "==> Building Release arm64"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  clean build

APP_PATH="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Build succeeded but $APP_PATH was not found."
  exit 1
fi

cp -R "$APP_PATH" "$DIST/$APP_NAME"
APP_PATH="$DIST/$APP_NAME"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing with Developer ID"
  if [[ -n "${TEAM_ID:-}" ]]; then
    echo "Team ID: $TEAM_ID"
  fi
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  echo "==> No SIGN_IDENTITY set; applying ad-hoc signature for local installation"
  codesign --force --deep --sign - "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

STAGE="$DIST/dmg-root"
mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/README.txt" <<'TXT'
VidgetYo — установка

1. Перетащите VidgetYo.app в Applications.
2. Запустите VidgetYo из Applications.
3. В настройках укажите адрес API задач веб-приложения.

Виджет лежит на рабочем столе. Иконка в строке меню — чеклист.
Пункт «Поверх окон» поднимает карточку над обычными окнами.

Если сборка без Developer ID, Gatekeeper может попросить:
Control-click VidgetYo.app > Открыть > Открыть.
TXT

DMG_PATH="$DIST/$DMG_NAME"
rm -f "$DMG_PATH"
echo "==> Creating DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    echo "ERROR: NOTARY_PROFILE was set, but SIGN_IDENTITY is empty. Notarization requires Developer ID signing."
    exit 1
  fi
  echo "==> Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

rm -rf "$STAGE"

echo
echo "Installer: $DMG_PATH"
shasum -a 256 "$DMG_PATH"
if [[ -z "${CI:-}" ]]; then
  open "$DIST"
fi
