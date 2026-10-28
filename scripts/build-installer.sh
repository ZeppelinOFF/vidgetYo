#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/VidgetYo.xcodeproj"
SCHEME="VidgetYo"
CONFIGURATION="Release"
DIST="$ROOT/dist"
APP_NAME="VidgetYo.app"
VOLUME_NAME="VidgetYo"
VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PROJECT/project.pbxproj" | head -1)"
# ARCH=arm64 or ARCH=x86_64 builds one slice. The default builds both.
ARCHES="${ARCH:-arm64 x86_64}"

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

rm -rf "$DIST"
mkdir -p "$DIST"

build_arch() {
  local arch="$1"
  local derived="$ROOT/build/DerivedData-$arch"
  local dmg_name="VidgetYo-${VERSION}-macOS27-${arch}.dmg"
  local dmg_path="$DIST/$dmg_name"
  local stage="$DIST/dmg-root-$arch"
  local app_path

  rm -rf "$derived" "$stage"
  echo "==> Building Release $arch"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$derived" \
    -destination "platform=macOS,arch=$arch" \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    clean build

  app_path="$derived/Build/Products/$CONFIGURATION/$APP_NAME"
  if [[ ! -d "$app_path" ]]; then
    echo "ERROR: Build succeeded but $app_path was not found."
    exit 1
  fi

  mkdir -p "$stage"
  cp -R "$app_path" "$stage/$APP_NAME"
  app_path="$stage/$APP_NAME"

  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "==> Signing $arch with Developer ID"
    if [[ -n "${TEAM_ID:-}" ]]; then
      echo "Team ID: $TEAM_ID"
    fi
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app_path"
  else
    echo "==> No SIGN_IDENTITY set; applying ad-hoc signature for $arch"
    codesign --force --deep --sign - "$app_path"
  fi

  codesign --verify --deep --strict --verbose=2 "$app_path"
  ln -s /Applications "$stage/Applications"

  cat > "$stage/README.txt" <<'TXT'
VidgetYo — установка

1. Перетащите VidgetYo.app в Applications.
2. Запустите VidgetYo из Applications.
3. В настройках укажите адрес API задач веб-приложения.

Виджет лежит на рабочем столе. Иконка в строке меню — чеклист.
Пункт «Поверх окон» поднимает карточку над обычными окнами.

Если сборка без Developer ID, Gatekeeper может попросить:
Control-click VidgetYo.app > Открыть > Открыть.
TXT

  rm -f "$dmg_path"
  echo "==> Creating $arch DMG"
  diskutil image create from \
    --format UDZO \
    --volumeName "$VOLUME_NAME" \
    "$stage" \
    "$dmg_path"

  if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    echo "==> Signing $arch DMG"
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$dmg_path"
  fi

  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    if [[ -z "${SIGN_IDENTITY:-}" ]]; then
      echo "ERROR: NOTARY_PROFILE was set, but SIGN_IDENTITY is empty. Notarization requires Developer ID signing."
      exit 1
    fi
    echo "==> Submitting $arch DMG for notarization"
    xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
  fi

  rm -rf "$stage"
  echo
  echo "Installer ($arch): $dmg_path"
  shasum -a 256 "$dmg_path"
}

for arch in $ARCHES; do
  case "$arch" in
    arm64|x86_64) build_arch "$arch" ;;
    *)
      echo "ERROR: ARCH must be arm64 or x86_64, got '$arch'."
      exit 1
      ;;
  esac
done

if [[ -z "${CI:-}" ]]; then
  open "$DIST"
fi
