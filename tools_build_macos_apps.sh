#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/build/macos-apps"
FINAL_DIR="$BUILD_DIR/final"
TMP_DIR="$BUILD_DIR/tmp"

APP_NAME="SSH 免密配置器"
BUNDLE_ID="com.chaojifeng.ssh-passwordless-installer"
APP_VERSION="0.1.0"
APP_BUILD="1"
ZIP_NAME="SSH-Passwordless-Setup-macOS.zip"
SCRIPT_PATH="$REPO_DIR/scripts/macos/setup-passwordless-ssh.command"
ICON_SVG="$REPO_DIR/assets/brand/logo.svg"

mkdir -p "$BUILD_DIR" "$FINAL_DIR" "$TMP_DIR"
rm -rf "$TMP_DIR"/* "$FINAL_DIR"/*

create_png_from_svg() {
  local src_svg="$1"
  local out_png="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d "$TMP_DIR/ql.XXXXXX")"
  qlmanage -t -s 1024 -o "$tmp_dir" "$src_svg" >/dev/null 2>&1
  cp "$tmp_dir/$(basename "$src_svg").png" "$out_png"
}

create_icns() {
  local src_png="$1"
  local out_icns="$2"
  local base
  base="$(mktemp -d "$TMP_DIR/iconset.XXXXXX")"
  local iconset="$base/AppIcon.iconset"
  mkdir -p "$iconset"

  sips -z 16 16     "$src_png" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32     "$src_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$src_png" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64     "$src_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$src_png" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256   "$src_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$src_png" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512   "$src_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$src_png" --out "$iconset/icon_512x512.png" >/dev/null
  cp "$src_png" "$iconset/icon_512x512@2x.png"

  iconutil -c icns "$iconset" -o "$out_icns"
}

create_app() {
  local app_dir="$TMP_DIR/$APP_NAME.app"
  local contents="$app_dir/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"
  local icon_png="$TMP_DIR/app-icon.png"

  mkdir -p "$macos" "$resources"
  cp "$SCRIPT_PATH" "$resources/installer.command"
  chmod 755 "$resources/installer.command"

  create_png_from_svg "$ICON_SVG" "$icon_png"
  create_icns "$icon_png" "$resources/AppIcon.icns"

  cat > "$macos/launcher" <<'EOS'
#!/bin/bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$APP_DIR/Resources/installer.command"
chmod 755 "$SCRIPT_PATH"
open -a Terminal "$SCRIPT_PATH"
EOS
  chmod 755 "$macos/launcher"

  cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>launcher</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

  /usr/libexec/PlistBuddy -c "Print" "$contents/Info.plist" >/dev/null
  echo "$app_dir"
}

zip_unsigned_app() {
  local app_dir="$1"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$FINAL_DIR/$ZIP_NAME"
}

sign_notarize_zip() {
  local app_dir="$1"
  local identity="$2"
  local notary_profile="$3"

  codesign --force --deep --options runtime --timestamp --sign "$identity" "$app_dir"
  codesign --verify --deep --strict --verbose=2 "$app_dir"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$TMP_DIR/$ZIP_NAME"
  xcrun notarytool submit "$TMP_DIR/$ZIP_NAME" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$app_dir"
  spctl --assess --type execute -vv "$app_dir"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$FINAL_DIR/$ZIP_NAME"
}

APP_DIR="$(create_app)"

if [[ -n "${CODESIGN_IDENTITY:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  echo "Signing and notarizing app..."
  sign_notarize_zip "$APP_DIR" "$CODESIGN_IDENTITY" "$NOTARY_PROFILE"
else
  echo "Building unsigned app zip..."
  zip_unsigned_app "$APP_DIR"
fi

find "$FINAL_DIR" -name '.DS_Store' -delete

echo
echo "Final artifact:"
find "$FINAL_DIR" -maxdepth 1 -type f | sort
