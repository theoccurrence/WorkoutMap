# WorkoutMap

A 1:1 rebuild of the original **WorkoutMap** iOS app: it reads your walking,
running and cycling workouts from Apple Health, draws their GPS routes on a
desaturated Apple map and lets you filter them by week / month / year.

* Display name: `WorkoutMap`
* Bundle identifier: `com.theoccurrence.workoutmap`
* Built against the **iOS 26 SDK** (Xcode 27), iPhone only, portrait + landscape
* Runs on iPhone and on the folding iPhone Duo (inner and outer display)

## Features

| Tab | What it does |
| --- | --- |
| **Workouts** | Chronological list of every walk / run / ride with distance, date and a small map thumbnail of the route. Tapping a row opens the detail screen. |
| **Map** | All routes of the selected period drawn on a grayscale map, auto-zoomed to fit. A vertical glass toolbar carries share, the week / month / year / all filter (behind a menu) and the locate button, with Walk / Run / Ride as circle buttons on the opposite side. The map can be panned, pinched and turned with two fingers. The share button exports the current map as an image card. |
| **Setting** | Data source (Health), **default period** (the Week / Month / Year / All filter the map opens with), feedback, share app, about, contact. |

Detail screen: map with the route, workout type, date, weather (temperature and
humidity from the workout metadata), then time, distance, elevation, active
calories, average pace and average heart rate, plus a share button that opens the
export card.

Export card: the map with the *Workout Map* title, a 2×2 statistic grid and the
app badge; **Save** writes the card to the photo library.

## Requirements

* macOS with **Xcode 27** (or newer) and the iOS 26 SDK
* [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) – only needed to regenerate the project file
* An Apple ID for signing (a free account works; HealthKit is available to
  personal teams)

## Open and run

```bash
open WorkoutMap.xcodeproj
```

Select your team under *Signing & Capabilities*, then run on a device. The app
asks for Health (workouts + routes) and, when the map is opened, for
location (the blue position dot).

## Build an IPA

```bash
./scripts/make_ipa.sh          # → WorkoutMap.ipa (unsigned)
```

The script builds the `Release` configuration for `generic/platform=iOS` with
code signing disabled and zips the `Payload/` folder, which is the layout every
sideloading tool expects. Sign it with your own account:

* **Xcode** – open the project, set your team, *Product ▸ Archive ▸ Distribute*.
* **Feather / Sideloadly / AltStore** – drag the `.ipa` in and sign with your
  certificate. Make sure the **HealthKit** capability stays enabled; the app
  declares `com.apple.developer.healthkit` in
  `WorkoutMap/WorkoutMap.entitlements`.

## Simulator / UI development

The app can be driven without any Health data through launch environment
variables (Debug builds only):

| Variable | Effect |
| --- | --- |
| `WM_SAMPLE_DATA=1` | Replaces Health data with a fixed set of sample workouts and routes |
| `WM_START_TAB=0\|1\|2` | Opens the Workouts / Map / Setting tab |
| `WM_START_RANGE=week\|month\|year\|all` | Pre-selects a map range |
| `WM_START_CATEGORY=walk\|run\|ride` | Pre-selects a category filter |
| `WM_START_SHEET=1` | Opens the calendar picker |
| `WM_START_DETAIL=1` | Pushes the first workout's detail screen |
| `WM_START_EXPORT=1` | Opens the export card |
| `WM_SKIP_LOCATION=1` | Skips the location prompt (screenshots) |
| `WM_FAKE_LOCATION="lat,lon"` | Publishes a fixed position (checks the dot) |
| `WM_STRESS=N` | Replicates the sample workouts N times, `WM_STRESS_SPREAD` degrees apart (map performance) |

`./scripts/sim_shots.sh` builds, installs and captures every screen into
`/tmp/shots` – handy for comparing against the original screenshots.

## Architecture

```
WorkoutMap/
  Model/       Workout, WorkoutCategory, TimeRange (week/month/year/all), RouteGeometry
  Services/    HealthStore (HealthKit), RouteStore (route fetch + disk cache),
               LocationProvider, MapImageRenderer (map snapshots), DebugSampleData
  Theme/       Palette (measured colours), Metrics (measured geometry), Formatters
  Views/       RootView (TabView), WorkoutsListView, WorkoutCardView, WorkoutDetailView,
               MapTabView, RouteMapView, RangePickerSheet, ExportPreviewView, SettingsView
```

Notes on the map rendering, all measured from the original app:

* The map is **desaturated** by two blend-mode overlays that MapKit composites
  *inside* its own render pass (`ToneOverlay`: grey at `saturation`, then black at
  20 %), and the routes are `MKPolyline` overlays added after them so they keep
  their colour. Routes, tone and tiles therefore share one pass and stay glued to
  each other while the map is panned, pinched or rotated. Neither a `CALayer`
  filter above the map view (VectorKit renders tiles and overlays into one Metal
  layer, so it would grey the routes out too) nor a route layer positioned from
  `visibleMapRect` callbacks (VectorKit renders a frame ahead of the main thread,
  so it always trails the map) can do that. Snapshots (card thumbnails, export
  card) run the same tone mapping on the pixels.
* Card thumbnails frame the route with a **100 m margin** and then extend the
  rect to the thumbnail's aspect ratio, so a route occupies roughly the same
  fraction of every card.
