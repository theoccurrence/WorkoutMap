import SwiftUI
import MapKit

/// The map style picker: Apple Maps' own "Map Modes" panel, with the app's grey map kept as
/// the fifth entry, `Legacy`.
///
/// Drawn as one of the map screen's own cards (`View.menuCard()`), the same shape as the sheet the
/// range bubble opens, rather than presented as a sheet: a sheet lies over the screen's chrome on
/// the Duo, and the row of tiles is centred on the card itself whatever the window reserves at its
/// edges.
///
/// Every tile is bundled artwork — Maps' own for its four styles, the grey Explore tile for
/// `Legacy` — so the panel is complete the moment it opens. The tiles were snapshots of the
/// region the map was showing until now, which meant five `MKMapSnapshotter` runs per opening
/// and an empty panel while they arrived.
struct MapModePanel: View {
    @Binding var mode: MapMode
    /// The appearance setting and the system's own style, so every tile is the artwork of the
    /// style the map is being drawn in: light, dark, or — for `system` — whatever the phone is
    /// set to. `legacy` keeps its grey tile either way.
    let appearance: MapAppearance
    let systemStyle: UIUserInterfaceStyle
    /// How much room the card has to work with (`MapTabView.menuLayer`).
    let room: CGFloat
    var onClose: () -> Void

    /// Whether Satellite draws its labels layer. Kept in the settings, so the map opens the way
    /// the user last left it; the toggle below the tiles writes it.
    @AppStorage(MapMode.satelliteLabelsKey) private var satelliteLabels = true

    /// Square tiles, as in Maps. The row is as wide as the five of them and their gaps make
    /// it, and the tiles take everything the panel has to give up to `tileMax` — so they grow
    /// with the display instead of leaving the wide margins a fixed size would.
    private static let tileMax: CGFloat = 96
    private static let tileGap: CGFloat = 8
    private static let sideInset: CGFloat = 12
    /// The panel's own height: what the sheet it used to be was handed as a detent, plus the room the
    /// close cross takes above the title (`Metrics.menuCardCrossInset`) — without it the row of tiles was
    /// pushed down until its labels sat on the card's own bottom edge.
    private static let panelHeight: CGFloat = 200 + Metrics.menuCardCrossInset
    /// The room the Labels **bar** takes under the tiles: the bar itself (50 pt), its gap to the
    /// tiles (18) and the card's own bottom breathing (12). It is part of the height in **every**
    /// mode — the card must not change size when the mode changes — and only the bar's contents fade
    /// in and out.
    private static let labelsBarHeight: CGFloat = 80

    /// The panel's own height, or whatever the display has room for (`MapTabView.menuRoom`).
    private var height: CGFloat { min(Self.panelHeight + Self.labelsBarHeight, room) }

    var body: some View {
        GeometryReader { proxy in
            let side = tileWidth(available: proxy.size.width)
            VStack(spacing: 0) {
                header
                HStack(alignment: .top, spacing: Self.tileGap) {
                    ForEach(MapMode.allCases) { item in
                        tile(item, width: side)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                // The Labels bar, as Maps draws it: a row of its own under the tiles. The room for it
                // is there in every mode — the card is the same height whatever is selected — and only
                // the bar's contents fade in, for Satellite.
                labelsBar
                    .padding(.top, 18)
                    .opacity(mode == .satellite ? 1 : 0)
                    .allowsHitTesting(mode == .satellite)
                    .animation(.easeInOut(duration: 0.25), value: mode == .satellite)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        // The close cross is not part of the header's own row: it is placed against the **card's**
        // top-trailing corner, on the column the map screen's own toolbar keeps
        // (`Metrics.menuCardCrossInset`), and the header only leaves it the room above the title.
        // Laid out inside the header it would follow the header's own inset instead and miss that
        // column — and a card of the display is where that column is defined, not the card's row.
        .overlay(alignment: .topTrailing) {
            MenuCloseButton { onClose() }
                .padding(.top, Metrics.menuCardCrossInset)
                .padding(.trailing, Metrics.menuCardCrossInset)
        }
    }

    /// Satellite's own row, as Maps carries it: the labels layer in a **bar of its own** under the
    /// tiles — a rounded row inset from the card's edges, with the label and the switch set well
    /// inside it (measured off Apple Maps' own panel: the bar sits 13 pt in from the card, and both
    /// the label and the switch 24 pt inside the bar).
    private var labelsBar: some View {
        Toggle(isOn: $satelliteLabels) {
            Text("Labels")
                .font(.system(size: 17))
                .foregroundStyle(.white)
        }
        .tint(Palette.accent)
        .padding(.horizontal, 24)
        .frame(height: 50)
        .background(Color.white.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 13)
    }

    /// The title, with the room the close cross above it takes.
    private var header: some View {
        Text("Map Modes")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.menuHeaderHeight)
            .padding(.top, Metrics.menuCardCrossInset)
    }

    private func tileWidth(available: CGFloat) -> CGFloat {
        let columns = CGFloat(MapMode.allCases.count)
        let gaps = Self.tileGap * (columns - 1)
        return min(Self.tileMax, floor((available - 2 * Self.sideInset - gaps) / columns))
    }

    private func tile(_ item: MapMode, width: CGFloat) -> some View {
        let selected = item == mode
        return Button {
            mode = item
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    if let artwork = item.artwork(for: appearance.interfaceStyle(for: item, system: systemStyle)) {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.white.opacity(0.08)
                    }
                }
                .frame(width: width, height: width)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Palette.modeSelection : Color.white.opacity(0.14),
                                      lineWidth: selected ? 2 : 1)
                }

                Text(item.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A tile is one of the card's own drag handles: the card is dragged from a tile as from
        // anywhere else on it — a tap still picks the style (the drag needs 8 pt of travel first).
        .menuCardDragHandle()
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
