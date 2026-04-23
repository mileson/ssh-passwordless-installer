#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/build/release-bundles"
FINAL_DIR="$BUILD_DIR/final"
WINDOWS_TMP="$BUILD_DIR/windows"

mkdir -p "$FINAL_DIR" "$WINDOWS_TMP"
rm -rf "$WINDOWS_TMP"/* "$FINAL_DIR"/*

cleanup_tmp() {
  rm -rf "$WINDOWS_TMP"
}

trap cleanup_tmp EXIT

"$REPO_DIR/tools_build_macos_apps.sh"

WINDOWS_BUNDLE_DIR="$WINDOWS_TMP/SSH-Passwordless-Setup-Windows"
mkdir -p "$WINDOWS_BUNDLE_DIR"

cp "$REPO_DIR/scripts/windows/setup-passwordless-ssh.bat" "$WINDOWS_BUNDLE_DIR/"
cp "$REPO_DIR/scripts/windows/setup-passwordless-ssh.ps1" "$WINDOWS_BUNDLE_DIR/"
cp "$REPO_DIR/README_CN.md" "$WINDOWS_BUNDLE_DIR/README.md"
cp "$REPO_DIR/README.md" "$WINDOWS_BUNDLE_DIR/README_EN.md"
cp "$REPO_DIR/LICENSE" "$WINDOWS_BUNDLE_DIR/"

(
  cd "$WINDOWS_TMP"
  zip -rq "$FINAL_DIR/SSH-Passwordless-Setup-Windows-Download-Then-Double-Click.zip" "$(basename "$WINDOWS_BUNDLE_DIR")"
)

cp "$REPO_DIR/build/macos-apps/final/SSH-Passwordless-Setup-macOS.zip" "$FINAL_DIR/"

find "$BUILD_DIR" -name '.DS_Store' -delete
find "$FINAL_DIR" -name '.DS_Store' -delete

echo
echo "Final release bundles:"
find "$FINAL_DIR" -maxdepth 1 -type f | sort
