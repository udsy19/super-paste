import SwiftUI
import SuperPasteCore

/// The Filters popover (ui-reference §3.3): sections App / Date / Device / Pinboard / Type, each a flexible grid of
/// items (10 × 6 padding, body font); the selected ones on the accent colour; long sections collapse behind More.
struct FilterBrowserView: View {
    let sources: FilterSources
    let style: SPStyle
    let onToggle: (SearchQuery.Filter) -> Void
    @State private var applied: [SearchQuery.Filter]
    @State private var expanded: Set<SearchQuery.FilterType> = []

    static let collapsedItemLimit = 6

    init(sources: FilterSources, applied: [SearchQuery.Filter], style: SPStyle, onToggle: @escaping (SearchQuery.Filter) -> Void) {
        self.sources = sources
        self.style = style
        self.onToggle = onToggle
        _applied = State(initialValue: applied)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(sources.sections.filter { !$0.items.isEmpty }, id: \.type) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.filterSection(section.type))
                        .font(.callout.bold())
                        .foregroundStyle(.secondary)
                    let open = expanded.contains(section.type)
                    let shown = open ? section.items : Array(section.items.prefix(Self.collapsedItemLimit))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), alignment: .leading,
                              spacing: 10) {
                        ForEach(shown, id: \.filter) { item in
                            FilterChip(title: item.title, selected: applied.contains(item.filter), style: style) {
                                if let index = applied.firstIndex(of: item.filter) { applied.remove(at: index) }
                                else { applied.append(item.filter) }
                                onToggle(item.filter)
                            }
                        }
                    }
                    if section.items.count > Self.collapsedItemLimit {
                        Button(open ? L10n.less : L10n.more) {
                            if open { expanded.remove(section.type) } else { expanded.insert(section.type) }
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }
}

private struct FilterChip: View {
    let title: String
    let selected: Bool
    let style: SPStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ChipStyle(selected: selected, radius: style == .glass ? 100 : 6))
    }
}

private struct ChipStyle: ButtonStyle {
    let selected: Bool
    let radius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(selected ? Color.accentColor : Color(nsColor: SPColor.ink05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.1 : 0))
            )
            .contentShape(Rectangle())
    }
}
