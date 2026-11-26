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
| **Workouts** | List of every walk / run / ride with distance, date and a small map thumbnail of the route, ordered by date or by length from the control in the header (the choice is kept), and an **Edited** badge on a row whose route has been edited in the app. Tapping a row opens the detail screen; the glass rail at its trailing edge — Share, Edit and Back, the same round glass buttons the map screen's cards carry, hung just above the info cards — returns to the list. The detail screen carries the **eraser** besides its share button: it opens the route editor, where the drawn route can be changed — ground erased, or a GPS jump flagged as ground that really was covered — and kept (see below). |
| **Map** | All routes of the selected period drawn on the map, auto-zoomed to fit. A vertical glass toolbar carries share, the week / month / year / all filter (behind a menu) and a two-button pill — the map style picker above the locate button, as in Maps — with Walk / Run / Ride as the app's own round **glass** buttons on the opposite side. The map can be panned, pinched and turned with two fingers. The share button exports the current map as an image card. The position marker carries a translucent cone — in the colour of the selected category — showing the way the user faces, and moves smoothly between fixes instead of jumping once a second. Tapping a route on the map shows that route's own date and time in the range bubble at the top (`DD.MM.YYYY - hh:mm`), which then carries a chevron and is itself the way into that workout: tapping the bubble opens the workout's own detail screen — the same screen the Workouts list pushes and the settings' edit list opens — while tapping the map itself brings the range's label back. The screen's own menus — the explorer's input, the calendar, the map-style picker — are drawn in the map screen as **cards of the same shape as the sheet the bubble opens** (inset from every edge of the display, corners that follow the display's own), and each **rises from the bottom edge of the display and leaves the same way** over a spring, with the map and the range bubble dimming behind it as it comes — the dim fades in *and* out, and a tap anywhere on it closes the menu. While a menu is up the screen's own controls — the Walk / Run / Ride and explorer circles, the hand-placed toolbar, and on the Duo the system rail itself — are **not on screen at all** (they fade out with the card's own animation and fade back when it leaves), because a card over the map must not have buttons reading through it. The explorer's **result card** is deliberately *not* one of those: it appears without any dimming of its own, because the suggested routes drawn on the map have to stay readable while one of them is picked. |
| **Map styles** | Apple Maps' own *Map Modes* panel: **Explore**, **Driving** (live traffic), **Transit** (stations only), **Satellite** (imagery) and **Legacy** — the grey map the app shipped with, which is also what it opens with. Each tile is Maps' own artwork for the style (the grey Explore tile for **Legacy**), so the panel is complete the moment it opens. The close cross is one of the screen's own **glass circles** (`GlassCircleButton`), in the column its toolbar keeps rather than in the card's own corner. **Satellite** carries the **Labels** toggle under the tiles, as Maps does: on by default — the imagery *with* its labels layer (roads, place names), which is `MKHybridMapConfiguration`, against the bare photograph of `MKImageryMapConfiguration` — written through to the settings, and read by the detail screen, the editor and the exported card as well. It is a **bar of its own**, as Maps draws it — a rounded row (white at 10 %) inset 13 pt from the card's edges, with the label and the switch set 24 pt inside it — and its room is in the panel's height in **every** mode (the card does not change size when the mode changes, which the user asked for): only the bar's contents fade in, for Satellite, over 0.25 s. The choice is kept in the settings, and the detail screen and the export card draw the map in it as well. The map itself — and every preview of it — is drawn in the system's own light or dark style, or in the one pinned under *Map Appearance*; **Legacy** is the grey map the app shipped with and stays dark either way. |
| **Explore** | A route planner for ground the user has never covered. Its own circle sits above the Walk / Run / Ride filters with **twice the gap** between the three, so it reads as a group of its own — binoculars in its own blue while it is on, the same glass circle otherwise. It opens a panel: **Loop** (starts and ends at the current position) or **To a destination** (a search result, or the pin dropped by pressing and holding the map), and how many kilometres. A plan comes back as Apple Maps' blue route with as many washed-out alternates as *Routes Suggested* asks for, and a card carrying the distance, the share of *new ways* and the expected time, with **Go** to keep it on the map — the Go and the cross beside it in the app's **medium** glass size (`.controlSize(.regular)`, 32.5 pt), a size the pair carries on its own. The panel grows and shrinks **with an animation** as the mode changes, and its own close cross is a glass circle like the screen's toolbar. Tapping one of the alternates on the map picks it, the same as tapping its pill on the card. Once Go is tapped the map shows that one route alone and the Go and the cross give way to a red **Stop**; the card can be swiped up out of the way without ending anything, and the binoculars bring it back — or open the panel again to plan another one. The route stays until Stop, a new plan, or a relaunch. The pin carries an info bubble with the name the geocoder resolved, the address, **how far away it is** (live, as the user walks) and a bin to remove it. The Walk / Run / Ride filters keep working underneath and independently: a category filter and the explorer can both be on at once. |
| **Settings** | Data source (Health), **default period** (the Week / Month / Year / All filter the map opens with), **map appearance** (light / dark / system — the map alone; the rest of the app stays dark), **gps jumps** — two independent rules, each *dotted* / *hidden* / *solid*: legs longer than a **distance** threshold (25 m to start with) and legs faster than a **speed** threshold (162 km/h to start with, and past 10 m of ground — a shorter leg is a rounded clock, not a jump), each with its own **colour** for the tone it draws in (the system colour picker and hex, as under *Mode Colors*, with *Reset Colors* beneath them), see below; the combined detection that catches the big ones is fixed and never drawn, **mode colors** (the primary colour of Walk, Run and Ride — the routes, the position dot and its cone, and each mode's filter button — chosen in the system colour picker with its spectrum, sliders and hex field, plus *Reset to Defaults*), **explore** — how many routes are suggested (1–5), a **route shape** slider from *Wide* (a few long legs that reach far out) to *Tight* (many short ones that fill the streets around the route) and a **new ways** slider (10 %–100 %) for how much of the route should be ground the user has never covered, **workout edits** — *Edited Workouts*, its own list of every workout the editor has changed (most recent first, each row naming the workout and saying what was changed to it, with a bin that removes the edit without the workout being opened — a row opens the workout while this device has it), so the settings screen itself stays short however many there are, with *Export Edits* writing them all to a JSON file and *Import Edits* merging such a file in — feedback, share app, about, contact. |

Detail screen: map with the route, workout type, date, weather (temperature and
humidity from the workout metadata), then the six numbers — time, distance,
elevation, active calories, average pace and average heart rate — as cards laid out
**three rows of two standing up and two rows of three lying down**, with the
`*Data from …` line under them, plus a share button that opens the export card. It is
opened in two ways and tells them apart (`WorkoutDetailView.Presentation`): **pushed**,
from the Workouts tab and from the settings' edited list — edge to edge in whatever
container pushed it (see the rail notes below), which inside that settings *sheet* means
the sheet's own card, filled whole rather than inset inside a second time (insetting it
again left the system's fill showing as a grey bar under the card's bottom edge:
measured, the band stays `(28, 28, 30)` whatever `presentationBackground` is told); and
**as the map screen's own card** (`Presentation.card`, `MapTabView.menuLayer`) when the
range bubble opens it, the same card that screen's three menus are — which is what lets
the margin it keeps show the *map* it floats over instead of a sheet's own background,
which runs flush to the display's bottom edge (the one side its card is not inset on) and
cannot be cleared. The
map takes whatever height the cards and that line leave it, rather than a fixed share
of the screen, which is what keeps the sixth card and the source label inside the card
on the smallest display the app runs on.

