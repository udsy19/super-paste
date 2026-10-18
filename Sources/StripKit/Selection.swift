import Foundation

/// How a click changes the selection (ui-reference §4.6 `CollectionView.SelectionMode`): ⇧ range, ⌘ toggle.
enum SelectionMode: Equatable {
    case single, range, toggle
}

/// The selection over a list of `count` cards, by index. `anchor` is where a range starts; `lead` is the card the
/// keyboard moves from (the most recently clicked or reached one). Pure, so it is unit-tested.
struct SelectionState: Equatable {
    private(set) var indices: IndexSet = []
    private(set) var anchor: Int?
    private(set) var lead: Int?

    init() {}

    init(indices: IndexSet, anchor: Int?, lead: Int?) {
        self.indices = indices; self.anchor = anchor; self.lead = lead
    }

    var isEmpty: Bool { indices.isEmpty }
    var count: Int { indices.count }
    func contains(_ index: Int) -> Bool { indices.contains(index) }

    mutating func clear() { self = SelectionState() }

    mutating func click(_ index: Int, mode: SelectionMode) {
        switch mode {
        case .single:
            indices = [index]; anchor = index; lead = index
        case .toggle:
            if indices.contains(index) {
                indices.remove(index)
                if lead == index { lead = indices.isEmpty ? nil : indices.integerLessThanOrEqualTo(index) ?? indices.first }
                if anchor == index { anchor = lead }
            } else {
                indices.insert(index); anchor = index; lead = index
            }
        case .range:
            let start = anchor ?? lead ?? index
            indices = IndexSet(integersIn: min(start, index)...max(start, index))
            anchor = start; lead = index
        }
    }

    /// ← / → (and ⇧ to extend): moves the lead by `delta`, clamped to the list.
    mutating func move(by delta: Int, extend: Bool, count: Int) {
        guard count > 0 else { clear(); return }
        let from = lead ?? (delta > 0 ? -1 : count)
        moveTo(min(max(0, from + delta), count - 1), extend: extend, count: count)
    }

    /// Home / End / Page keys, or ⇧ with them to extend.
    mutating func moveTo(_ index: Int, extend: Bool, count: Int) {
        guard count > 0 else { clear(); return }
        let target = min(max(0, index), count - 1)
        click(target, mode: extend ? .range : .single)
    }

    mutating func selectAll(count: Int) {
        guard count > 0 else { clear(); return }
        indices = IndexSet(integersIn: 0..<count)
        anchor = anchor ?? 0
        lead = lead ?? 0
    }

    /// Keeps only indices that still exist after the list shrank or grew.
    mutating func clamp(to count: Int) {
        indices = indices.filteredIndexSet { $0 < count }
        if let a = anchor, a >= count { anchor = indices.last }
        if let l = lead, l >= count { lead = indices.last }
        if indices.isEmpty { anchor = nil; lead = nil }
    }
}
