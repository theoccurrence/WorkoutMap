import SwiftUI

/// One round action on the app's **Liquid Glass**.
///
/// The button is the system's own — `.buttonStyle(.glass)` with `.buttonBorderShape(.circle)`, which is
/// exactly what a toolbar item of the map screen's rail is drawn with — and it is given **no size of
/// its own**: the label is the bare symbol, so the glass is the size the system sizes it to (measured
/// below) and the glyph is the system's own weight and scale, the way the cross on Apple Maps' own
/// *Map Modes* card is. An explicit `.frame` inside the glass is what made the first version's button
/// ~62 pt across where that one is ~50, with a cross a third larger again: the glass pads whatever it
/// is handed, so imposing `Metrics.toolbarButtonSize` on the *content* adds its padding *on top*.
/// The colour comes through `tint` rather than `foregroundStyle`, which is the other half of the same
/// measurement — a glass button carries its label's colour that way, and a painted symbol never reacted
/// to a touch at all.
struct GlassCircleButton: View {
    var symbol: String
    var label: String
    /// The glyph. White over the glass on the app's dark screens.
    var glyph: Color = .white
    /// The glyph's own point size, where the system's (the body font's) is not the right one. Only
    /// the close cross needs it — see `Metrics.closeGlyphSize`.
    var glyphSize: CGFloat? = nil
    /// The system's control size. `.large` is the app's default; the plan-route bar asks for
    /// `.regular` (the "medium" the user wanted to see).
    var size: ControlSize = .large
    /// The wash in the **glass** itself, where the button has a state to show — the map screen's
    /// filter circles are the users: `tint` alone colours the glyph, and a glass button's own glass
    /// stays neutral, so the wash has to be asked for through the button's `Glass` value.
    var glassTint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                // A **fixed** box for the label, which is what makes every circle the same size: the
                // glass pads whatever it is handed, so a bare symbol sizes its own disc — measured at
                // `.large`, `chevron.left` came out 42.7 × 47.3 pt where `square.and.arrow.up` was
                // 49 × 52.7 and `ellipsis` 48.3 × 36 (the Duo's cover panel read the same three as
                // ~44 and ~52 before the box was introduced). This box plus the glass's own 15 pt a
                // side is the 48.5 pt every disc in the app comes out at.
                //
                // The glyph's own size is the system's — `font` is left to the environment — except
                // where one is handed in (`glyphSize`): the box is what the glass measures, never the
                // glyph, so the close cross can take its own size without moving its disc.
                .font(glyphSize.map { .system(size: $0) })
                .frame(width: Metrics.glassButtonLabel, height: Metrics.glassButtonLabel)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(size)
        // The wash, where the button has a state to show. A plain colour *behind* the glass, not a
        // tinted `Glass`: `GlassButtonStyle(Glass)` is iOS 26.1 and this app ships to 26.0, and a
        // glass that sampled another glass would be the one thing the material is documented not to do.
        .background {
            Circle().fill(glassTint?.opacity(0.30) ?? .clear)
        }
        .tint(glyph)
        .accessibilityLabel(label)
        // A glass circle inside a menu card is one of the card's own drag handles (`menuCardDragHandle`):
        // the close cross of every menu and the workout card's own rail. Where there is no card the
        // environment is empty and this does nothing.
        .menuCardDragHandle()
    }
}

/// The close cross a menu card of the app carries — the map screen's three menus and the route
/// editor's own chrome.
struct MenuCloseButton: View {
    var glyph: Color = .white
    var size: ControlSize = .large
    var action: () -> Void

    var body: some View {
        GlassCircleButton(symbol: "xmark", label: "Close", glyph: glyph,
                          glyphSize: size == .large ? Metrics.closeGlyphSize : Metrics.closeGlyphSizeMedium,
                          size: size, action: action)
    }
}

