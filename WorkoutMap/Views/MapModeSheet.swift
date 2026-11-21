import SwiftUI
import MapKit

/// The map style picker: Apple Maps' own "Map Modes" panel, with the app's grey map kept as
/// the fifth entry, `Legacy`.
///
/// Every tile is bundled artwork — Maps' own for its four styles, the grey Explore tile for
/// `Legacy` — so the panel is complete the moment it opens. The tiles were snapshots of the
/// region the map was showing until now, which meant five `MKMapSnapshotter` runs per opening
/// and an empty panel while they arrived.
struct MapModeSheet: View {
    @Binding var mode: MapMode
    /// The appearance setting and the system's own style, so every tile is the artwork of the
    /// style the map is being drawn in: light, dark, or — for `system` — whatever the phone is
    /// set to. `legacy` keeps its grey tile either way.
    let appearance: MapAppearance
    let systemStyle: UIUserInterfaceStyle

    @Environment(\.dismiss) private var dismiss

    /// Square tiles, as in Maps. The row is as wide as the five of them and their gaps make
    /// it, and the tiles take everything the sheet has to give up to `tileMax` — so they grow
    /// with the display instead of leaving the wide margins a fixed size would.
    private static let tileMax: CGFloat = 96
    private static let tileGap: CGFloat = 8
    private static let sideInset: CGFloat = 12
    private static let detent: CGFloat = 200

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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // On the folded panel the sheet's content is laid out beside the rail, 76 pt narrower
        // than the card it is drawn in (measured: a 374 pt content area in a 466 pt window),
        // and a row centred in there sits visibly off to one side — which side depending on
        // where the rail is. The card covers that strip anyway, so the row is centred on the
        // card instead.
        .ignoresSafeArea(.container, edges: .horizontal)
        .glassPanel()
        .presentationDetents([.height(Self.detent)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(12)
    }

    private var header: some View {
        ZStack {
            Text("Map Modes")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            HStack {
                Spacer()
                CloseCircleButton { dismiss() }
            }
        }
        .padding(.horizontal, Metrics.contentInset)
        .padding(.top, 14)
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
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
