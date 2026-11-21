#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
cd "$(dirname "$0")/.."
DEV="iPhone 18 Pro Max"
OUT=${OUT:-/tmp/shots}
mkdir -p "$OUT"
xcodegen generate >/dev/null
xcodebuild -project WorkoutMap.xcodeproj -scheme WorkoutMap -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEV" -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -3
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1 || true
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/WorkoutMap.app
xcrun simctl privacy booted grant location com.theoccurrence.workoutmap 2>/dev/null || true
xcrun simctl privacy booted grant photos-add com.theoccurrence.workoutmap 2>/dev/null || true
xcrun simctl location booted set 48.1494,11.6347 >/dev/null 2>&1 || true
shot() {
  local name="$1"; shift
  xcrun simctl terminate booted com.theoccurrence.workoutmap 2>/dev/null || true
  sleep 0.6
  env "SIMCTL_CHILD_WM_SAMPLE_DATA=1" "$@" xcrun simctl launch booted com.theoccurrence.workoutmap >/dev/null
  sleep 5
  xcrun simctl io booted screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "shot $name"
}
shot list      SIMCTL_CHILD_WM_START_TAB=0
shot map_week  SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week
shot map_month SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=month
shot map_year  SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=year
shot map_all   SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=all
shot map_run   SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_CATEGORY=run
shot map_ride  SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_CATEGORY=ride
shot modes      SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_MODES=1
shot mode_explore   SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_MODE=explore
shot mode_driving   SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_MODE=driving
shot mode_transit   SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_MODE=transit
shot mode_satellite SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_MODE=satellite
shot sheet_week  SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_START_SHEET=1
shot sheet_month SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=month SIMCTL_CHILD_WM_START_SHEET=1
shot sheet_year  SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=year SIMCTL_CHILD_WM_START_SHEET=1
shot detail    SIMCTL_CHILD_WM_START_TAB=0 SIMCTL_CHILD_WM_START_DETAIL=1
shot export    SIMCTL_CHILD_WM_START_TAB=0 SIMCTL_CHILD_WM_START_DETAIL=1 SIMCTL_CHILD_WM_START_EXPORT=1
shot settings  SIMCTL_CHILD_WM_START_TAB=2