/// One of the app's smaller **Liquid Glass** capsules — the explorer's route alternates: the
/// distance of one planned route, the selected one carrying the app's own wash the way the map
/// screen's Walk / Run / Ride circles do.
///
/// The *Go* button's own construction (`PlannedRouteBar`), one control size down: the system's
/// `.glass` capsule with the glyph carried by `tint` and the wash behind the glass, and the label in
/// the same **fixed box** every round button's label uses (`Metrics.glassButtonLabel`) so a capsule
/// and a circle stand the same height. The wash is a plain colour *behind* the glass rather than a
/// tinted `Glass`, which is iOS 26.1 and this app ships to 26.0.
struct GlassPillButton: View {
    var title: String
    var label: String
    /// The glyph. White over the glass on the app's dark screens, and the accent where the pill is
    /// the selected one.
    var glyph: Color = .white
    /// The system's control size. `.small` is the app's default here — one below the *Go* pair's
    /// `.regular`, the category smaller the user asked for.
    var size: ControlSize = .small
    /// The wash in the **glass** itself, where the pill has a state to show — the selected one, in
    /// the app's accent, so it reads as *in focus* the way a selected filter circle does.
    var glassTint: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(height: Metrics.glassButtonLabel)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(size)
        .background {
            Capsule().fill(glassTint?.opacity(0.30) ?? .clear)
        }
        .tint(glyph)
        .accessibilityLabel(label)
    }
}

/// The drag a menu card of the map screen is dismissed by — the state `MenuCardModifier` drives, and
/// the one thing a card that must keep its own gestures (the workout card, which is navigated) hands
/// to the only part of itself that may still drag it: its rail of glass buttons.
///
/// It is carried in the environment (`.menuCardDrag`) rather than kept in the modifier alone so that
/// the card's own gesture **and** every control inside it (`menuCardDragHandle`) pull the *same*
/// offset: the card follows the finger whichever of the two it is on, and the threshold and the
/// rubber band are written once. It is empty wherever there is no card — the pushed detail screen,
/// the map screen's own filters — where a drag handle is then a no-op.
final class MenuCardDragState: ObservableObject {
    /// How far the card has been pulled down, added to the card's own `.offset`.
    @Published var offset: CGFloat = 0
    /// The card's own height, measured by the modifier, so the threshold and the rubber band are the
    /// card's rather than a fixed guess.
    var height: CGFloat = 320
    /// What a drag far enough calls — the modifier's `onDismiss`.
    var dismiss: () -> Void = {}

    /// The card follows the finger: one to one *down*, a rubber band *up* and past its own travel.
    func update(_ dy: CGFloat) { offset = pull(dy) }

    /// The release decides where it settles: past a third of the card, or flicked fast enough that it
    /// *would* have got there, it leaves; otherwise it springs back.
    func end(_ dy: CGFloat, predicted: CGFloat) {
        let settled = max(dy, predicted)
        if settled > max(120, height / 3) {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { offset = 0 }
        }
    }

    /// How far the card is pulled for a finger movement: one to one *down*, which is the direction it
    /// can go at all, and a rubber band the other way — a pull *up* has nowhere to go, so the edge
    /// gives there instead of the card following the finger off its place. Past its own travel it is
    /// a rubber band down as well, so the bottom edge gives the same way.
    private func pull(_ dy: CGFloat) -> CGFloat {
        let down = max(0, dy)
        let up = max(0, -dy)
        let travel = height + Metrics.menuCardInset
        let past = max(0, down - travel)
        return min(down, travel) + rubberBand(past, limit: height * 0.25)
                       - rubberBand(up, limit: height * 0.12)
    }

    /// `UIScrollView`'s own rubber band, the one the explorer's result card uses (`cardOffset`): the
    /// displacement approaches `limit` as the pull grows, and a small pull moves it about half as far
    /// as the finger.
    private func rubberBand(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
        guard distance > 0, limit > 0 else { return 0 }
        let constant: CGFloat = 0.55
        return (distance * limit * constant) / (limit + constant * distance)
    }
}

private struct MenuCardDragKey: EnvironmentKey {
    static let defaultValue: MenuCardDragState? = nil
}

