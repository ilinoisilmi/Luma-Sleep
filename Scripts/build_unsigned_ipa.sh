#!/bin/bash
# A real iPhone build requires macOS and Xcode. No signing secrets are used here.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo 'Run this script on macOS with Xcode, or use the included GitHub Actions workflow.' >&2
  exit 1
fi

mkdir -p build/logs build/export
xcodebuild \
  -project LumaSleep.xcodeproj \
  -scheme LumaBasic \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  build 2>&1 | tee build/logs/xcodebuild.txt

python3 Scripts/package_ipa.py \
  build/DerivedData/Build/Products/Release-iphoneos/LumaSleep.app \
  build/export/LumaSleep-unsigned.ipa

echo 'Build succeeded. Sign and install LumaSleep-unsigned.ipa with Sideloadly on Windows.'
