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
# The range bubble: a tap on a route (WM_TAP_AT) puts that route's own date in it, and the bubble
# itself is the way into the workout — the second shot taps it.
shot map_bubble      SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=month SIMCTL_CHILD_WM_JUMP_DISTANCE_M=25 SIMCTL_CHILD_WM_TAP_DELAY=2 "SIMCTL_CHILD_WM_TAP_AT=305,427"
shot map_bubble_open SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=month SIMCTL_CHILD_WM_JUMP_DISTANCE_M=25 SIMCTL_CHILD_WM_TAP_DELAY=2 "SIMCTL_CHILD_WM_TAP_AT=305,427" SIMCTL_CHILD_WM_TAP_BUBBLE=1
shot edit        SIMCTL_CHILD_WM_START_TAB=0 SIMCTL_CHILD_WM_START_DETAIL=1 SIMCTL_CHILD_WM_START_EDIT=1
shot edit_erase  SIMCTL_CHILD_WM_START_TAB=0 SIMCTL_CHILD_WM_START_DETAIL=1 SIMCTL_CHILD_WM_START_EDIT=1 "SIMCTL_CHILD_WM_EDIT_STROKE=94,439;104,488;122,537;146,579;183,608;214,616"
# With the distance rule at 5 m every leg of the sample route is one the ruler catches, so the
# *Jump valid* tool has something to flag — which is the point of the shot.
shot edit_valid  SIMCTL_CHILD_WM_START_TAB=0 SIMCTL_CHILD_WM_START_DETAIL=1 SIMCTL_CHILD_WM_START_EDIT=1 SIMCTL_CHILD_WM_JUMP_DISTANCE_M=5 SIMCTL_CHILD_WM_EDIT_TOOL=valid "SIMCTL_CHILD_WM_EDIT_STROKE=336,415;339,476;323,525;293,561"
# The explorer's result card is the one panel that leaves the map *undimmed*: the suggested routes
# have to be readable while one of them is picked.
shot plan_card     SIMCTL_CHILD_WM_START_TAB=1 SIMCTL_CHILD_WM_START_RANGE=week SIMCTL_CHILD_WM_FAKE_PLAN=1 SIMCTL_CHILD_WM_PLAN_AUTORUN=1 SIMCTL_CHILD_WM_PLAN_KM=3
shot edited_workouts SIMCTL_CHILD_WM_START_TAB=2 SIMCTL_CHILD_WM_START_EDITS=1
shot settings  SIMCTL_CHILD_WM_START_TAB=2