extension EnvironmentValues {
    /// The drag a card of the map screen is dismissed by, where the card handed one down
    /// (`MenuCardModifier`). `nil` anywhere there is no card.
    var menuCardDrag: MenuCardDragState? {
        get { self[MenuCardDragKey.self] }
        set { self[MenuCardDragKey.self] = newValue }
    }
}

/// The drag a **control inside** a menu card carries, where the card handed one down
/// (`MenuCardModifier`).
///
/// A card is dragged from **anywhere** on it — a button included — so a control that would otherwise
/// swallow the drag (the close cross of every menu, the map-style tiles, the explorer's own buttons,
/// the workout card's rail) carries this instead of relying on the card's own gesture, which a
/// child's own tap wins over. It is a **high-priority** drag, so it beats that tap: a tap still fires
/// (the drag needs 8 pt of travel first), a drag moves the card. Only *controls* get this — a wheel,
/// a slider and a scroll view keep their own gesture and are dragged as the control they are, which
/// is the one place a card is deliberately not draggable. Where there is no card the environment is
/// empty and this does nothing at all.
///
/// Measured in the **window's** space, like the card's own gesture (`MenuCardModifier.dismissDrag`):
/// a handle sits inside the subtree the drag offsets, so a *local* measurement would be short by the
/// offset already applied, and the two writers would disagree frame by frame — the flicker the user
/// saw when dragging from a button.
private struct MenuCardDragHandle: ViewModifier {
    @Environment(\.menuCardDrag) private var drag

    func body(content: Content) -> some View {
        content.highPriorityGesture(gesture, including: drag == nil ? .none : .all)
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { drag?.update($0.translation.height) }
            .onEnded { drag?.end($0.translation.height, predicted: $0.predictedEndTranslation.height) }
    }
}

extension View {
    /// Makes this control a drag handle for the menu card it sits in (`MenuCardDragHandle`). A no-op
    /// where there is no card.
    func menuCardDragHandle() -> some View { modifier(MenuCardDragHandle()) }
}

/// The motion a card of the app is put away on, and a control that belongs to it fades on.
///
/// One spring for the whole app rather than one per screen: the map screen's own menus open and
/// leave on it, the chrome around them fades on it, and the route editor's tools panel — dismissed
/// by a swipe, brought back by a chevron that fades in — is put away on the same one, so a card
/// anywhere in the app leaves at the same rate and a control that comes or goes with it is never
/// seen moving on a spring of its own.
///
/// The numbers are read by `MapTabView.menuSpringResponse` as well, which keeps the debug hook that
/// stretches the spring (`WM_MENU_DURATION`), and are written out by hand there because
/// `UISpringTimingParameters` has to be handed numbers rather than a SwiftUI `Animation`.
enum MenuMotion {
    static let response: Double = 0.34
    static let damping: Double = 0.86

    static var animation: Animation { .spring(response: response, dampingFraction: damping) }
}

extension View {
    /// One of the map screen's own cards: the glass, in the shape its **position** asks for
    /// (`menuCardShape`), together with the swipe that throws it away. See `MenuCardModifier` for why
    /// the position has to be measured, and why the one card that draws its own background asks for
    /// `clipped` instead of the glass.
    ///
    /// The card is dragged from **anywhere on it that is not a control of its own**: the card's own
    /// gesture is a plain one, so a wheel still spins, a slider still slides, a scroll view still
    /// scrolls and the workout card's **map** still pans and pinches — each of them a child gesture
    /// that wins inside its own bounds. What a plain gesture therefore *misses* is a **button**,
    /// whose tap wins over it; those carry a handle of their own (`menuCardDragHandle`), so a card is
    /// dragged from a button too while every other control is left as it is. The workout card the
    /// range bubble opens is no different: its map keeps its own gestures (the user navigates there),
    /// and the info cards under the map drag the card exactly as they always did.
    func menuCard(display: CGSize, clipped: Bool = false, onDismiss: @escaping () -> Void) -> some View {
        modifier(MenuCardModifier(display: display, clipped: clipped, onDismiss: onDismiss))
    }