Export card: the map with the *Workout Map* title, a 2×2 statistic grid and the
app badge; **Save** writes the card to the photo library.

Edit screen: the workout's route with a **brush** on it, opened from the eraser button
on the detail screen, and two tools to say one of two things about a leg. **Eraser**
takes the ground under the brush out of the line — walked legs and GPS-jump lines
alike. **Jump valid** says the opposite about a leg a GPS-jump rule caught: it was
ground the user really covered, so the rules must leave it alone and the map and the
list draw it as an ordinary part of the route. That flag is this app's own business,
so — unlike the eraser, which is invisible everywhere — it *is* shown where it can also
be changed: the workout's own detail screen and this editor draw such a leg in the
route's own colour **dotted**, so it reads as both at once, a piece of the route and a
jump the rules still see. One finger drags the brush — sized on the slider, and drawn
under the finger in the tool's colour — two fingers move the map and a pinch zooms.
*Undo* steps back a stroke, *Clear* puts the whole route back, and *Done* keeps the
edit. Nothing about the workout changes — Health's data cannot be changed, by this app
or the Fitness app — what changes is how the app *draws* the route, and the two sets of
legs are kept as ranges of the route's own leg indices in a small SQLite database in
the app (`RouteEditStore`), so every screen that draws the route draws it that way from
then on.

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
| `WM_START_JUMP_STYLE=dotted\|hidden\|solid` | Sets the distance rule's style (the flag keeps the name it shipped with) |
| `WM_JUMP_DISTANCE_STYLE` / `WM_JUMP_SPEED_STYLE=dotted\|hidden\|solid` | Sets each jump rule's style on its own |
| `WM_JUMP_DISTANCE_M=<metres>` / `WM_JUMP_SPEED_KMH=<km/h>` | Sets each jump rule's threshold on its own |
| `WM_SAMPLE_JUMPS=1` | Splices one errant fix into the sample routes (checks the GPS-jump settings) |
| `WM_TAP_AT="x,y"` | Fires one tap on the map at those screen points (checks the route tap and the range bubble) |
| `WM_TAP_BUBBLE=1` | Taps the range bubble a moment after `WM_TAP_AT`, through the action its button calls (checks the workout opening from the map) |
| `WM_MAP_HEADING=<degrees>` | Turns the map once its camera has been placed (checks the two-finger pan on a turned map) |
| `WM_OPEN_MENU=range\|modes\|plan` | Opens one of the map screen's own menus a few seconds after launch (checks the dimming and the rise) |
| `WM_MENU_DURATION=<seconds>` | Slows that rise down, far enough for a screenshot to catch the card halfway up |
| `WM_CLOSE_MENU=<seconds>` | Closes the menu `WM_OPEN_MENU` opened — or, with `WM_START_WORKOUT_SHEET`, the workout card — that long after it went up, through the call a tap on the dim makes (checks the way it leaves) |
| `WM_START_WORKOUT_SHEET=1` | Opens the workout the range bubble names as one of the map screen's own cards (the flag keeps the name it shipped with) — without a tap on the map |
| `WM_MODE_COLORS="walk=FF00FF,run=00FFFF,ride=0000FF"` | Writes Walk / Run / Ride colours at launch through the same store the picker uses |
| `WM_RESET_MODE_COLORS=1` | Puts Walk / Run / Ride back to their shipped colours at launch (checks *Reset to Defaults*) |
| `WM_START_DETAIL=1` | Pushes the first workout's detail screen |
| `WM_START_EXPORT=1` | Opens the export card |
| `WM_START_EDIT=1` | Opens the route editor on the detail screen it pushes |
| `WM_EDIT_TOOL=eraser\|valid` | Picks the tool the editor opens with |
| `WM_EDIT_STROKE="x,y;x2,y2"` | Runs one stroke of the brush along those screen points, through the path its recognizer uses |
| `WM_EDIT_STROKE_DELAY=<seconds>` | Moves that stroke back, so it can land after the route has loaded |
| `WM_EDIT_SAVE=1` | Writes the edit after that stroke, through the call *Done* makes |
| `WM_EDIT_TOOLS_HIDDEN=1` | Opens the editor with its tools panel already swiped away (checks the chevron that brings it back) |
| `WM_EDIT_TOOLS=<seconds>` | Puts that panel away that long after the screen opens and brings it back the same time later — through the very calls the swipe and the chevron make, since the simulator cannot swipe the panel |
| `WM_PAN="x,y;x2,y2"` | Drives the two-finger pan through the call its recognizer makes (checks the map moving) |
| `WM_PAN_DELAY=<seconds>` | Moves that pan back, so it lands after the map has been laid out |
| `WM_FAKE_PINCH_SCALE=<scale>` | Stands in for a pinch: with a scale away from 1 the pan must leave the camera alone (checks the zoom not being fought) |
| `WM_START_EDITS=1` | Opens the settings screen's list of edited workouts |
| `WM_EDITS_DETAIL=1` | Opens a workout's detail inside that list's navigation stack — the same screen a row pushes — without a tap on a row |
| `WM_EXPORT_EDITS=<path>` | Writes the edits file there at launch (the settings screen's *Export Edits*, without a tap) |
| `WM_IMPORT_EDITS=<path>` | Merges that edits file in at launch (the settings screen's *Import Edits*, without a tap) |
| `WM_SKIP_LOCATION=1` | Skips the location prompt (screenshots) |
| `WM_ZOOM_SPAN=<metres>` | Opens the map centred on the routes at that span instead of fitting them (checks an overlay at one zoom level) |
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
| `WM_SATELLITE_LABELS=0\|1` | Sets Satellite's labels layer at launch (checks the map modes panel's toggle) |
| `WM_PLAN_SHAPE=0\|0.5\|1` | Pre-sets the explorer's route shape (checks the wide/tight setting) |
| `WM_PLAN_ROUTES=1..5` | Pre-sets how many routes are offered |
| `WM_PLAN_NEW=0.1..1` | Pre-sets the share of the route that should be new ground |
| `WM_PLAN_ALGO=tour\|zigzag` | Picks the planner's algorithm (the tour is the proof of concept) |
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
               WorkoutRoute (a track and its per-leg intervals), RouteJumpStyle, JumpRules
               (the two jump rules the settings expose), ExploreOptions (the two explorer
               settings), RouteEdits (the legs the route editor erased and flagged, as index ranges)
  Services/    HealthStore (HealthKit), RouteStore (route fetch + disk cache),
               LocationProvider, MapImageRenderer (map snapshots), DebugSampleData,
               CoverageIndex + CoverageStore (where the user has been), DirectionsClient
               (MKDirections, behind a protocol), RoutePlanner (the explorer's algorithm),
               RouteEditStore (the route edits, in SQLite, and the JSON file they travel in)
  Theme/       Palette (measured colours), CategoryColorStore (the user's mode colours),
               JumpColorStore (the tone each jump rule draws in), Metrics (measured geometry),
               Formatters, SystemAppearance (the phone's own light/dark style), ControlAppearance
  Views/       RootView (TabView), WorkoutsListView, WorkoutCardView, WorkoutDetailView,
               WorkoutEditView (the route editor) + RouteEditsDocument (its JSON file),
               EditedWorkoutsView (the settings screen's own list of edited workouts),
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
* The route editor works in **legs** — not fixes, and not a copy of the trimmed track — and that is
  the whole of why both of its tools work on the GPS-jump lines as well: a dotted jump line *is* one
  leg, so erasing it, or flagging it, is naming one index. Because `WorkoutRoute.drawing` only ever
  emits the legs it is given and never invents one between two fixes an erasure separated, taking a
  stretch out of the route can neither leave a phantom line across the gap nor turn what is left of
  a stretch into a dotted one. The brush's stroke is measured against every leg with the same
  point-to-segment maths the map's own tap hit-test uses (`Geo.pointToSegmentSquared`), with the
  radius — 12–70 pt, set on the slider — converted into the map's own units at the zoom it is used
  at, so a brush of a fixed size on the screen covers the ground the finger does. The stroke is
  walked in steps smaller than the radius, because a jump leg can be hundreds of metres long and a
  stroke across its middle has to catch it without the finger touching either end.
* Two edits, and they are deliberately **not** shown alike. `RouteEdits.erased` is ground the line
  leaves out everywhere. `RouteEdits.validated` is the opposite statement — "this jump really
  happened" — so the map, the list and their thumbnails draw such a leg as an ordinary part of the
  route (that is the point of flagging it), while the two screens whose business the flag is, the
  workout's detail screen and the editor itself, still draw it as the jump it is: in the route's own
  colour, **dotted**, which reads as both facts at once and is a mark nothing else in the app uses
  (the rules' own tones stay grey and red). The two sets never overlap — the eraser takes a leg out
  of the flag and the flag takes it out of the erasure — and where two devices disagree an import
  makes the erasure win, since taking ground out of the line is the stronger statement. The eraser
  may take any leg it reaches; the flag may only take one a **softer** rule caught
  (`WorkoutRoute.jumpKind`), because an ordinary leg is drawn as walked already and a leg the strict
  rule owns is the receiver's invention.
* The edits are kept as ranges of leg indices — two numbers a stretch, `12-40,58` — in
  `RouteEditStore`, a SQLite database in **Application Support** (never `Caches`: an edit is the
  user's work and must survive both a purge and the route itself being fetched from Health again),
  read once at launch into memory, so drawing a route costs a dictionary lookup and never a disk
  read. Every screen that draws a route applies them — the detail map, the memoised split behind the
  map tab (`RouteLineCache`, whose key includes them) and the list thumbnails
  (`MapImageRenderer.thumbnail`, in *its* cache key too), and with those the export card. Coverage
  and the explorer deliberately do not: an edit is how a route is *drawn*, not where the user has
  been. The file travels as JSON — the workout's own UUID is the key on both devices, an edit whose
  workout this device does not have is kept and simply never drawn, and the key the erased set
  travelled under before the flag existed is still read. A database written by the build before the
  flag existed (one `erase_edits` table with a `legs` column) is moved into the new shape on the
  first launch after the update.
* With a brush up, MapKit's own pan is parked (`isScrollEnabled`) — it cannot be told to leave a
  single finger alone — and the camera is moved by recognizers of the coordinator's: one finger
  drags the brush, two fingers pan, and MapKit's own pinch is **watched** so the pan can stand aside
  while it scales. Only the map's **centre** is ever written (`centerCoordinate`), never its span,
  and the drag is turned by the camera's own **heading** before it becomes a shift of the centre: the
  fingers move the screen, and a map turned a quarter turn used to walk sideways when it was pushed
  up — a swipe to the right sent the ground *down* the screen instead of right, because the
  translation was still being read as if north were up. Measured through `WM_PAN` with `WM_MAP_HEADING`:
  a 200 pt drag to the right logs `east 0, north +200 pt` on a map turned 90° (screen-right is due
  north there) and `east −200 pt, north 0` on an upright one — the same screen direction in both.
  Alongside that, the pan used to write a whole region, with the span it had captured when the gesture
  began, on every step — and a pinch moves the fingers' centre too, so every frame of a zoom had the
  old span written back over it and a zoom could barely take hold. Measured with `WM_PAN` and
  `WM_FAKE_PINCH_SCALE`: with the pan free the same call moves the map over 31,977 sampled pixel
  pairs, and with a pinch scale of 1.4 standing in for the fingers it changes **0**. Rotation and the
  pinch itself are MapKit's, untouched. An erased leg is not drawn at all — walked or jump — which is
  also why the *Undo* step is per stroke, not per touch event.
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
  The **detail screen hides the navigation bar**, so the system has no actions to put in that
  rail at all — and it is drawn **edge to edge** for that reason: laid out inside the safe area,
  the 84 pt the window reserves down that side was left as a band of empty black with nothing in
  it, and the map stopped short of it as well. Its content ignores the safe area
  (`.ignoresSafeArea()` on the map and the cards, which then run the full width of the window),
  while the back and share buttons are placed on the `GeometryReader` above it — still inside
  the safe area, so they keep clear of the rail and of the camera cut-out. Nothing this screen
  draws lives in that strip, so there is no reason to keep out of it. Measured on the folded
  panel: full width in the folded portrait and in the folded landscape.
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
* The **Walk / Run / Ride filters** are the app's own round glass buttons (`GlassCircleButton`,
  the same 48.5 pt disc every close cross and card action carries) — symbol only, walk at
  the top — on the side *opposite* the toolbar, since the rail sits on the camera cut-out's
  side (so the filters land right when the folded landscape puts the rail left). The lowest
  one ends level with the lowest button of the toolbar column on the other side: down a side
  the tab bar is stacked into that same column, so that is its last tab; with the bar running
  along the bottom the column holds only the two-button pill, so it is the locate button at its
  foot. The height comes
  from the bar's capsule, measured at runtime instead of guessed from the safe area. The
  selected one carries its colour through the button's `tint` — the symbol solid in it and the
  glass washed with the same colour — the same lever every glass button in the app takes its
  colour from, so the settings' colour picker reaches these circles unchanged; walk starts
  selected. The folded landscape puts the bar at very
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
    into one polyline. **Two algorithms** build those legs and `WM_PLAN_ALGO` picks between them
    at launch — the tour is the proof of concept and the default, the zigzag is what shipped.
  * The **zigzag** (`WM_PLAN_ALGO=zigzag`) makes both shapes a **zigzag sized so its
    straight-line length is the distance asked for**. That is what the *Route Shape* setting
    steers: how many legs the zigzag is made of, not how long it is. A **loop** is a zigzag over
    a square centred on the start, the route turning at each row's far end and coming home; a
    **destination** is a zigzag along the direct line, alternating either side of it. At *Wide*
    the loop is two long legs out and back around the start and the destination is one big bow
    off the corridor; at *Tight* the
    loop is a **lawnmower over the square the start sits in** and the destination is a handful of
    side streets either side of the way there. Measured on a 5 km loop from the same spot:
    5.87 km reaching ~1.1 km out at *Wide* against 4.81 km filling a ~1.1 km square at *Tight* —
    the distance holds while the shape changes, which is the whole point of the setting.
  * The **tour** (`WM_PLAN_ALGO=tour`) is the proof of concept. Instead of a zigzag sized on a
    straight line, it puts a **disc of ground** around the user and sizes the disc so the streets
    in it are the distance asked for; the walk then **sweeps the disc row by row**, a lawnmower
    over the ground rather than a zigzag past it. The rows are the *Route Shape* setting: at
    *Tight* it is many short rows over a small disc, at *Wide* a couple of long rows over a big
    one. Rows that are covered ground from end to end are **dropped before anything is routed**,
    so a tight tour spends its legs on the streets the user has not walked; the rows that remain
    are nudged at each end towards the least covered ground nearby, exactly as the zigzag's
    turning points are. The disc is tried at the start and on a few rings around it, and a centre
    is preferred when the ground inside it is unexplored *and* it is near the user — which is the
    answer to the zigzag's habit of ignoring the new streets under the user's feet in favour of a
    bigger, emptier square further out. Both algorithms are docked for **re-walking ground they
    have already walked** (`CoverageIndex.selfOverlapMeters`), so a route that goes out along a
    street and back down it ranks below one that sweeps once. The loop's leg home still retraces
    about the disc's radius — the open point this proof of concept leaves, where a shape whose
    return is itself new ground is the obvious next step.
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
    leg is retried twice with a growing delay, and the zigzag is capped at 18 legs — which is
    also what caps *Routes Suggested* at three when the shape asks for five legs each. The tour
    asks for more: a sweep is a row per leg and then some, so it is capped at 14 legs a route and
    45 a plan, and the same three-at-a-time throttle carries the burst. A leg that fails
    outright drops its candidate: a route with a hole in it is not a route.
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
  * **Every panel of the map screen is glass**, and the three menus are **cards of their own**. The
    explorer's result card and the range bubble keep the material they had; the three menus — the
    explorer's input, the calendar picker and the map-style picker — are drawn on the map screen's
    `menuCard(_:_:)`, which is the same **Liquid Glass** (`glassEffect`) in the shape **the card's own
    position asks for**: one `ConcentricRectangle` (`menuCardShape`), asked for *per corner*. A corner
    resting on a display edge is answered by the display — its radius minus the card's margin — which is
    the only way the folded Duo's cover panel can come out right, because its corners are **asymmetric**
    and *which* way each goes is its own business: measured on that panel now, the card's bottom-left
    corner is a straight edge where the display's corner is nearly square, and its bottom-right sweeps
    ~69 pt where the display's is round. A corner out in the open, where the display's answer is nothing
    at all, is drawn with `Metrics.menuCardRadius` instead — the strongly rounded default every floating
    card of the system's has, measured off Apple Maps' own card on the same 466 pt display, corner
    against corner (**40 pt**: both of the Maps card's top corners are circles of 120.5 px = 40.2 pt,
    where this app's card read 96.4 px = 32.1 pt at the 32 it carried before, and the older reading of
    that same corner — 86 px in, six pixels down from the card's top edge — is a radius of ~41 pt, not
    32) —
    and the change from one to the other is **blended** over `Metrics.menuCardBlend` points of approach,
    which is what the system's own sheets do as they are dragged up to a corner: a slow change of shape
    rather than a jump at the end of the movement (`Edge.Corner.Style` is `Animatable`, so the blend is
    an animation of its own).
    `MenuCardModifier` is what knows where a card sits: it measures the card's own frame in the window's
    space — the cards are bottom-aligned in one column and their heights differ, so nothing else knows a
    card's distance from the top of the display — and adds the swipe's offset **by hand**, because
    `.offset` does not move a layout frame and the corner being dragged away from a display edge has to
    know that it has moved. The card is inset by the same margin from **all four** display edges — see
    `Metrics.menuCardInset`, measured off that sheet's card — so it reaches over the band the tab bar
    and the Duo's rail register live in instead of stopping short of it, and its bottom edge ends above
    the display's bottom edge, which is what makes it read as a card rather than as a sheet that runs
    off it.
  * A menu **rises out of the bottom edge of the display and goes back down through it**, and that is
    a transition on the *card*: `menuLayer` keeps a full-screen container in the tree so the view that
    is inserted and removed is the card itself. Two arrangements that look right do not work, and both
    were on screen for a while: a `move(edge: .bottom)` on a container the size of the display moves
    the card by the *screen's* height rather than its own, and a `move` on a **descendant** of the
    inserted subtree is never run at all — the panels arrived in a fade and left in no time. Every path
    out of a menu goes through the same `withAnimation` (`open`/`close`/`closeMenus`), the spring
    being the one `WM_MENU_DURATION` slows down: the panel's X, a tap on the dim, the explorer's
    *Plan route*, the range picker's own controls. The dim is the outermost view of its own conditional
    subtree, so it fades in **and out** with the same spring.
  * The workout card the range bubble opens is the **one card that is tall** — the whole screen — so it
    is the one whose top margin `menuCardInsets` does not leave it (that insets the other three sides;
    the three menus' own height is what leaves theirs) and its caller adds the fourth
    (`MapTabView.menuLayer`). Two things about it were measured the hard way:
    * The safe area read **inside** that card is still the *window's*, so a card that reaches for it —
      `WorkoutDetailView` does, to fill its container edge to edge when it is a pushed screen — pushes
      its black backdrop out of the frame it was given: measured on the folded cover panel, it ran off
      the top of the display and came out 11.3 pt from the leading edge against 3.0 pt from the trailing
      one, with the margins square rather than round. Drawn as a card it fills exactly what it was given
      and nothing more. Measured after the fix, off a frame of the same screen with the card on it and
      one without: the rows above the card are the map behind at the dim's own ratio of **0.650**, and
      the card starts on the 24th pixel — 8 pt — on every side.
    * The card is **clipped** to its shape, not merely backed by one: the map inside it is a rectangle
      of its own, so it is the map's square corner, not the backdrop's round one, that reaches the
      card's corner (measured: the corner came out square). And it is *one* clip on the one view rather
      than the same shape asked for twice (a shape on the background and the same shape on the clip) —
      those two resolutions do not come out the same, and on that display they left a black wedge of
      backdrop behind the card's round corner (measured: a pixel inside the corner was `(0, 0, 0)`
      before and the map itself `(60, 71, 39)` after). That clip is the **screen's** rather than the
      card's own: the shape is resolved from where the card sits on the display (`menuCardShape`), and
      the detail screen — which is handed nothing about that — would resolve it a second time, its own
      way. It draws a plain black fill and the map screen cuts it to shape.
  * While a menu is up, **the screen's own controls are not behind it** — and, unlike the system's
    chrome, they are drawn **over** the cards rather than under them. The two things that have to *not*
    read through a card over the map are the Walk / Run / Ride and explorer circles and the hand-placed
    pill: both are faded out with the menu's own animation (`opacity`, in the same `withAnimation`), and
    fade back when it leaves, which is more than a sheet's dim would do — a sheet only darkens what is
    behind it. Over the card is what makes that fade *visible*: a card is opaque, and the card the
    workout opens is **full height**, so under it the fade ran the whole time and was never on screen —
    the card's top edge swept the whole column away inside a couple of frames, which read as the card
    sliding over the icons (the user caught exactly that; the shorter menus showed their own fade only
    because the top of the column stayed above their card's edge). Nothing of them reads through the
    card once it has arrived — they are at zero by then — and they stop taking taps with it, which they
    must: a SwiftUI view at opacity 0 is **still hit-testable**, and the range picker's *Done* sits
    under the foot of that column. On a screen whose actions are the system's own toolbar items
    (the Duo's rail) the rail, its bottom bar and the **tab bar** fade the same way — and *not* from
    SwiftUI: a toolbar's visibility cannot be animated there (`.toolbar(.hidden)` inside the menu's own
    `withAnimation` swaps the bar in one frame, measured), so `SystemChromeFade` leaves the bars
    declared and moves their own `alpha` over the menu's spring instead. The
    **range bubble** and the explorer's **result card** stay where they are and are merely dimmed —
    the card is readable through it on purpose, and the workout card the bubble itself opens is drawn
    *above* it for the same reason: the bubble stays readable over the card it put up (the user's own
    screenshot of the sheet it used to be shows the bubble above the card).
  * A menu can also be **swiped down out of the way**, the way a sheet is (`MenuCardModifier`):
    the card follows the finger, and the release decides where it settles — past a third of its own
    height, or flicked fast enough that it *would* have got there, it leaves; otherwise it springs
    back. It is a plain `.gesture`, not a high-priority one, so the calendar's wheels still spin and
    the explorer's own scroll view still scrolls — a child's gesture wins inside its own bounds, and
    the card's drag takes the header and the room around the controls, which is where a sheet's own
    grabber drag lives too. The card is left exactly where the finger dropped it as it goes: the
    dismissal is the card's own `move(edge: .bottom)` transition, which carries it on down from there
    rather than snapping it back to rest first.
  * The menus are still **drawn in the map screen itself** (`MapTabView.menuLayer`) rather than
    presented as sheets, and that is not a style choice: a half-height sheet is handed a glass panel
    of the system's own — Apple's note on adopting Liquid Glass: "half sheets are inset from the edge
    of the display" — and no value of `presentationBackground` removes it (measured on iOS 27: the
    card keeps its blurred panel whatever the modifier is told, and only an opaque colour painted over
    it hides it). A menu also has to be handed **the room the keyboard leaves it**, so that the
    explorer's header and its close cross cannot be pushed off the top of a short display; a sheet's
    detent does not know about the keyboard, and the panel is the one screen here with a text field in
    it. The map screen's own card gives both for free.
  * The explorer panel's own fields (the search box, the results, the chosen destination) are
    `.thinMaterial` over it. The flat `Palette.sheetCard` / `Palette.pickerGlass` fills went with
    it. The export card is the one exception: it is a full-screen viewer for the image it
    produces rather than a panel over the map, so it still sits on black.
  * A card's close cross is one of the screen's own **glass buttons** (`GlassCircleButton`) — a 48.5 pt
    disc, so a hit region wider than the 44 pt `Metrics.toolbarButtonSize` the map screen's own controls
    carry — and it is placed against the **card's** own corner rather than in the header's row, with the
    **same inset on the top and on the trailing side** (`Metrics.menuCardCrossInset`). Equal is what
    Apple Maps' own cards do — measured on the Duo's cover panel, its *Map Modes* card carries a 48.7 pt
    circle 16 pt from the card's top edge and 14 pt from its side — and it is what this app was missing:
    its trailing inset was **9 pt**, put there to line the cross's centre up with the column the map
    screen's own rail keeps, an alignment a 44 pt target made 10 pt and the 48.5 pt one could no longer
    hold. The header still grew for the circle: the card's radius out in the open is 40 pt, so its arc is
    centred 40 pt in from both edges, and this inset puts the circle's centre at 16 + 24.25 = 40.25 pt —
    on that centre — leaving its edge **15.4 pt clear** of the arc, so it is wholly inside the card's
    shape instead of poking out of its corner. The Map Modes panel grew by the same amount, so its row of
    tiles kept the room it had under the labels instead of sitting on the card's bottom edge.
  * **Every** close cross in the app is that same button, and there is no other kind left: the map
    screen's three menus and the workout card (above), the route editor's own chrome, the settings'
    *Edited Workouts* list and the export preview all carry `MenuCloseButton` — one size, one look,
    wherever a cross appears. The plain grey circle the app shipped with (`CloseCircleButton` and
    `Palette.closeButton`) went with the last two users of it. The explorer's result card carries the
    same family: its cross is that button, and *Go* is a **glass capsule tinted with the accent** — the
    editor's own *Done*, which is what the user asked it to match — rather than the flat fill the app
    drew before; *Stop*, which replaces the pair once the route is the one being walked, is that same
    button in the pin's red. Their labels sit in the round buttons' own box too (`Metrics.glassButtonLabel`
    as the label's height): the system pads a capsule 15 pt a side exactly as it pads a circle, so without
    it a text label's own line box made the capsule 50.3 pt against the cross's 48.5 — the box is what
    keeps a row of the app's glass chrome one height, whatever shape of button it is.
  * The **export preview** is the one screen whose cross is not a card's, because the screen is not a
    card: it is a full-screen viewer on black for the image *Save* writes, so its cross stands in the
    **screen's** own corner — `Metrics.screenInset` from the trailing edge and from the top, inside
    whatever the window reserves there (the Duo's cover panel keeps 84 pt for the system's rail, so the
    disc's edge lands 102 pt from the display's right edge, measured) — and the **status bar is hidden**
    for it, as it is on the editor. Two things were wrong with it. Its cross hung **35 pt inside the
    reader and 3 pt below the display's top edge** — which on the folded panel is the band the status
    elements are drawn *over*, because that panel reports **no** top inset at all (measured: 0 pt, and
    84 pt trailing) — and the card itself was laid out at its natural height, so a window shorter than the
    card showed only the top of its map: on the folded panel held sideways the stats grid, the footer and
    the *Save* button were all off the screen. The preview now **draws the rendered card** — the same
    image *Save* writes, so it cannot promise a different one — fitted: never bigger than that image, so
    its text stays sharp, and scaled down where the window is short, so the whole card is visible in every
    pose (measured in the landscape reader: the card at 182 × 232 pt inside 594 × 432, all of it on
    screen). *Save* is inset by `Metrics.screenInset` like the app's other primary buttons
    (`RoutePlannerPanel`, `RangePickerPanel`), rather than running edge to edge.
  * Those buttons are the **system's** own glass button — `.buttonStyle(.glass)` with
    `.buttonBorderShape(.circle)`, which is what a toolbar item of the rail is drawn with — rather than
    a `Button` painted with `.glassEffect`: the first version's glass never reacted to a touch at all,
    while a glass button sinks under the finger the way the rail's do. Their colour comes through
    `tint`, not `foregroundStyle`, which is the other half of the same measurement.
  * The **size** is the system's as well: `.controlSize(.large)` on the glass button, with the label in a
    **fixed box** (`Metrics.glassButtonLabel`) — and the box is the point. The glass pads whatever label
    it is handed, so a bare SF Symbol sizes its *own* disc, and every symbol is a different box: measured
    on the Pro Max at `.large`, the workout card's own `chevron.left` came out 42.7 × 47.3 pt where
    `square.and.arrow.up` was 49 × 52.7 and `ellipsis` 48.3 × 36 (the Duo's cover panel had read the
    same three as ~44 and ~52) — three actions, three sizes, and never a square one. At `.regular` a bare
    symbol is smaller again (~32 pt with a 13 pt cross), and the *first* version put an explicit 44 pt
    frame **inside** the glass, which the glass then padded *around*: ~62 pt across with a cross a third
    larger again, which is what the user saw as "riesig". The system's own padding is what the box is
    added to — **15 pt a side at `.large`** (7 at `.regular`), measured rather than documented — so the
    box alone decides the size: the 18.5 pt one is the **48.5 pt** (145.5 px at 3×) every round button in
    the app comes out at: a menu's close cross, the card's actions, the editor's chrome. That is a shade
    under Apple Maps' own *Map Modes* card (~50 pt on the same display) and lands on the ~145–146 px the
    polished third-party crosses measure, and it is still 4.5 pt over the 44 pt hit region the Human
    Interface Guidelines ask for. Apple publishes no points for the glass sizes at all — `ControlSize`
    names `mini`, `small`, `regular`, `large` and `extraLarge` and stops there — so the box is the only
    continuous lever the app has, and `Metrics.menuCardCrossInset` places a button by its **centre**, so
    the size it ends up at is a layout number as much as a look.
  * The **glyph** is the system's too, with one exception: the close cross carries a size of its own
    (`Metrics.closeGlyphSize`). A bare `xmark` at the body font draws **13 pt** of ink, where Apple Maps'
    own card draws ~**16.8** — measured at 3× on the Duo's cover panel: 50 × 51 px against this app's
    39 × 39 — the smallest box of any symbol the app draws, and the one that read as too small inside the
    same 48.5 pt disc. The glass pads the *label's* box and never the glyph, so 22 pt of font puts the
    ink back at ~16.7 pt without moving the disc: measured 51 × 50 px after the change, and the disc is
    still 145.5 px across.
  * They are **not** declared as toolbar items, and that was measured rather than assumed. A
    `NavigationStack` bar **insets the screen** as soon as it has items in it: the route editor, wrapped
    in one for a `Button(role: .close)` as [the article the user pointed at](https://nilcoalescing.com/blog/AddACloseButtonToSwiftUIModalsOnIOS26)
    describes, lost its full-bleed map — the map started ~103 pt down, at the bar's own bottom edge —
    and neither `.ignoresSafeArea(.container)` on its content nor `.toolbarBackgroundVisibility(.hidden)`
    moved it back (both measured on the Pro Max in this SDK). A bar with **no** items in it costs
    nothing, which is why the map screen's own map is full bleed. And on the folded Duo an item in that
    bar would be invisible anyway: the bar the rail lives in is the one the screen **fades** while a card
    is up (`SystemChromeFade`; on that display the rail and the tab capsule are one view). So a
    full-bleed map with drawn-on glass buttons, or the system's bar with an inset screen, is the choice,
    and a full-bleed map is what the app takes.
  * The detail screen's own actions — **Share**, **Edit** and **Back**, one round glass button each —
    are drawn **in** the screen, and they **hang on the bottom**: `Metrics.pillGap` above the
    info-card block, the same gap the buttons keep between themselves (~35 px at 3×, the user's own
    measurement). The block's height is *measured* (`blockHeight`), so that gap is the same in every
    pose and on every display — the folded panel held sideways used to have the rail reaching *into*
    the cards. Hanging from the bottom is also what keeps them out of the **status band's** way: that
    band's height is a number the folded cover panel does not report at all (measured: safe-area
    **top 0**, trailing 84) even though it draws its whole cluster *inside* the display, and every
    attempt to guess it — 59, then 110, then 200 pt on that panel — put the buttons among the icons
    (the user's screenshots of both screens). Their **column** is the status cluster's own, which the
    two displays place differently: on the folded panel the clock and the radio arc are centred 48 pt
    from the trailing edge, so `Metrics.statusColumnInsetFolded` (23.75) puts the 48.5 pt disc's
    centre exactly there, while a notched iPhone keeps the app's `screenInset` (18, a centre 42.25 pt
    in). **Both** presentations put that one rail on that one column, and the difference between them
    is the box they are laid out in — read off a probe rather than reasoned about, after two wrong
    guesses: `pushed` fills the display (its 48.5 pt disc lands at 393.75..442.25, centre **418.00** on
    the folded panel), while a card's box ends `Metrics.menuCardInset` short of the display, so the same
    column put the card's disc 8 pt inboard and the card takes that margin back out again
    (`railTrailing`). Its reader reports **no** window safe area on that panel either, so nothing else
    is allowed for; the card measured 417.67 pt after the correction, against the cluster's own 418.00.
  * A card's height is capped by the band the **status elements** keep at the top
    (`MapTabView.menuRoom`): the display, less the card's own margin, less
    `max(windowInsets.top, menuCardInset)` — the window's own safe area, which the map reports and a
    **Live Activity** grows. Before that the explorer's *To a destination* panel was built 560 pt
    tall, and with the keyboard up the card was pushed up until its own close cross sat under the
    clock and could not be tapped (the user's screenshot of it); it is built 440 pt now — its
    destination part is a `ScrollView`, so it does not have to be tall enough for the search results
    and the pin at once — and the height a *mode* change makes is animated (`animatedMode`), so the
    card grows and shrinks instead of jumping. The editor's own tools panel is a card of the same
    kind (`WorkoutEditView`): `menuCard` against the **display's** own bottom edge — that screen's
    reader is inside the safe area, so the display's geometry is read from it and added — and, swiped
    away, it is brought back by a glass chevron at the display's bottom trailing corner that fades in
    and out on the app's own card spring (`MenuMotion`, which the map screen's menus and their chrome
    fade on as well).
  * Measured, with the spring frozen (`WM_MENU_DURATION=40`, a frame every ~1.9 s on the iPhone 18
    Pro Max): the card comes up from **below** the display's bottom edge — the range picker's *Done*
    button's own top edge 938.3 pt → 885.0 pt — while the dim's strength at a corner no card reaches
    goes 1.000 → 0.653; on the way out that corner goes 0.653 → 0.686 → 0.720 → 0.765 → 0.803 → 0.845
    → 0.877 → 0.905 → 0.928 → 0.951 → 0.965 → 0.975 → 1.000 while the card's top edge walks 757 →
    933 pt before it leaves the screen. The build **before** this change (a scratch tree at HEAD with
    only the close hook added) kept that same button at 798.0 pt in every frame it appeared in, and
    took the card and the dim away between two consecutive frames (0.662 → 1.000): the rise that was
    only a fade and the dismissal that was instant.
  * The screen's own controls go with it, measured on the same device: the accent-yellow pixels of the
    Walk / explorer filter circles number 1413 in the settled frame, **0** with a menu up (they are
    faded out with the card's animation) and 1413 again once it has left. On a screen whose actions
    are the system's (`usesVerticalControls`, the Duo) the rail, its bottom bar and the **tab bar**
    fade with it, measured with the spring slowed (`WM_MENU_DURATION=6`, on the folded cover panel):
    the rail's own glyphs' mean brightness walks 84.8 → 84.8 → 72.9 → 38.1 → 32.3 over the leave
    rather than arriving at 32.3 in one frame, and comes back the same way. Left and right fade on
    **one** spring, and that took writing it out: handed `UISpringTimingParameters(dampingRatio:)` the
    rail ran a different spring than the circles that fade from SwiftUI — UIKit's own frequency, not the
    menu's, since the duration passed to the animator does not drive it. Measured on that same panel
    with the spring stretched (`WM_MENU_DURATION=6`, a sample every 0.45 s): the rail at 0.37 alpha
    where the circles were at 0.52, and 0.05 where they were 0.13 — mean |Δalpha| 0.068 over the leave.
    Mass 1 with ω₀ = 2π/response and ζ = the menu's damping *is* that spring, and puts the two at a mean
    |Δalpha| of 0.009 over the same leave, 0.037 at worst. Handing both sides the spring's own cubic
    approximation instead — one curve, verbatim for each — measured worse still (0.073), so the spring
    is what stays. What is left is the one frame they start on: the circles move in the frame the state
    changes and the rail's own `alpha` one frame later, which is what a UIKit animator started from a
    SwiftUI update costs. Measured on the Pro Max
    as well: the hand-placed column goes 94.5 → 74.8 → 45.7 as the menu opens. It used to be
    **hidden** for as long as a menu was up instead — measured on the folded panel: left up, the tab
    bar's column lies over the card's trailing edge and its own capsule over the card's *Done* — and
    that hide had to be given back only once the card had left, on the animation's own **completion**
    (`withAnimation(_:completionCriteria:)`) rather than on a guessed delay: hiding a bar lays the
    screen out again (the tab bar reserves a region of the map view) and a layout pass in the middle of
    a transition cut the card's slide short — measured: the card and the dim were gone between two
    frames two seconds apart with the bar put back in the same turn as the close, while the same
    spring took about ten seconds to bring that card *up*. A completion is right at every spring
    response; a constant is not (measured with the spring slowed: the chrome stayed away while the
    card was still walking down — the dim mid-fade at 0.653 with the chrome still hidden, and back at
    1.000 with the chrome back). A fade changes no layout at all, so the chrome leaves and returns
    *with* the card now, and the completion went with the hide.
  * The menus and the detail screen's card are the **same card**, measured on the same displays: on
    the Duo's folded panel the menu card's own edges are 7.3 pt (leading) and 7.7 pt (trailing) from
    the display, and the detail card's black backdrop 8.0 / 8.0 / 8.0 pt (leading / trailing /
    bottom); on the Pro Max the detail's backdrop is 8.0 / 8.0 / 8.0 pt as well. The 8 pt is the
    margin the system's own sheet card keeps on the Duo (`Metrics.menuCardInset`); on the Pro Max the
    system's card is the **full width** of the display (measured 0 pt at the sides) and flush at the
    bottom, so the detail screen insets its own backdrop by that margin there instead — which is what
    makes the two cards agree on both devices rather than only where the system happens to inset.
    The folded Duo's corners are **asymmetric**: the sheet card's top-left corner reaches its straight
    edge about 24 px below the card's own top edge (an 8 pt radius — the display's own radius minus the
    margin) against about 56 px on the top right (19 pt). That asymmetry is what the per-corner shape
    above is for, and it is measurable on the app's own cards now — off a settled workout card on that
    panel, its bottom-left corner is the **straight edge itself** (the pixel at the card's own left
    edge, 24 px, on every row down from the card's bottom, against 121 px at the first row when the same
    card was drawn with one radius for every corner), while its bottom-right corner sweeps: the card's
    black reaches no further right than 1166 px at its bottom row, 1255 at 6 px up, 1326 at 42, and only
    reaches the straight edge 1374 about 170 px up — a ~69 pt radius, the display's own, since the card
    is 8 pt inside it. A corner in the open, which is what a short menu's top corners are, comes out at
    the default instead — 32 pt, measured against Apple Maps' own card on the same display (see above) —
    and the app asks for the default only where the display's own answer is *nothing*, so the two never
    fight.
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
  timestamp (`WorkoutRoute.drawing`). The app keeps the three-part rule it always had: a leg
  has to cover more than 25 m **and** beat 162 km/h, or cover 300 m when its timestamp cannot be
  used. That rule is fixed and **never drawn**: a leg it catches is left out of the map, gap and
  all. On top sit the **two independent rules** *Settings ▸ GPS Jumps* exposes: a leg longer
  than the distance threshold is a distance leg, and a leg faster than the speed threshold is a
  speed leg — provided it also covers more than 10 m (`JumpRules.speedMinimumDistance`). A
  receiver's timestamps are rounded, and two fixes a metre apart a hundredth of a second apart
  imply 100 m/s: that is a bad clock, not a jump, and flagging it put a lone dot on a fix the
  user was standing on. Each rule is drawn *dotted*, *hidden* or *solid* on its own — a leg that
  trips both is drawn as a fast leg. Dotted and solid use the rule's own **tone**, never the
  route's colour, and that tone is the user's to set (`JumpColorStore`, through the two colour
  rows under *Settings ▸ GPS Jumps* — the same system colour picker the mode colours use, with
  the hex beside it): grey for the distance rule and the system red for a fast leg until another
  one is picked, and a change lands on the map, the card thumbnails and the export card at once.
  The tone belongs to the **rule**, so it is what a leg reads as whether the rule draws it
  dotted or solid. A dotted leg is a row of **dots**, each a zero-length dash
  stroked with a round cap, and both the dot and its spacing are measured against the width the
  route itself is drawn at (`RouteJump`). Health stores a jump as an ordinary fix — the straight
  line is what a polyline draws between any two fixes, and the impossibility is in the time
  between them — so nothing in the route itself marks it; the cached route therefore keeps one
  interval per fix beside the coordinates (`WMR2`, the seconds the leg took, so a threshold can
  move without a fetch; a `WMR1` file, which held a jump flag instead, is fetched from Health
  again). The dots are stroked by the app's own renderer (`JumpDotsRenderer`), because MapKit's
  dashed stroke grows with the map's zoom: measured with the camera pinned over the same routes,
  the dots came out ~4 px at a 1.5 km span and ~10 px at a 40 km one while the route line stayed
  put, so they ended up wider than the line they interrupt. The renderer keeps the dot and its
  gap fixed against the zoom, and the coordinator asks it to redraw when the zoom has actually
  moved the dots by more than a fraction of one. MapKit hands a renderer **one tile at a time**,
  so the renderer keeps each leg with the rectangle it covers and strokes only the legs the tile
  can reach, all of them in one path: stroking the whole overlay per tile is what made the map
  crawl — measured at 8–11 ms a tile with a few thousand legs, every leg on the map stroked
  again for each tile a pan brought in, whether or not it lay anywhere near it — and the cost of
  a tile is now its own dots. The walked
  stretches are split around every leg either rule catches, which costs a handful of polylines
  per workout and still one overlay — one draw call — per colour and dash pattern; the split is
  cut once per route and kept until the rules or the colour move (`RouteLineCache`), because the
  map screen asks for its lines on every redraw of the screen. Each jump
  line carries the workout's id with a suffix, which a tap cuts off again
  (`Coordinator.baseRouteID`), so picking a route still picks that workout. Snapshots (card
  thumbnails and the export card) draw the same legs into their pixels, and the thumbnail cache
  key carries the rules so a cached image of the other look does not come back.
* An overlay set replaced while the map is **off screen** is on the map but not on the screen. MapKit
  draws an overlay when it *renders*, and it stops rendering while the map is not on screen — which is
  the case for the workout card's map while the route editor, presented as a full screen cover, is
  over it — so nothing draws the new set until the visible region next changes. That is what made an
  edit saved with *Done* show up only once the card's map had been moved under the finger: measured on
  the iPhone 18 Pro Max, the card's map kept the route as it was after the editor closed (the same
  1123 differing pixels a run *without* the edit shows — the map's own antialiasing — against 5744 in
  the erased arc once it drew), and a 2 pt pan through `panMap(by:)`, the pan recognizer's own call,
  drew it at once. The coordinator therefore **hands MapKit fresh overlay objects** for the set that
  is already on the map (`reapplyOverlaysIfNeeded`) rather than trusting the swap it made, once from
  the map's own layout pass — which is when it is laid out on screen again — and once after the
  cover's dismissal (`repaintRetryDelay`), because the detail screen the Workouts list pushes is not
  laid out again by an edit; `mapViewDidFinishRenderingMap(fullyRendered:)` is what says the set has
  been drawn, and stops it being repeated. A route set that holds **nothing** — every leg erased, or a
  filter with no route in it — has nothing of its own to hand over, so the map keeps one overlay for
  the case that spans the **visible rectangle** with a hairline (`repaintCarrier`, alpha 0.004: below
  anything visible over any map); measured, the erased set stayed drawn until that was added, while a
  carrier spanning the *world* left it — and the three attempts that do not work are worth recording:
  `setNeedsDisplay`, `setVisibleMapRect`/`camera` with the value they already had, and removing and
  re-adding the *same* overlay objects are all no-ops, because each leaves MapKit thinking the tiles
  it drew are still right.
* The Settings screen omits the "WorkoutMap Plus" banner.
