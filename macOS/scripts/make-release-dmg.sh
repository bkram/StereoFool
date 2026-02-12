#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: macOS/scripts/make-release-dmg.sh [options]

Builds StereoFool macOS release artifacts:
1) StereoFool.app
2) StereoFool-<version>.dmg (drag app to Applications)

Options:
  -v, --version VERSION     Release version (default: YYYY.MM.DD+<git-sha>)
  -o, --out-dir DIR         Output directory (default: macOS/dist)
  -c, --config PATH         Default INI to bundle (default: macOS/StereFool.ini)
  -h, --help                Show this help
EOF
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS_DIR="$ROOT_DIR/macOS"

OUT_DIR="$MACOS_DIR/dist"
CONFIG_PATH="$MACOS_DIR/StereFool.ini"

default_version() {
  local stamp sha
  stamp="$(date +%Y.%m.%d)"
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    sha="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"
  else
    sha="local"
  fi
  printf '%s+%s' "$stamp" "$sha"
}

VERSION="$(default_version)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      VERSION="$2"
      shift 2
      ;;
    -o|--out-dir)
      OUT_DIR="$2"
      shift 2
      ;;
    -c|--config)
      CONFIG_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Config not found: $CONFIG_PATH" >&2
  exit 3
fi

if [[ -d "/Applications/Xcode.app/Contents/Developer" ]] && [[ -z "${DEVELOPER_DIR:-}" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/swift-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/swift-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

APP_NAME="StereoFool"
BUNDLE_ID="com.stereofool.app"
VOL_NAME="StereoFool ${VERSION}"
DMG_NAME="StereoFool-${VERSION}.dmg"
WORK_DIR="$OUT_DIR/.release-work"
APP_DIR="$OUT_DIR/${APP_NAME}.app"
DMG_PATH="$OUT_DIR/$DMG_NAME"
ICON_PATH="$OUT_DIR/AppIcon.icns"

rm -rf "$WORK_DIR" "$APP_DIR" "$DMG_PATH"
mkdir -p "$OUT_DIR"

echo "Building release binary..."
xcrun swift build -c release --package-path "$MACOS_DIR"

BIN_PATH="$MACOS_DIR/.build/release/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Release binary missing: $BIN_PATH" >&2
  exit 4
fi

echo "Creating app bundle..."
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/bin"

python3 "$MACOS_DIR/scripts/generate-universal-stereo-icon.py" "$ICON_PATH" >/dev/null

cat >"$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>StereoFool needs microphone access for live input processing.</string>
</dict>
</plist>
EOF

cp "$BIN_PATH" "$APP_DIR/Contents/Resources/bin/StereoFool-bin"
cp "$CONFIG_PATH" "$APP_DIR/Contents/Resources/StereFool.ini"
cp "$MACOS_DIR/README.md" "$APP_DIR/Contents/Resources/README.txt"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat >"$APP_DIR/Contents/MacOS/${APP_NAME}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$APP_ROOT/Resources/bin/StereoFool-bin"
DEFAULT_CFG="$APP_ROOT/Resources/StereFool.ini"
exec "$BIN" --config "$DEFAULT_CFG" "$@"
EOF

chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"
chmod +x "$APP_DIR/Contents/Resources/bin/StereoFool-bin"

echo "Packaging DMG..."
mkdir -p "$WORK_DIR"
cp -R "$APP_DIR" "$WORK_DIR/"
ln -s /Applications "$WORK_DIR/Applications"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$WORK_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$WORK_DIR"

echo "Release created:"
echo "  App: $APP_DIR"
echo "  DMG: $DMG_PATH"
echo
echo "Optional next steps:"
echo "  1) codesign --deep --force --sign \"Developer ID Application: ...\" \"$APP_DIR\""
echo "  2) xcrun notarytool submit \"$DMG_PATH\" --wait --keychain-profile <profile>"
echo "  3) xcrun stapler staple \"$APP_DIR\""
echo "  4) xcrun stapler staple \"$DMG_PATH\""
