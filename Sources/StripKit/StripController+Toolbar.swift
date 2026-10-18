import AppKit
import SwiftUI
import SuperPasteCore

// The tab bar and search field callbacks.
extension StripController: TabBarDelegate, SearchFieldDelegate {
    // MARK: TabBarDelegate

    func tabSelected(_ scope: ListScope) {
        if !query.isEmpty { toolbar?.search.clear() }
        setScope(scope)
        focusCards()
    }

    func tabRenamed(_ pinboardID: UUID, to name: String?) {
        if let name { renamePinboard(pinboardID, to: name) } else { reloadPinboards() }
        focusCards()
    }

    func tabAcceptsDrop(_ scope: ListScope) -> Bool {
        if case .pinboard = scope { return true }
        return false
    }

    func tabDropped(_ itemIDs: [UUID], on scope: ListScope) {
        guard case .pinboard(let board) = scope, let store = Services.store else { return }
        pin(store.items(itemIDs), to: board)
    }

    func tabsReordered(_ pinboardIDs: [UUID]) {
        do { try Services.store?.reorderPinboards(pinboardIDs) } catch { Alerts.error("Couldn't reorder the pinboards.", error) }
        reloadPinboards()
    }

    /// "<name> (⌘←, ⌘→ to navigate)".
    func tabTooltip(_ entry: TabEntry) -> String {
        let bindings = StripKeyBindings.current
        return L10n.tabTooltip(entry.name, previous: bindings.previousList?.displayString, next: bindings.nextList?.displayString)
    }

    // MARK: SearchFieldDelegate

    func searchQueryChanged(_ query: SearchQuery) { setQuery(query) }

    func searchActiveChanged(_ active: Bool) {
        toolbar?.setSearchActive(active, animated: true)
    }

    func searchForwardKey(_ event: NSEvent) -> Bool {
        let key = KeyStroke(event: event)
        guard let command = StripKeyMap.command(for: key, bindings: .current) else { return false }
        switch command {
        case .paste, .quickPaste:
            perform(command); return true
        case .switchFocus:
            focusCards(); return true
        default:
            return false
        }
    }

    /// Esc in an empty field: nothing left to clear, so the preview or the strip closes.
    func searchCancelled() {
        if preview.isShowing { preview.closePopover() } else { hide() }
    }

    func searchShowFilters() { showFilters() }

    var filterSources: FilterSources { FilterSources.current }

    // MARK: Filter browser (⌘F)

    func showFilters() {
        guard let search = toolbar?.search else { return }
        if !search.isActive { search.activate() }
        search.layoutSubtreeIfNeeded()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        let browser = FilterBrowserView(sources: filterSources, applied: query.filters, style: style) { [weak self] filter in
            self?.toolbar?.search.toggleFilter(filter)
        }
        let host = NSHostingController(rootView: browser)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        let anchor = search.filtersAnchor
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.topEdge)
    }
}
