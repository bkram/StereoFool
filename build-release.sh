#!/bin/bash
# Build StereoFool release DMG with universal binary

set -e

cd "$(dirname "$0")"

VERSION=${1:-0.8}
OUTPUT_DIR="macOS/dist"
APP_NAME="StereoFool"
ICON_FILE="macOS/Resources/StereoFool.icns"
ENTITLEMENTS="macOS/StereoFool.entitlements"

echo "Building StereoFool $VERSION release (universal binary)..."

# Clean output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Build release binary for both architectures with entitlements
echo "Building arm64..."
swift build --package-path macOS -c release --arch arm64

echo "Building x86_64..."
swift build --package-path macOS -c release --arch x86_64

# Create .app bundle structure
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy universal binary to app bundle
echo "Creating universal binary..."
lipo -create \
    "macOS/.build/arm64-apple-macosx/release/StereoFool" \
    "macOS/.build/x86_64-apple-macosx/release/StereoFool" \
    -output "$APP_DIR/Contents/MacOS/StereoFool"

echo "Note: App is not code-signed. For distribution, sign with a valid Apple Developer certificate."
echo "To run without signing, users may need to run: xattr -cr '$APP_DIR'"

if [ -f "$ICON_FILE" ]; then
    cp "$ICON_FILE" "$APP_DIR/Contents/Resources/"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>StereoFool</string>
    <key>CFBundleIdentifier</key>
    <string>com.stereofool.app</string>
    <key>CFBundleName</key>
    <string>StereoFool</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>StereoFool.icns</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>StereoFool needs microphone access to capture audio input for FM signal processing.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2024. All rights reserved.</string>
</dict>
</plist>
EOF

# Embed entitlements in the app bundle
cp "$ENTITLEMENTS" "$APP_DIR/Contents/Resources/StereoFool.entitlements"

# Create default config
cat > "$OUTPUT_DIR/StereoFool.ini" << 'EOF'
[ stereofool ]
input_gain_db = 0.0
output_gain_db = 0.0
preemphasis_us = 75

[pilot ]
pilot_level = 0.09

[ stereo ]
sum_level = 1.0
diff_level = 1.0

[rds ]
en_rds = 1
rds_level = 0.04
rds_pi = FFFF

[mpx ]
mpx_deviation_khz = 75.0

[orbass ]
orbass_enabled = 0
orbass_amount = 0.35
orbass_freq_hz = 95.0
orbass_harmonics = 0.35
orbass_drive = 1.0
EOF

# Copy default config to app resources
cp "$OUTPUT_DIR/StereoFool.ini" "$APP_DIR/Contents/Resources/"

# Create DMG
echo "Creating DMG..."
DMG_PATH="$OUTPUT_DIR/StereoFool-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH" || {
    echo "Failed to create DMG, keeping .app bundle"
}

echo ""
echo "Build complete!"
echo "Output: $DMG_PATH"
echo "App: $APP_DIR"
ls -la "$OUTPUT_DIR/"