    /// A menu card can be **swiped down out of the way**, the way a sheet is — the drag, and where it
    /// settles, are `MenuCardModifier`'s, which is also what knows where the card sits on the display.

    /// The margin a menu card keeps from the display's own edges — the same on all four sides, and
    /// measured from the display rather than from the safe area, so the card reaches over the band
    /// the tab bar and the Duo's rail register live in instead of stopping short of it. The bottom
    /// one is what makes it a card rather than a sheet that runs off the edge.
    ///
    /// It is the margin the system's own sheet card keeps (`Metrics.menuCardInset`, measured), so a
    /// menu and that card sit in the same place on the same display.
    func menuCardInsets() -> some View {
        padding(.leading, Metrics.menuCardInset)
            .padding(.trailing, Metrics.menuCardInset)
            .padding(.bottom, Metrics.menuCardInset)
    }
}

/// The shape a menu card of the map screen keeps where it sits `insets` from the display's edges: one
/// `ConcentricRectangle`, its four corners asked for one at a time.
///
/// `ConcentricRectangle` asks the container for its corner shape instead of being told a number, and —
/// since iOS 26 — **per corner**, which is the whole of this. The card sits in the map screen
/// `Metrics.menuCardInset` from the display on every side but the top, and *where* it sits on the
/// display is what each corner resolves to: one resting on a display edge is answered by the display —
/// round on a round side, nearly square where the folded Duo's cover panel is, which is what the
/// display's own corner is there — while one out in the open, where the display's answer is nothing at
/// all, keeps `Metrics.menuCardRadius` instead, the rounded look every floating card has.
///
/// A corner's `minimum` is the default radius **scaled by how far out in the open that corner is**:
/// resting on the display's own corner (`excess` zero) the minimum is nothing, so the display's own
/// answer is what the corner is drawn with — which is the whole point, and on the folded Duo's cover
/// panel means a nearly square corner on one side and a sweeping one on the other, because that is what
/// the display has; out in the open the minimum is the whole default; and in between the two, over
/// `Metrics.menuCardBlend` points of approach, it is the blend — the slow change of shape the system's
/// own sheets show as they are dragged towards a corner. `Edge.Corner.Style` is `Animatable`, so that
/// blend is an animation of its own rather than a jump.
///
/// `excess` is measured past `Metrics.menuCardInset`, the gap a card keeps at rest: a corner that is
/// *at* the display's corner is at rest on both of its edges, and anything further out than that — the
/// top corners of a short menu, or any corner of a card dragged away from the edge — is out in the open.
func menuCardShape(insets: EdgeInsets) -> ConcentricRectangle {
    func corner(_ across: CGFloat, _ down: CGFloat) -> Edge.Corner.Style {
        let excess = max(0, max(across, down) - Metrics.menuCardInset)
        let openness = min(1, excess / Metrics.menuCardBlend)
        let minimum = max(Metrics.menuCardFloor, Metrics.menuCardRadius * openness)
        return .concentric(minimum: .fixed(minimum))
    }
    return ConcentricRectangle(topLeadingCorner: corner(insets.leading, insets.top),
                               topTrailingCorner: corner(insets.trailing, insets.top),
                               bottomLeadingCorner: corner(insets.leading, insets.bottom),
                               bottomTrailingCorner: corner(insets.trailing, insets.bottom))
}

/// One of the map screen's own cards: **where it sits on the display**, which its shape is resolved
/// from (`menuCardShape`), the glass that card is drawn on, and the swipe that throws it away.
///
/// The position has to be *measured* rather than handed down: the screen's cards are laid out
/// bottom-aligned in one column (`MapTabView.menuLayer`) and their own heights differ, so how far a
/// card's top corners are from the top of the display is its own business. The measurement is taken in
/// the window's space, which is the display's — this screen fills it.
///
/// The swipe's offset is added to that measurement **by hand**: `.offset` does not move a view's layout
/// frame, so a measurement taken while the card is being dragged reports where it rests, and the corner
/// that is being dragged away from a display edge has to know that it has moved.
///
/// `clipped` is for the one card that draws its own background — the workout card, which is the detail
/// screen in black — and wants only the shape; every other card is drawn on the glass here.
private struct MenuCardModifier: ViewModifier {
    /// The display's size, from the container the card is laid out in.
    let display: CGSize
    let clipped: Bool
    /// What a swipe down does to it.
    let onDismiss: () -> Void