* The map fits the filtered routes with a **1.8× span** (40 % margin on each
  side) whenever the range or the category changes and the user has not panned.
* **Screens with a system side rail** (the iPhone Duo reserves 84 pt for its status
  and tab bar; a notched iPhone held sideways only 62, hence `Metrics.railInset = 70`)
  get the system toolbar: `MapTabView` puts share / calendar / range in `ToolbarItem`s
  inside the screen's `NavigationStack`, and the system places them in its own vertical
  bar — the same column as the tab bar, above it, scaling with the status cluster — so
  the rail follows the system geometry (pose, orientation, Live Activity) and the items
  pick up the system's glass toolbar style with **neutral white glyphs** (only the tab bar
  carries the accent). The locate action is a second `ToolbarItem` at `.bottomBar`
  placement, which gives it a bubble of its own beneath the pill.
  Screens **without** such a rail — the unfolded inner panel, and any portrait iPhone —
  get the same column **placed by hand** at the bottom trailing corner
  (`MapTabView.mapToolbar`), in the same glass shape and with its bottom edge on the tab
  bar's top edge: the system only offers a vertical bar where it reserves a side inset, and
  there is nowhere else to put one at the bottom of a portrait screen. The grey top bar
  (`MapTabView.toolbar`) is gone with it.
  When the rail is too short for share + calendar + range the two filters fold into one
  `ellipsis` overflow menu, so share stays and the column still fits. That state
  (`compactWanted`) only trips on the folded cover panel held sideways — its content column
  is 382 pt wide and 620 pt tall in portrait, ~445 pt tall in landscape, against the
  unfolded panel's ~650 pt — so the overflow never appears when the phone is unfolded.
  **The items stay system items — do not hand-place this column.** The system positions them
  itself (below the status cluster, clear of the camera cut-out and of a Live Activity) and
  re-lays them out on every turn. A hand-placed overlay — it was tried once, on the folded
  panel — sits at a fixed offset, drifts out of line with the tab bar underneath it and runs
  under the clock as soon as a Live Activity is live; it has none of the system's dynamics.
  And since the *set* of items is the only lever, it must not change while the system is
  moving the rail: an item set that changed mid-turn made the bar rebuild itself, and the
  whole rail — the system's own tab bar included — was gone for a moment on every turn. So
  `MapTabView.scheduleRailCompact` hands the new set over only once the window has stopped
  moving (120 ms after the last geometry change).
  **What the transition can and cannot be** — measured, with three routes tried:
  * The item *set* is the only lever, and it may only change once the window is still.
    Mid-turn the host rebuilds the rail while it is relocating it and the whole rail, tab bar
    included, is missing for a moment; at rest the host brings the new pill in with an
    animation of its own, and that animation is all there is.
  * One `ToolbarItem` whose *content* changes, instead of a set that changes, does not work:
    the glass around the item is measured when it is inserted and never again, so it keeps
    the height of the state before — clipped glyphs one way round, an empty capsule the other
    (tried with the pill's height and its icons decoupled, deferred and immediate, with and
    without an explicit frame).
  * An item's content cannot be animated at all: `.animation(_:value:)` and `.transition(…)`
    inside a `ToolbarItem` never reach the UIKit bar, which swaps the content in one frame.
    That is why the `.scale` / `.move` / `.opacity` experiments were indistinguishable from
    no animation at all.
  * A pill of our own would animate properly, but loses the system's placement — see above.
  The range bubble is a capsule with the measured grey label (14 pt, `Palette.rangeLabel`)
  pinned to the top of the display, the same gap to the screen edge in every layout.
* The **Walk / Run / Ride filters** are toolbar circles of their own — symbol only, walk at
  the top — on the side *opposite* the toolbar, since the rail sits on the camera cut-out's
  side (so the filters land right when the folded landscape puts the rail left). The lowest
  one ends level with the lowest button of the toolbar column on the other side: down a side
  the tab bar is stacked into that same column, so that is its last tab; with the bar running
  along the bottom the column holds only the locate circle, so it is that. The height comes
  from the bar's capsule, measured at runtime instead of guessed from the safe area. The
  selected one takes its colour in the **symbol**, with a light wash of the same colour behind
  it (`Glass.tint` at 25 %); walk starts selected. The folded landscape puts the bar at very
  different heights in its two rotations, and the bar cannot be measured there at all — a
  parked copy of it is left in the window and reads 105 pt where the bar sits at 23 — so both
  rotations keep to the same fixed edge instead: `Metrics.filterInsetFoldedLandscape`, the
  rail's own 23 pt plus the 4 px (1.33 pt at 3x) that put the filter circles' bottom edge
  exactly level with the platter's. The bar's own position is measured at runtime,
  but a rotation can leave a parked copy of it in the window at a stale position, so a
  measured value outside the plausible range falls back to the measured fixed offset instead
  of flinging the filters across the screen.
* The map view sets `insetsLayoutMarginsFromSafeArea = false`: `MKMapView` fits its camera
  (a route fit, a centred user location) into the view's layout margins, so the safe area
  would push a fitted route set and the user location off centre. MapKit's legal attribution
  therefore sits where MapKit puts it — the bottom leading corner, which the filters leave
  free now that they end on the tab bar's top edge.


* The bottom tab bar is the current system tab bar (Liquid Glass floating bar)
  instead of the legacy flat bar the original app shipped with.
* The Settings screen omits the "WorkoutMap Plus" banner.
