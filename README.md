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
| **Map** | All routes of the selected period drawn on the map, auto-zoomed to fit. A vertical glass toolbar carries share, the week / month / year / all filter (behind a menu) and a two-button pill — the map style picker above the locate button, as in Maps — with Walk / Run / Ride as circle buttons on the opposite side. The map can be panned, pinched and turned with two fingers. The share button exports the current map as an image card. The position marker carries a translucent cone — in the colour of the selected category — showing the way the user faces, and moves smoothly between fixes instead of jumping once a second. Tapping a route on the map shows that route's own date and time in the range bubble at the top (`DD.MM.YYYY - hh:mm`); tapping the map itself brings the range's label back. |
| **Map styles** | Apple Maps' own *Map Modes* panel: **Explore**, **Driving** (live traffic), **Transit** (stations only), **Satellite** (imagery) and **Legacy** — the grey map the app shipped with, which is also what it opens with. Each tile is Maps' own artwork for the style (the grey Explore tile for **Legacy**), so the panel is complete the moment it opens. The choice is kept in the settings, and the detail screen and the export card draw the map in it as well. The map itself — and every preview of it — is drawn in the system's own light or dark style, or in the one pinned under *Map Appearance*; **Legacy** is the grey map the app shipped with and stays dark either way. |
| **Settings** | Data source (Health), **default period** (the Week / Month / Year / All filter the map opens with), **map appearance** (light / dark / system — the map alone; the rest of the app stays dark), feedback, share app, about, contact. |

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
| `WM_START_MODE=explore\|driving\|transit\|satellite\|legacy` | Opens the map in that style |
| `WM_START_MODES=1` | Opens the map style picker |
| `WM_START_APPEARANCE=system\|light\|dark` | Draws the map light or dark (checks the appearance setting) |
| `WM_TAP_AT="x,y"` | Fires one tap on the map at those screen points (checks the route tap and the range bubble) |
| `WM_START_DETAIL=1` | Pushes the first workout's detail screen |
| `WM_START_EXPORT=1` | Opens the export card |
| `WM_SKIP_LOCATION=1` | Skips the location prompt (screenshots) |
| `WM_FLIP_MODES=<seconds>` | Switches the stored map style between Explore and Legacy every that many seconds (checks the controls' own light/dark transition) |
| `WM_ROTATE=landscapeRight,portrait` | Turns the device through those orientations, 4 s apart (there is no Simulator UI to drag in this setup) |
| `WM_FAKE_LOCATION="lat,lon"` | Publishes a fixed position (checks the dot) |
| `WM_FAKE_HEADING=<degrees\|cycle>` | Stands in for the compass (checks the cone, and that it turns while the dot stands still) |
| `WM_FAKE_DEVICE_ORIENTATION=portrait\|upsideDown\|landscapeLeft\|landscapeRight` | Stands in for the pose the compass correction is computed from |
| `WM_STRESS=N` | Replicates the sample workouts N times, `WM_STRESS_SPREAD` degrees apart (map performance) |

`./scripts/sim_shots.sh` builds, installs and captures every screen into
`/tmp/shots` – handy for comparing against the original screenshots.

## Architecture

```
WorkoutMap/
  Model/       Workout, WorkoutCategory, TimeRange (week/month/year/all), RouteGeometry,
               MapMode (Explore / Driving / Transit / Satellite / Legacy)
  Services/    HealthStore (HealthKit), RouteStore (route fetch + disk cache),
               LocationProvider, MapImageRenderer (map snapshots), DebugSampleData
  Theme/       Palette (measured colours), Metrics (measured geometry), Formatters,
               SystemAppearance (the phone's own light/dark style)
  Views/       RootView (TabView), WorkoutsListView, WorkoutCardView, WorkoutDetailView,
               MapTabView, RouteMapView, RangePickerSheet, MapModeSheet, ExportPreviewView,
               SettingsView
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
  card) run the same tone mapping on the pixels — for the modes that have it.
* The **map style** is `MapMode`: Apple Maps' four modes plus `legacy`, the grey map
  the app shipped with and the one it opens with, so nothing changed for anyone who
  does not pick another. MapKit has no switch per mode, so each entry is the closest
  configuration it does have — standard with normal emphasis for Explore, the same
  with `showsTraffic` for Driving, the same with only `.publicTransport` points of
  interest for Transit (MapKit draws the transit lines itself on the standard map and
  has no switch for them), `MKImageryMapConfiguration` for Satellite, and the muted
  standard map with every point of interest excluded for Legacy. The tone pass belongs
  to Legacy alone and is switched **inside the renderer** (`ToneOverlay.active`)
  instead of being removed and re-added: MapKit draws the overlays of one level in the
  order they were added, so a tone pass re-added after a mode change would land above
  the routes and grey those out with it. Snapshots follow the mode
  (`MapImageRenderer.image(mode:)`), the export card with them, and the detail screen
  reads the stored style too; only the list thumbnails keep their measured grey card
  look. The picker's five tiles are **bundled artwork** (`MapMode.artwork(for:)`), one
  image per style and appearance: five `MKMapSnapshotter` runs per opening, arriving one by
  one while the panel sat half empty, was what the panel used to be, and the artwork is what
  Maps itself shows. `MapImageRenderer.modeThumbnail` and `MapMode.previewTone` went with it.
  The tiles are square and take everything the sheet
  has to give up to 96 pt (a 12 pt inset and an 8 pt gap between them, so the row fills the
  card instead of leaving wide margins). On the folded panel the sheet's *content* is laid
  out beside the rail — measured: a 374 pt content area in a 466 pt card, 76 pt narrower —
  and a row centred in there sits visibly off to one side (which side depending on where the
  rail is), so the panel ignores the container's horizontal safe area: the card covers that
  strip anyway.
* The **map's light/dark style** is `MapAppearance` (Setting ▸ *Map Appearance*): `system`,
  `light` or `dark`, resolved against the phone's own setting. The app itself is pinned to dark
  (`WorkoutMapApp`'s `.preferredColorScheme(.dark)`; the plist's `UIUserInterfaceStyle` was
  dropped for it, so that one trait stays dark), so the map carries its own style instead of
  inheriting it: `MKMapView.overrideUserInterfaceStyle` for the live map, and
  `MKMapSnapshotter.Options.traitCollection` for the snapshots behind the map-mode tiles and the
  export card — one `interfaceStyle` threaded through both. The *phone's* style cannot be read
  from any trait the app can see (the window, the scene and `UITraitCollection.current` all
  report dark under the pin — measured), so `SystemAppearance` reads the **screen's** trait
  (`windowScene.screen`), which still follows the system. Nothing publishes that trait:
  `UIScreen` is not `UITraitChangeObservable`, and KVO on its `traitCollection` reports the
  value once and never again (checked). Waiting for the next activation is what it used to do,
  and that is exactly what the screen did *not* want: the setting is changed in Control Center
  or in Settings, both of which leave the app inactive but still drawing, and Maps turns while
  Control Center is still open. So the screen is read on a 0.2 s poll while the app is on
  screen — one property read, and the map answers the system's own switch as it happens. The
  map cannot fade that answer itself: MapKit swaps its tiles in one frame, and `UIView.transition`
  over the map view has nothing to snapshot (its tiles are drawn by a Metal layer — measured,
  the cross-dissolve never appeared). So the screen lays a **wash** of the style it came from
  over the whole screen for 0.45 s (`MapTabView.washAppearanceChange`), which the map *and its
  controls* change underneath; the wash is stepped rather than handed to `withAnimation`, because
  a state that is taken back in the same turn it is set never reaches the screen at all
  (measured). `legacy` is
  the one exception: the grey map the app shipped with keeps the dark style it has always had,
  live and in its preview, whatever the setting says. Measured end to end: `explore` is a light
  map on a light phone and a dark one on a dark phone, a pinned style overrides the system either
  way, `legacy` stays dark on a light phone, and the five map-mode tiles follow the same rule.
* The map screen's **own controls** are drawn in the same style as the map: light glass on a
  map drawn light, dark glass otherwise — and `legacy`, the grey map the app shipped with, is
  never light, so it keeps the dark controls whatever the setting says. `controlsAreLight` is the
  whole of it (the map's own `interfaceStyle`), and it drives the rail items' glyph colour *and*
  their `.toolbarColorScheme` — the one lever that turns the system bar's own glass — the
  hand-placed column and the filter circles, and the range bubble (`Palette.surfaceLight` and
  `rangeLabelLight`). Two things are worth knowing before touching it:
  * the hand-placed controls' glass resolves its light or dark material **when it is inserted**
    and is not re-resolved when the colour scheme changes afterwards (measured: the same view
    stayed dark under a changed `\.colorScheme`), so it needs the rebuild `.id(controlsAreLight)`
    gives it — and the wash covers that rebuild.
  * the tab bar is the app's own control rather than the screen's and is told separately
    (`ControlAppearance`): in the light style its selected item is the system's own blue instead
    of the app's yellow accent, and `RootView` honours it only while the map tab is the one in
    front, because the app's own design is dark.
  Switching between the two — the system's own appearance change, or a map style change to or
  from `legacy` — is what the wash above is for: the controls turn underneath it as the map does,
  so both leave together (measured through a run that alternated Explore and Legacy).
* The **position dot** is an annotation of our own, so MapKit does not animate it the
  way it animates its built-in user location: every fix would teleport it. And there is
  no faster stream to wait for — a fix arrives about once a second, which is what the
  receiver has to give (`LocationProvider` asks for the most there is:
  `kCLLocationAccuracyBestForNavigation`, no distance filter, no automatic pause —
  measured at 1.007 s between fixes), because a phone's GPS has no 60 Hz to offer. The
  dot is therefore walked by hand at the display's own rate: every fix starts a step
  from where the dot currently is to that fix, over the interval the previous fix took,
  on a `CADisplayLink` that stops the moment the dot has caught up. It runs one fix
  behind reality and lands just as the next one arrives (measured: 301 frame pairs over
  a 5 s run, not one frame without motion, 199.6 m/s implied against the 200 m/s the
  simulator was told to walk). A gap of more than 3 s is not a stream of positions —
  the screen was away, and the dot has a city to cross — so it jumps to the fix instead
  of sliding. The app declares `CADisableMinimumFrameDurationOnPhone`: without it a
  ProMotion screen caps the app at 60 Hz.
  The dot also carries the **translucent cone** Maps draws in front of it: a 34 pt sector,
  filled with a radial gradient in the colour of the selected category (walk yellow, run
  orange, ride green), fading from 45 % at the dot to nothing at its tip. It points at the way
  the **user** faces, and falls back to the fix's course only when there is no compass reading
  at all (a magnetometer disturbed by a bus or a tunnel). Neither known, and the cone leaves the
  screen rather than pointing at something nobody measured.
  `CLHeading` reports the bearing of the **top of the device**, so the device's own rotation has
  to come back out of it: turn the phone sideways in the hand and its top edge points 90° away
  from the way its user faces — which is what the cone is about. `LocationProvider` therefore
  adds the pose's rotation back (`correction(for:)`: landscapeLeft +90, landscapeRight −90,
  upside down +180, portrait 0) and watches `UIDevice.orientationDidChangeNotification`, so
  turning the phone re-points the cone at once instead of at the next fix.
  That correction is keyed on the **device** pose, *not* on the interface orientation: the Duo's
  inner display is laid out wide while the device itself stays upright, so the two disagree in
  exactly the pose the user holds the unfolded phone in — an interface-keyed correction turned
  the cone 90° there, and in the rotated poses it was inverted on top. Portrait is the natural
  pose of both of the Duo's displays, which is why nothing is added for it.
  Measured end to end with compass and pose both stubbed (`WM_FAKE_HEADING`,
  `WM_FAKE_DEVICE_ORIENTATION`): a heading of 90° with the four poses puts the cone at
  90° / 0° / 180° / 270° — the 90° steps the field test was missing.
  Two things that look reasonable and are wrong, tried and reverted:
  * A correction keyed on `UIWindowScene.interfaceOrientation` — see above, and its sign is the
    inverse of the device pose's.
  * A bearing derived from the last pair of fixes as a fallback direction. It keeps pointing
    down the road the receiver last saw, long after the user has stopped and past the turn the
    bus took, which is the "twisted cone" the field test showed.
  The wheel is turned on every map frame (`mapViewDidChangeVisibleRegion`) and on every heading
  or pose change, because a cone drawn in the screen's frame has to follow the camera's heading,
  and the angle is kept unwrapped so 350° to 10° turns 20° and not the long way round.
  The turn itself is not animated per update: the drawn angle is chased on a `CADisplayLink`
  (exponential, 63 % per 120 ms), so a heading that arrives in steps — the compass reports at
  roughly 1 Hz, and `headingFilter = 1` keeps it from being any coarser — is followed
  continuously instead of restarting a fixed animation at every step. Measured after a 90°
  step: the cone is still moving for about a second across frames (pixel change 1015 → 278 →
  54 → 0 per 0.35 s) and an intermediate frame shows it mid-swing, which a fixed-duration snap
  cannot do. A heading change smaller than half a degree is not published at all, so a standing
  compass does not redraw the screen.
  `simctl` reports a course but never a heading (no magnetometer), so in the simulator the cone
  shows up on the course path and the two stubs stand in for the compass.
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
  carries the accent). The map style and the locate action are two more `ToolbarItem`s at
  `.bottomBar` placement, which the system puts in one bubble of their own beneath the
  pill — the same two-button pill the hand-placed column draws (map style above, locate
  below).
  Screens **without** such a rail — the unfolded inner panel, and any portrait iPhone —
  get the same column **placed by hand** at the bottom trailing corner
  (`MapTabView.mapToolbar`), in the same glass shape and with its bottom edge on the tab
  bar's top edge: the system only offers a vertical bar where it reserves a side inset, and
  there is nowhere else to put one at the bottom of a portrait screen. The grey top bar
  (`MapTabView.toolbar`) is gone with it.
  The rail declares one of **three sets**, and it chooses between them from the window's own
  geometry — not by watching what the system does with them:
  `full` — share, the calendar and the range, and the map style above the locate action in a
  bubble of their own; `filtersFolded` — share and one overflow menu carrying the calendar and
  the range, the map style and the locate action untouched; and `compact` — share, the calendar,
  the range *and* the map style behind that menu, the locate action alone in its bubble.
  `compact` is the short rail's own set (`shortRailWanted`: the folded cover panel held sideways
  — its content column is 382 pt wide and 620 pt tall in portrait, ~445 pt tall in landscape,
  against the unfolded panel's ~650 pt, so this never trips when the phone is unfolded).
  `filtersFolded` is the folded cover panel's rail, upright (`isFoldedPanel`), and it is what
  that rail can hold. Its status cluster is a *vertical* strip — the clock, the battery and the
  badge turn with the rail — and it takes most of the rail's height (measured: the rail's own
  top sits ~370 pt down a 678 pt screen), which leaves the rail room for the filters' set but
  not for the full one. Without a Live Activity the full set fits there by a hair; a Live
  Activity grows the cluster, and the system folds what no longer fits into an `ellipsis` of its
  own — measured on that panel, it folds the **map style and the locate action**, the pill the
  screen is for, away with it. No API says a Live Activity is there, and reading it off the rail
  (the system showing fewer items than the declared set: `railItems`, polled every 0.15 s) left
  that wrong pill on screen for the quarter second the answer took, after every Live Activity.
  A rail the full set only *just* fills is not one to declare a full set on: the rail declares
  the set the window can hold whatever the status cluster does, and the cluster can no longer
  change the layout at all. The cost is that this rail shows the filters folded even while the
  cluster is at rest, where the full set fits — two buttons sit one tap deeper, and the layout
  is the same in every state.
  The rail is not measured at all any more: `FittableMapView` reports the window's safe area and
  the tab bar's capsule — both needed elsewhere — and nothing else, and the 0.15 s poll the Live
  Activity needed is gone with it.
  **The items stay system items — do not hand-place this column.** The system positions them
  itself (below the status cluster, clear of the camera cut-out and of a Live Activity) and
  re-lays them out on every turn. A hand-placed overlay — it was tried once, on the folded
  panel — sits at a fixed offset, drifts out of line with the tab bar underneath it and runs
  under the clock as soon as a Live Activity is live; it has none of the system's dynamics.
  And since the *set* of items is the only lever, it must not change while the system is
  moving the rail: an item set that changed mid-turn made the bar rebuild itself, and the
  whole rail — the system's own tab bar included — was gone for a moment on every turn. So
  `MapTabView.scheduleRailSet` hands the new set over only once the window has stopped
  moving (120 ms after the last geometry change) — except the first set the rail is ever
  handed, which goes over at once so the rail never opens on a set the window cannot hold.
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
  along the bottom the column holds only the two-button pill, so it is the locate button at its
  foot. The height comes
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
  Tapping the filter that is already on is a **no-op**: it must not turn the filter off, because
  an empty filter falls back to walking's routes and a reload re-zooms the map, so a second tap
  on Walk used to deselect it and change nothing but the camera. Measured with the toggle put
  back: a second tap on Walk re-zooms and drops the circle's wash; with the guard in place the
  frame is byte-identical (0 of 3.8 M pixels differ).
* The map view sets `insetsLayoutMarginsFromSafeArea = false`: `MKMapView` fits its camera
  (a route fit, a centred user location) into the view's layout margins, so the safe area
  would push a fitted route set and the user location off centre. MapKit's legal attribution
  therefore sits where MapKit puts it — the bottom leading corner, which the filters leave
  free now that they end on the tab bar's top edge.


* The bottom tab bar is the current system tab bar (Liquid Glass floating bar)
  instead of the legacy flat bar the original app shipped with.
* The **Map tab carries the app's own glyph** (`MapTab`, a template image) instead of an SF
  Symbol. The tab bar draws a custom image at its **intrinsic** point size — a SwiftUI
  `.resizable().frame(…)` on the label changes nothing (measured: identical ink before and
  after) — so the glyph's own padding is what sets its size, and the original 24 pt bitmap
  carried 3–4 pt of transparent margin on each side: its ink was 18 × 16 pt against the ~24 pt
  ink of the neighbouring SF Symbols, which is why it read small. The bitmaps are trimmed and
  scaled to fill the box (ink 23 × 21 pt at 1x/2x/3x), so the tab now matches: measured 22 pt
  of ink against the gear's 24, up from 16.7.
* The Settings screen omits the "WorkoutMap Plus" banner.
