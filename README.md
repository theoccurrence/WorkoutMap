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
| **Explore** | A route planner for ground the user has never covered. Its own circle sits above the Walk / Run / Ride filters with **twice the gap** between the three, so it reads as a group of its own — binoculars in its own blue while it is on, the same glass circle otherwise. It opens a panel: **Loop** (starts and ends at the current position) or **To a destination** (a search result, or the pin dropped by pressing and holding the map), and how many kilometres. A plan comes back as Apple Maps' blue route with as many washed-out alternates as *Routes Suggested* asks for, and a card carrying the distance, the share of *new ways* and the expected time, with **Go** to keep it on the map. Tapping one of the alternates on the map picks it, the same as tapping its pill on the card. Once Go is tapped the map shows that one route alone and the Go and the cross give way to a red **Stop**; the card can be swiped up out of the way without ending anything, and the binoculars bring it back — or open the panel again to plan another one. The route stays until Stop, a new plan, or a relaunch. The pin carries an info bubble with the name the geocoder resolved, the address, **how far away it is** (live, as the user walks) and a bin to remove it. The Walk / Run / Ride filters keep working underneath and independently: a category filter and the explorer can both be on at once. |
| **Settings** | Data source (Health), **default period** (the Week / Month / Year / All filter the map opens with), **map appearance** (light / dark / system — the map alone; the rest of the app stays dark), **gps jumps** (dotted grey / hidden / solid — how a leg the receiver invented while it had no fix is drawn, see below), **mode colors** (the primary colour of Walk, Run and Ride — the routes, the position dot and its cone, and each mode's filter button — chosen in the system colour picker with its spectrum, sliders and hex field, plus *Reset to Defaults*), **explore** — how many routes are suggested (1–5), a **route shape** slider from *Wide* (a few long legs that reach far out) to *Tight* (many short ones that fill the streets around the route) and a **new ways** slider (10 %–100 %) for how much of the route should be ground the user has never covered — feedback, share app, about, contact. |

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
| `WM_START_JUMP_STYLE=dotted\|hidden\|solid` | Draws a GPS jump as a dotted grey line, not at all, or as the straight line the data holds |
| `WM_SAMPLE_JUMPS=1` | Splices one errant fix into the sample routes (checks the GPS-jump setting) |
| `WM_TAP_AT="x,y"` | Fires one tap on the map at those screen points (checks the route tap and the range bubble) |
| `WM_MODE_COLORS="walk=FF00FF,run=00FFFF,ride=0000FF"` | Writes Walk / Run / Ride colours at launch through the same store the picker uses |
| `WM_RESET_MODE_COLORS=1` | Puts Walk / Run / Ride back to their shipped colours at launch (checks *Reset to Defaults*) |
| `WM_START_DETAIL=1` | Pushes the first workout's detail screen |
| `WM_START_EXPORT=1` | Opens the export card |
| `WM_SKIP_LOCATION=1` | Skips the location prompt (screenshots) |
| `WM_FLIP_MODES=<seconds>` | Switches the stored map style between Explore and Legacy every that many seconds (checks the controls' own light/dark transition) |
| `WM_ROTATE=landscapeRight,portrait` | Turns the device through those orientations, 4 s apart (there is no Simulator UI to drag in this setup) |
| `WM_FAKE_LOCATION="lat,lon"` | Publishes a fixed position (checks the dot) |
| `WM_FAKE_HEADING=<degrees\|cycle>` | Stands in for the compass (checks the cone, and that it turns while the dot stands still) |
| `WM_FAKE_DEVICE_ORIENTATION=portrait\|upsideDown\|landscapeLeft\|landscapeRight` | Stands in for the pose the compass correction is computed from |
| `WM_START_PLANNER=1` | Opens the explorer's panel |
| `WM_PLAN_MODE=loop\|destination` | Pre-selects the explorer's mode |
| `WM_PLAN_KM=5` | Pre-fills the explorer's distance |
| `WM_PLAN_AUTORUN=1` | Plans a route straight after launch (checks the whole path without the panel) |
| `WM_PLAN_GO=1` | Taps Go as soon as a route has been planned |
| `WM_PLAN_SHAPE=0\|0.5\|1` | Pre-sets the explorer's route shape (checks the wide/tight setting) |
| `WM_PLAN_ROUTES=1..5` | Pre-sets how many routes are offered |
| `WM_PLAN_NEW=0.1..1` | Pre-sets the share of the route that should be new ground |
| `WM_TAP_DELAY=<seconds>` | Moves the `WM_TAP_AT` tap back, so it can land after a plan has arrived |
| `WM_HIDE_CARD=1` | Swipes the explorer's result card away a few seconds after it appears |
| `WM_SELECT_PIN=1` | Opens the dropped pin's info bubble (the simulator cannot tap the map from the command line) |
| `WM_FOCUS_SEARCH=1` | Focuses the explorer's search field at launch, so the room the keyboard leaves the panel can be seen |
| `WM_PIN_DELETE=1` | Fires that bubble's bin a moment later, through the delegate method the bin calls |
| `WM_FAKE_PLAN=1` | Replaces `MKDirections` with a fixture, so the explorer runs without a network |
| `WM_FAKE_PIN="lat,lon"` | Drops the destination pin at launch |
| `WM_STRESS=N` | Replicates the sample workouts N times, `WM_STRESS_SPREAD` degrees apart (map performance) |

`./scripts/sim_shots.sh` builds, installs and captures every screen into
`/tmp/shots` – handy for comparing against the original screenshots.

## Architecture

```
WorkoutMap/
  Model/       Workout, WorkoutCategory, TimeRange (week/month/year/all), RouteGeometry (+ Geo),
               MapMode (Explore / Driving / Transit / Satellite / Legacy), RoutePlan,
               WorkoutRoute (a track and the legs that are GPS jumps), RouteJumpStyle,
               ExploreOptions (the two explorer settings)
  Services/    HealthStore (HealthKit), RouteStore (route fetch + disk cache),
               LocationProvider, MapImageRenderer (map snapshots), DebugSampleData,
               CoverageIndex + CoverageStore (where the user has been), DirectionsClient
               (MKDirections, behind a protocol), RoutePlanner (the explorer's algorithm)
  Theme/       Palette (measured colours), CategoryColorStore (the user's mode colours),
               Metrics (measured geometry), Formatters, SystemAppearance (the phone's own
               light/dark style), ControlAppearance
  Views/       RootView (TabView), WorkoutsListView, WorkoutCardView, WorkoutDetailView,
               MapTabView, RouteMapView, RangePickerPanel, MapModePanel, ExportPreviewView,
               SettingsView, RoutePlannerPanel, PlannedRouteBar
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
  The tiles are square and take everything the panel
  has to give up to 96 pt (a 12 pt inset and an 8 pt gap between them, so the row fills the
  card instead of leaving wide margins). The row is centred on the panel itself: on the folded
  panel the window's rail takes 84 pt of the card's width (measured: a 374 pt content area in a
  466 pt window), and a row centred in the content area beside it would sit visibly off to one
  side — which side depending on where the rail is.
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
  orange, ride green unless changed under *Settings ▸ Mode Colors*), fading from 45 % at the
  dot to nothing at its tip. It points at the way
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
  The rail is handed **every action** and says which of them may go, instead of declaring a set
  of its own: the calendar and the range carry `ToolbarItem.visibilityPriority(.low)`, the share
  action and the locate action `.high`, and the map style is left at the system's own priority.
  That ladder is the order the system folds along, first to go first (iOS 27; an SDK with no Duo
  to put a rail on falls back to the same actions with the system's automatic order). With no
  priority the bar folds what sits lowest — measured on the folded cover panel, that is the **map
  style and the locate action**, the pill this screen is for, while the calendar and the range
  stay, which is what the rail used to be in the habit of showing. The ladder puts the filters
  first instead, and the rest of the order lands the way this screen wants:
  * the folded cover panel's rail, upright, fits the whole set while its status cluster is at
    rest — measured: exactly, three actions in the pill and the map style above the locate action
    in their bubble. A Live Activity grows that cluster by about a button's worth, and the system
    folds the calendar and the range to make the room, in the same pass — the layout the screen
    wants, with nothing to read back;
  * the same rail held sideways is shorter still, and the fold goes on there: the calendar and
    the range, then the map style, and the locate action keeps a button of its own;
  * a rail with room to spare never folds anything.
  The actions used to be declared as one of three **sets** instead, and the set was changed when
  the screen had watched the system fold — `railItems`, the system's own bar buttons counted out
  of the view tree and polled every 0.15 s, answered with the filters folded once the system had
  already shown the wrong pill. That left it on screen for the quarter second the answer took,
  after every Live Activity. The rail is not measured at all any more: `FittableMapView` reports
  the window's safe area and the tab bar's capsule — both needed elsewhere — and nothing else,
  and the 0.15 s poll is gone with them.
  **The items stay system items — do not hand-place this column.** The system positions them
  itself (below the status cluster, clear of the camera cut-out and of a Live Activity) and
  re-lays them out on every turn. A hand-placed overlay — it was tried once, on the folded
  panel — sits at a fixed offset, drifts out of line with the tab bar underneath it and runs
  under the clock as soon as a Live Activity is live; it has none of the system's dynamics.
  The actions themselves may not be re-declared while the system is moving the rail: an item
  set swapped mid-turn made the bar rebuild itself, and the whole rail — the system's own tab
  bar included — was gone for a moment on every turn. Nothing is swapped here any more; the only
  thing that changes about the rail is which actions the system folds, and that is the system's
  own doing, in the pass that makes the room.
  **What the transition can and cannot be** — measured, with three routes tried:
  * An item set re-declared by the screen is the thing that does not work: swapped mid-turn the
    host rebuilds the rail while it is relocating it and the whole rail, tab bar included, is
    missing for a moment. Letting the system fold its own action costs none of that — the fold
    happens in the pass that makes the room, and the host animates the new pill in itself.
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
* The **explorer** plans a walk over ground the user has never covered. Two questions have to
  be answered, and both have a boring answer: *where have I been* is a grid, *what is a real
  route* is `MKDirections`.
  * `CoverageIndex` rasterises every workout route into ~25 m cells — a plain `Set<Int64>` of
    packed latitude/longitude indices. The grid is square in **degrees**, so an east-west cell
    is narrower away from the equator (at Munich's latitude ~17 m against 25 m); the history and
    the candidates run through the same grid, so the *share* of a route that is new is
    unaffected and only the absolute metre figure carries the anisotropy.
  * `CoverageStore` builds that index over **every** workout, not the range the map is filtered
    to: "where have I never been" is not a question about the current filter. The routes already
    on disk are read first, so the first plan is instant; the rest are pulled from Health four
    at a time and folded in, and the panel says so while that is still running.
  * `MKDirections` knows no waypoints, so a route is a handful of point-to-point legs stitched
    into one polyline — and both shapes are a **zigzag sized so its straight-line length is the
    distance asked for**. That is what the *Route Shape* setting steers: how many legs the zigzag
    is made of, not how long it is. A **loop** is a zigzag over a square centred on the start,
    the route turning at each row's far end and coming home; a **destination** is a zigzag along
    the direct line, alternating either side of it. At *Wide* the loop is two long legs out and
    back around the start and the destination is one big bow off the corridor; at *Tight* the
    loop is a **lawnmower over the square the start sits in** and the destination is a handful of
    side streets either side of the way there. Measured on a 5 km loop from the same spot:
    5.87 km reaching ~1.1 km out at *Wide* against 4.81 km filling a ~1.1 km square at *Tight* —
    the distance holds while the shape changes, which is the whole point of the setting.
  * The **new ways** slider is what makes the planner go looking. It is a target rather than a
    guarantee — a route that starts at the front door has to cross the streets around it, and
    those are the ones most likely to be covered already — and it works three ways at once.
    A loop is tried over a **ring of centres around the start**, not only at the start, because
    the ground under the user's feet is the ground they have covered most (a centre too far away
    to be reached and returned within the distance is pruned by the sizing itself). Every turning
    point is then nudged across its row, in both modes, to the **least covered ground within a
    span** — a waypoint a hundred metres to one side can be in a park while this one is on a road
    the user runs every week — which is what a park whose little paths were never walked rewards.
    And the shape is pulled as tight as the slider asks for, since filling the streets around the
    route is how new ground is found. What actually came back is what the card says.
  * Candidates are scored against the coverage grid *before* anything is routed, so only the
    best few ever reach the service, and the routed ones are ranked on the share of the finished
    route that is new ground, how close it lands to the distance asked for, and how recently the
    same walk was suggested from nearby (`PlanHistory`, in `UserDefaults`). The direction, the
    square's size and the turning points are jittered per request, so the same 5 km from the same
    front door does not produce the same walk twice — the *ranking* carries no noise, because it
    is the last word on which route the user is offered first and should be the best of them
    rather than the luckiest. The generator is seedable (`SplitMix64`).
  * A tighter shape turns more often and follows more side streets, so its real length runs
    further ahead of the straight line it was sized on: the road factor carries a slope with the
    setting (1.32 → 1.50). The destination's shape is sized by bisecting its lateral reach, and
    one correction round re-routes the better of the two sides when the first attempt lands more
    than 15 % off.
  * The legs are the request budget. `MKDirections` throttles a burst
    (`MKError.Code.loadingThrottled`), so at most three legs are in flight at once, a throttled
    leg is retried twice with a growing delay, and a plan is capped at 18 legs — which is also
    what caps *Routes Suggested* at three when the shape asks for five legs each. A leg that
    fails outright drops its candidate: a route with a hole in it is not a route.
  * The route is drawn by MapKit like everything else on this screen: the planned lines are
    handed to `RouteMapView` as a second list, added **after** the workout routes (MapKit draws
    one level's overlays in the order they were added, so a planned route always lands on top of
    a workout's instead of disappearing into it), in Apple Maps' blue with a darker casing under
    the selected one and the same blue at 45 % for the alternates. The result card sits **under
    the range bubble** rather than at the foot of the screen, because the foot is where the
    filters and the toolbar live and both have to stay usable while a route is planned. It is a
    full-width card, so unlike the filter column — which simply keeps to the side the rail is not
    on — it cannot dodge a rail: it is held off both screen edges by the window's own safe-area
    insets instead, because its close button was landing under the Duo's rail. Tapping an
    alternate **on the map** picks it — the tap is resolved against the planned lines first,
    since they are drawn on top of the workout routes — and after Go the alternates are not
    drawn at all: the map is the route being walked and nothing else.
  * The card is a state machine with an escape hatch. Before Go it offers the alternates and a
    cross that throws the plan away; after Go there is nothing left to pick between, so the pair
    becomes one red **Stop**. Dragging it up **follows the finger**: the drag writes the card's
    own offset — a swipe that does not keep up with the thumb does not feel like a swipe — and
    only the release decides where it settles, leaving on a spring if it is past a third of the
    way off or was flicked fast enough that it would have got there, and springing back with a
    little overshoot if not. Past the end of its travel, and dragging *down* where there is
    nothing below the resting place at all, the offset is a **rubber band** (`UIScrollView`'s own
    `(x·d·c)/(d + c·x)`) rather than a clamp: the pull still moves the card, by less and less, so
    the edge gives instead of stopping dead. The explorer's button brings it back down, or opens
    the panel again when it is already up. The card clears the top of the screen by its own
    height plus the gap it sits below, so nothing has to be clipped to hide it — clipping the
    overlay column is what used to cut the top off the range bubble.
  * **Every panel of the map screen is glass**, through one modifier (`View.glassPanel()`): the
    explorer's result card, the range bubble and the screen's three menus — the explorer's input
    panel, the calendar picker and the map-style picker. **Liquid Glass** (`glassEffect`) rather
    than a `Material`, because over a dark map a material — even `.ultraThin` — is a grey plate
    with a blur on it: it neither lights its own edge nor reads as glass, while the glass does
    both and still keeps the text readable. The **menus are drawn in the map screen itself**
    (`MapTabView.menuPanel`) rather than presented as sheets, and that is not a style choice: a
    half-height sheet is handed a glass panel of the system's own — Apple's note on adopting
    Liquid Glass: "half sheets are inset from the edge of the display" — and no value of
    `presentationBackground` removes it (measured on iOS 27: the card keeps its blurred panel
    whatever the modifier is told, and only an opaque colour painted over it hides it). That card
    is also the full width of the window, so on the Duo it lies over the rail the screen's toolbar
    and tab registers live in. Drawn in the map screen instead, a menu keeps the width the range
    bubble and the result card keep — reaching the rail without touching it — and is handed the
    room the keyboard leaves it, so it shrinks rather than pushing its own header off the screen.
    The explorer panel's own fields (the search box, the results, the chosen destination) are
    `.thinMaterial` over it, and every panel's close cross is **white** — black read as a hole
    punched in the glass. The flat `Palette.sheetCard` / `Palette.pickerGlass` fills went with
    it. The export card is the one exception: it is a full-screen viewer for the image it
    produces rather than a panel over the map, so it still sits on black.
  * The dropped pin's **info bubble** heads with the name MapKit's reverse geocoder resolved for
    the coordinate, and carries the address and **how far away the pin is** under it, plus the bin.
    The two lower lines are not the annotation's `subtitle`: MapKit drops an annotation's subtitle
    the moment the callout has a `detailCalloutAccessoryView`, so both live in a `UIStackView`
    there instead — which also lets them be written in place, so a bubble left open while the user
    walks towards the pin counts down instead of flickering once a second.
  * The explorer is **independent** of the Walk / Run / Ride filters: it neither selects nor
    clears one, and a walk filter can be on while a planned route is on the map. That is also
    what makes the two comparable at a glance — a filter's routes and a planned route are drawn
    side by side, in their own colours.
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
* **GPS jumps** — the leg of a route the receiver invented while it had no fix, drawn
  straight across houses, gardens and lakes as if it had been walked — are told apart from
  ground the user covered by the only thing that can tell them apart: the fixes carry a
  timestamp, and a leg whose applied speed beats 162 km/h cannot have been travelled
  (`WorkoutRoute.jumps(in:)`; it also has to cover 25 m, so a duplicate fix a metre away in a
  hundredth of a second is not one, and a plain 300 m distance is left as the test for a sample
  with no usable timestamp). Health stores a jump as an ordinary fix — the straight line is
  what a polyline draws between any two fixes, and the impossibility is in the time between
  them — so nothing in the route itself marks it, and the cached route keeps one flag per fix
  beside the coordinates (`WMR1`; a cache file without that header is fetched from Health
  again rather than read as a route without any jumps). *Settings ▸ GPS Jumps* draws them the
  way the Fitness app does — a row of grey **dots**, each a zero-length dash stroked with a
  round cap so the cap is the circle, and both the dot and its spacing measured against the
  width the route itself is drawn at (`RouteJump`) — hides them altogether, or leaves them
  solid as the app drew them before. The walked stretches are split around every jump, which
  costs a handful of polylines per workout and still one overlay — one draw call — per colour
  and dash pattern; each jump line carries the workout's id with a suffix, which a tap cuts off
  again (`Coordinator.baseRouteID`), so picking a route still picks that workout. Snapshots
  (card thumbnails and the export card) stroke the same dots into their pixels, and the
  thumbnail cache key carries the setting so a cached image of the other one does not come
  back.
* The Settings screen omits the "WorkoutMap Plus" banner.