    /// The card's drag, shared with the controls inside it (`menuCardDragHandle`): the card's own
    /// gesture and a button's handle pull the same offset.
    @StateObject private var drag = MenuCardDragState()
    /// Where the card was measured. Nothing until the first measurement lands, and a card drawn from
    /// nothing is drawn open — every corner away from the display — which is what `insets` answers.
    @State private var frame: CGRect = .zero
    /// The card's own height, measured off the card, so the drag's threshold and its rubber band are
    /// the card's rather than a fixed guess.
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        card(content)
            .offset(y: drag.offset)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0; drag.height = $0 }
            // The card's own drag is a plain `.gesture`, not a high-priority one, so a wheel inside
            // the card still spins, a slider still slides and a scroll view inside it still scrolls.
            // What the card's own gesture therefore *misses* — a button, whose tap wins over it — is
            // covered by the handle the controls carry themselves (`menuCardDragHandle`), so the card
            // is dragged from anywhere on it while every other control is left as it is.
            .gesture(dismissDrag)
            .environment(\.menuCardDrag, drag)
            .onAppear { drag.dismiss = onDismiss }
    }

    /// The card's own background, in the shape its position asks for.
    @ViewBuilder
    private func card(_ content: Content) -> some View {
        if clipped {
            content.clipShape(menuCardShape(insets: insets))
        } else {
            content.glassEffect(.regular, in: menuCardShape(insets: insets))
        }
    }

    /// Where the card sits, in points from each edge of the display — including how far the finger has
    /// pulled it, so a corner dragged away from the display edge resolves as one out in the open.
    private var insets: EdgeInsets {
        guard frame != .zero, display != .zero else { return EdgeInsets() }
        return EdgeInsets(top: frame.minY + drag.offset,
                          leading: frame.minX,
                          bottom: display.height - frame.maxY - drag.offset,
                          trailing: display.width - frame.maxX)
    }

    /// The drag a card answers to: it follows the finger down, springs back when the release does not
    /// carry it far enough, and lets itself go through `onDismiss` when it does. The pull and the
    /// settle live in `MenuCardDragState` so a control inside the card can drive the very same drag.
    ///
    /// The card is left exactly where the finger dropped it as it leaves: the dismissal is the card's
    /// own `move(edge: .bottom)` transition, which carries it on down from there rather than snapping
    /// it back to rest first.
    ///
    /// It is measured in the **window's** space (`.global`), and so is the handle a control inside the
    /// card carries (`MenuCardDragHandle`). That is not a detail: the card is moved by the very offset
    /// this drag writes (`.offset(y:)`), so a gesture measured in the *local* space of a view inside
    /// that moved subtree — the handle on a button — reads a translation that is already short by the
    /// offset applied so far, and the two writers (the card's gesture and the button's) then disagree
    /// by exactly that offset, frame by frame. The card was seen to **flicker between two y positions**
    /// while a drag from a button was under way, which is that disagreement. In the window's space
    /// both read the finger's own movement, so both write the same offset and there is nothing to
    /// disagree about.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { drag.update($0.translation.height) }
            .onEnded { drag.end($0.translation.height, predicted: $0.predictedEndTranslation.height) }
    }
}

/// The hairline between two rows of a settings card: one physical pixel, inset to where the row's
/// text starts, in the faint white the cards use.
struct RowDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.09))
            .frame(height: 1 / displayScale)
            .padding(.leading, 56)
    }
}

/// Full width yellow confirm button (sheet Done / export Save).
struct PrimaryButton: View {
    let title: String
    var height: CGFloat = 47
    /// Measured from the original app: both confirm buttons use a 10 pt radius.
    var radius: CGFloat = 10
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
