#!/bin/bash
# Builds the device (arm64) app and packages it as an UNSIGNED .ipa that can be
# re-signed with your own developer account (Xcode, Feather, Sideloadly, ...).
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

xcodebuild \
  -project WorkoutMap.xcodeproj \
  -scheme WorkoutMap \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build-device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="build-device/Build/Products/Release-iphoneos/WorkoutMap.app"
OUT="WorkoutMap.ipa"
rm -rf build-device/Payload "$OUT"
mkdir -p build-device/Payload
cp -R "$APP" build-device/Payload/
# Ad-hoc sign so the entitlements (HealthKit) travel with the binary and
# sideloading tools can merge them into your own profile.
codesign --force --sign - --timestamp=none \
  --entitlements WorkoutMap/WorkoutMap.entitlements \
  build-device/Payload/WorkoutMap.app
(cd build-device && zip -qry "../$OUT" Payload)
echo "Built $(pwd)/$OUT"
