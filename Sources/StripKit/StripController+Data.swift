import AppKit
import SuperPasteCore

// Loading the list, selection and the card row's callbacks.
extension StripController: CardCollectionDelegate {
    // MARK: Loading

    /// Reloads the shown list from the store, keeping the selected items selected when they're still there.
    func reload(keepSelection: Bool) {
        needsReload = false
        let selectedIDs = keepSelection ? selectedItems.map(\.id) : []
        let lead = selection.lead.flatMap { items.indices.contains($0) ? items[$0].id : nil }
        guard let store = Services.store else { items = []; total = 0; return }
        total = store.count(query, in: scope)
        items = store.search(query, in: scope, limit: max(Self.pageSize, items.count), offset: 0)
        var next = SelectionState()
        let indices = IndexSet(selectedIDs.compactMap { id in items.firstIndex { $0.id == id } })
        if !indices.isEmpty {
            let leadIndex = lead.flatMap { id in items.firstIndex { $0.id == id } } ?? indices.first!
            next = SelectionState(indices: indices, anchor: leadIndex, lead: leadIndex)
        } else if !items.isEmpty {
            next.click(min(selection.lead ?? 0, items.count - 1), mode: .single)
        }
        selection = next
        reloadPinboards()
        updateEmptyState()
        cards?.reloadData()
    }

    func reloadPinboards() {
        pinboards = Services.store?.pinboards ?? []
        if case .pinboard(let id) = scope, !pinboards.contains(where: { $0.id == id }) { self.scope = .history }
        var entries = [TabEntry(scope: .history, name: L10n.clipboard, color: nil)]
        entries += pinboards.map { TabEntry(scope: .pinboard($0.id), name: $0.name, color: $0.color) }
        toolbar?.tabBar.selected = scope
        toolbar?.tabBar.setEntries(entries)
        toolbar?.needsLayout = true
    }

    private func loadMore() {
        guard items.count < total, let store = Services.store else { return }
        let page = store.search(query, in: scope, limit: Self.pageSize, offset: items.count)
        guard !page.isEmpty else { total = items.count; return }
        items += page
        cards?.refreshVisibleCards()
    }

    func storeChanged(_ change: StoreChange) {
        guard isVisible else { needsReload = true; return }
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reloadScheduled = false
                self.reload(keepSelection: true)
            }
        }
    }

    func setScope(_ scope: ListScope) {
        guard scope != self.scope || needsReload else { return }
        self.scope = scope
        Defaults[.selectedListIdentifier] = scope.id
        toolbar?.tabBar.selected = scope
        toolbar?.tabBar.scrollToSelected()
        selection.clear()
        items = []
        reload(keepSelection: false)
        cards?.scrollToStart()
    }

    func setQuery(_ query: SearchQuery) {
        guard query != self.query else { return }
        self.query = query
        selection.clear()
        items = []
        reload(keepSelection: false)
        cards?.scrollToStart()
    }

    private func updateEmptyState() {
        guard let root else { return }
        root.emptyLabel.isHidden = !items.isEmpty
        if !query.isEmpty { root.emptyLabel.stringValue = L10n.nothingFound }
        else if case .pinboard = scope { root.emptyLabel.stringValue = L10n.pinboardEmpty }
        else { root.emptyLabel.stringValue = L10n.historyEmpty }
        root.needsLayout = true
    }

    /// Shows the list holding `item` (History first) and selects it, loading pages until it is found.
    func reveal(_ item: ClipItem, in target: ListScope? = nil) {
        let destination = target ?? (item.isInHistory ? .history : item.pinboardIDs.first.map(ListScope.pinboard) ?? .history)
        if !query.isEmpty { toolbar?.search.clear() }
        if destination != scope { setScope(destination) }
        var index = items.firstIndex { $0.id == item.id }
        while index == nil, items.count < total, items.count < 10_000 {
            loadMore()
            index = items.firstIndex { $0.id == item.id }
        }
        guard let index else { return }
        selection.click(index, mode: .single)
        cards?.updateSelection()
        cards?.scrollToReveal(index, animated: false)
    }

    // MARK: Selection

    var selectedItems: [ClipItem] { selection.indices.compactMap { items.indices.contains($0) ? items[$0] : nil } }

    var leadItem: ClipItem? { selection.lead.flatMap { items.indices.contains($0) ? items[$0] : nil } ?? selectedItems.first }

    func selectionChanged(reveal: Bool) {
        cards?.updateSelection()
        if reveal, let lead = selection.lead { cards?.scrollToReveal(lead) }
        preview.selectionChanged(selectedItems, anchor: selection.lead.flatMap { cards?.cardView(at: $0) })
    }

    // MARK: CardCollectionDelegate

    var cardCount: Int { items.count }

    func item(at index: Int) -> ClipItem? { items.indices.contains(index) ? items[index] : nil }

    func cardContext() -> CardContext {
        let geometry = cards?.geometry ?? StripGeometry(style: style, panelHeight: panelHeight)
        return CardContext(style: style, side: geometry.cardSide, sizeClass: geometry.sizeClass, scope: scope,
                           pinboards: pinboards, now: Date(), linkPreviewsEnabled: Defaults[.isLinkPreviewsEnabled],
                           fileThumbnailsEnabled: Defaults[.isFileItemQLThumbnailImageEnabled])
    }

    func isCardSelected(_ index: Int) -> Bool { selection.contains(index) }

    func cardClicked(_ index: Int, mode: SelectionMode) {
        focusCards()
        selection.click(index, mode: mode)
        selectionChanged(reveal: false)
    }

    func cardDoubleClicked(_ index: Int, plainText: Bool) {
        guard let item = item(at: index) else { return }
        paste([item], plainText: plainText)
    }

    func emptyAreaClicked() { focusCards() }

    func dragItems(startingAt index: Int) -> [ClipItem] {
        selection.contains(index) ? selectedItems : (item(at: index).map { [$0] } ?? [])
    }

    var canReorderCards: Bool {
        if case .pinboard = scope { return query.isEmpty }
        return false
    }

    func moveCards(_ ids: [UUID], toIndex index: Int) {
        guard case .pinboard(let board) = scope, let store = Services.store else { return }
        let before = items.indices.contains(index) ? items[index].id : nil
        let moving = Set(ids)
        let beforeID = before.flatMap { moving.contains($0) ? items[index...].first { !moving.contains($0.id) }?.id : $0 }
        let previousOrder = items.map(\.id)
        do {
            try store.move(ids, in: board, before: beforeID)
            registerUndo(L10n.pin) { strip in strip.restoreOrder(previousOrder, in: board) }
        } catch { Alerts.error("Couldn't move the items.", error) }
    }

    private func restoreOrder(_ ids: [UUID], in board: UUID) {
        try? Services.store?.move(ids, in: board, before: nil)
    }

    func cardsVisible(through index: Int) {
        if index >= items.count - 20 { loadMore() }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if let command = StripKeyMap.command(for: KeyStroke(event: event), bindings: .current) {
            perform(command)
            return true
        }
        let key = KeyStroke(event: event)
        if StripKeyMap.startsSearch(key), let text = event.characters, !text.isEmpty {
            toolbar?.search.insertTyped(text)
            return true
        }
        return false
    }

    func dragSessionChanged(active: Bool) {
        hideSuppression += active ? 1 : -1
        hideSuppression = max(0, hideSuppression)
    }
}
