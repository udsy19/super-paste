import AppKit
import SuperPasteCore

// Commands: keys, menu items and buttons all end up here (behaviour.md §4.4–§4.6, §4.10, §5).
extension StripController {
    // MARK: Key routing

    /// Key presses reaching the strip's root view (key equivalents first, then unhandled key-downs).
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let key = KeyStroke(event: event)
        let responder = panel?.firstResponder
        if responder is NSText || responder is NSTextField {
            // Editing text (search, a title, a tab name): Quick Paste and a few strip commands still work; the
            // standard editing keys go to the text even when the hidden main menu isn't consulted.
            if StripKeyMap.quickPasteNumber(key) != nil,
               case .quickPaste(let n, let plainText)? = StripKeyMap.command(for: key, bindings: .current) {
                perform(.quickPaste(n, plainText: plainText)); return true
            }
            switch (key.characters.lowercased(), key.modifiers) {
            case ("f", .command): perform(.filters); return true
            case ("n", .command): perform(.newTextItem); return true
            case (",", .command): perform(.settings); return true
            default: break
            }
            if let action = Self.editingAction(for: key) { return NSApp.sendAction(action, to: nil, from: self) }
            return false
        }
        return handleKey(event)
    }

    static func editingAction(for key: KeyStroke) -> Selector? {
        switch (key.characters.lowercased(), key.modifiers) {
        case ("a", .command): #selector(NSText.selectAll(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("x", .command): #selector(NSText.cut(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("z", .command): Selector(("undo:"))
        case ("z", [.command, .shift]): Selector(("redo:"))
        default: nil
        }
    }

    // MARK: Commands

    func perform(_ command: StripCommand) {
        switch command {
        case .move(let delta, let extend):
            selection.move(by: delta, extend: extend, count: items.count)
            selectionChanged(reveal: true)
        case .first(let extend):
            selection.moveTo(0, extend: extend, count: items.count)
            selectionChanged(reveal: true)
        case .last(let extend):
            loadAll()
            selection.moveTo(items.count - 1, extend: extend, count: items.count)
            selectionChanged(reveal: true)
        case .page(let direction, let extend):
            selection.move(by: direction * (cards?.cardsPerPage ?? 1), extend: extend, count: items.count)
            selectionChanged(reveal: true)
        case .selectAll:
            loadAll()
            selection.selectAll(count: items.count)
            selectionChanged(reveal: false)
        case .paste(let plainText):
            paste(selectedItems, plainText: plainText)
        case .quickPaste(let n, let plainText):
            guard let first = cards?.firstVisibleIndex, let item = item(at: first + n - 1) else { NSSound.beep(); return }
            paste([item], plainText: plainText)
        case .preview:
            guard !selectedItems.isEmpty else { NSSound.beep(); return }
            preview.toggle(selectedItems, from: leadCard)
        case .copy:
            copy(selectedItems, plainText: false)
        case .edit:
            guard let item = leadItem, Self.isEditable(item) else { NSSound.beep(); return }
            preview.edit(item, from: leadCard)
        case .rename:
            beginRename()
        case .open:
            open(selectedItems)
        case .delete:
            delete(selectedItems)
        case .showInList:
            guard let item = leadItem, let target = showInTargets(for: item).first else { NSSound.beep(); return }
            reveal(item, in: target)
        case .undo:
            if undo.canUndo { undo.undo() } else { NSSound.beep() }
        case .redo:
            if undo.canRedo { undo.redo() } else { NSSound.beep() }
        case .filters:
            showFilters()
        case .previousList:
            stepList(-1)
        case .nextList:
            stepList(1)
        case .newTextItem:
            newTextItem.show(in: scope)
        case .settings:
            hide()
            Services.settings?.show(pane: nil)
        case .cancel:
            if preview.isShowing { preview.closePopover() }
            else if !query.isEmpty || toolbar?.search.isActive == true { toolbar?.search.clear(); focusCards() }
            else { hide() }
        case .switchFocus:
            if isSearchFocused { focusCards() } else { toolbar?.search.activate() }
        }
    }

    var leadCard: CardView? { selection.lead.flatMap { cards?.cardView(at: $0) } }

    private func loadAll() {
        guard let store = Services.store, items.count < total else { return }
        items += store.search(query, in: scope, limit: min(total, 10_000) - items.count, offset: items.count)
        cards?.refreshVisibleCards()
    }

    static func isEditable(_ item: ClipItem) -> Bool {
        switch item.kind {
        case .text, .richText, .html, .link, .color, .image: true
        case .files, .unknown: false
        }
    }

    private func stepList(_ delta: Int) {
        let lists = [ListScope.history] + pinboards.map { .pinboard($0.id) }
        guard let index = lists.firstIndex(of: scope) else { return }
        let next = min(max(0, index + delta), lists.count - 1)
        if next != index { setScope(lists[next]) }
    }

    // MARK: Paste, copy, open

    /// Pastes into the app that was frontmost before the strip opened: ClipboardKit hides the strip, writes the
    /// pasteboard, re-activates that app and sends ⌘V (or copies and shows the hint without Direct Paste). Several
    /// items paste in list order. "Always paste as Plain Text" turns every paste into a plain one.
    func paste(_ items: [ClipItem], plainText: Bool) {
        guard !items.isEmpty, let pasting = Services.pasting else { NSSound.beep(); return }
        pasting.paste(items, plainText: plainText || Defaults[.isPasteAsPlainTextEnabled])
    }

    func copy(_ items: [ClipItem], plainText: Bool) {
        guard !items.isEmpty, let pasting = Services.pasting else { NSSound.beep(); return }
        pasting.copy(items, plainText: plainText)
        HUD.show(L10n.copied)
    }

    /// Links open in the default browser, files in their default apps.
    func open(_ items: [ClipItem]) {
        let urls = items.flatMap(Self.openURLs)
        guard !urls.isEmpty else { NSSound.beep(); return }
        urls.forEach { NSWorkspace.shared.open($0) }
        hide()
    }

    static func openURLs(_ item: ClipItem) -> [URL] {
        switch item.kind {
        case .link: ItemPresentation.linkURL(item).map { [$0] } ?? []
        case .files: item.filePaths.map { URL(fileURLWithPath: $0) }
        default: []
        }
    }

    /// "Open in Safari" / "Open with Preview", or "Open" when the app isn't known.
    static func openTitle(_ item: ClipItem) -> String? {
        guard let url = openURLs(item).first else { return nil }
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return L10n.open }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        return item.kind == .link ? "Open in \(name)" : L10n.openWith(name)
    }

    func revealInFinder(_ item: ClipItem) {
        let urls = item.filePaths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        hide()
    }

    /// The lists holding the item ("Show in …"): History first, then its pinboards; the shown list only while
    /// searching (where showing it clears the search).
    func showInTargets(for item: ClipItem) -> [ListScope] {
        var lists: [ListScope] = item.isInHistory ? [.history] : []
        lists += item.pinboardIDs.filter { id in pinboards.contains { $0.id == id } }.map(ListScope.pinboard)
        return query.isEmpty ? lists.filter { $0 != scope } : lists
    }

    func listName(_ scope: ListScope) -> String {
        switch scope {
        case .history, .all: L10n.clipboard
        case .pinboard(let id): pinboards.first { $0.id == id }?.name ?? L10n.untitled
        }
    }

    // MARK: Delete (undoable)

    func delete(_ items: [ClipItem]) {
        guard !items.isEmpty, let store = Services.store else { NSSound.beep(); return }
        if items.count > 1 {
            hideSuppression += 1
            defer { hideSuppression -= 1 }
            guard Alerts.confirm(L10n.deleteItemsTitle(items.count), confirmTitle: L10n.delete, destructive: true,
                                 suppressionID: "stripKit.deleteSelectedItems") else { return }
            panel?.makeKey()
        }
        deleteItems(items.map(\.id), store: store)
    }

    private func deleteItems(_ ids: [UUID], store: ItemStoring) {
        do {
            try store.delete(ids)
            registerUndo(L10n.delete) { strip in strip.undoDelete(ids, store: store) }
        } catch { Alerts.error("Couldn't delete the items.", error) }
    }

    private func undoDelete(_ ids: [UUID], store: ItemStoring) {
        do {
            try store.undoLastDelete()
            registerUndo(L10n.delete) { strip in strip.deleteItems(ids, store: store) }
        } catch { Alerts.error("Couldn't restore the items.", error) }
    }

    // MARK: Item changes (undoable by restoring the previous values)

    /// Applies a change to items, registering an undo that writes their previous values back (titles, pins,
    /// content; behaviour.md §4.10).
    @discardableResult
    func changeItems(_ ids: [UUID], actionName: String, _ change: (ItemStoring) throws -> Void) -> Bool {
        guard let store = Services.store else { return false }
        let before = store.items(ids)
        do {
            try change(store)
            registerRestore(before, actionName: actionName)
            return true
        } catch {
            Alerts.error("Couldn't change the item.", error)
            return false
        }
    }

    private func registerRestore(_ previous: [ClipItem], actionName: String) {
        guard !previous.isEmpty else { return }
        registerUndo(actionName) { strip in strip.restore(previous, actionName: actionName) }
    }

    /// Registers one undo step (its own group outside undo and redo, which group their inverse themselves).
    func registerUndo(_ actionName: String, _ handler: @escaping @MainActor (StripController) -> Void) {
        let grouped = !undo.isUndoing && !undo.isRedoing
        if grouped { undo.beginUndoGrouping() }
        undo.registerUndo(withTarget: self) { strip in MainActor.assumeIsolated { handler(strip) } }
        undo.setActionName(actionName)
        if grouped { undo.endUndoGrouping() }
    }

    private func restore(_ previous: [ClipItem], actionName: String) {
        guard let store = Services.store else { return }
        let current = store.items(previous.map(\.id))
        do {
            for item in previous { try store.update(item) }
            registerRestore(current, actionName: actionName)
        } catch { Alerts.error("Couldn't undo the change.", error) }
    }

    func beginRename() {
        guard let item = leadItem, let index = selection.lead else { NSSound.beep(); return }
        cards?.scrollToReveal(index, animated: false)
        cards?.tile()
        guard let card = cards?.cardView(at: index) else { return }
        card.beginRename { [weak self] title, committed in
            guard let self else { return }
            if committed, title != item.title {
                self.changeItems([item.id], actionName: L10n.rename) { try $0.rename(item.id, to: title) }
            }
            self.focusCards()
        }
    }

    // MARK: Pins (one pinboard per item, as in Paste)

    func pin(_ items: [ClipItem], to board: UUID) {
        let ids = items.map(\.id)
        changeItems(ids, actionName: L10n.pin) { store in
            try store.assign(ids, to: board)
            for item in items {
                for other in item.pinboardIDs where other != board { try store.unassign([item.id], from: other) }
            }
        }
    }

    func unpin(_ items: [ClipItem]) {
        let ids = items.map(\.id)
        changeItems(ids, actionName: L10n.unpin) { store in
            for item in items {
                for board in item.pinboardIDs { try store.unassign([item.id], from: board) }
            }
        }
    }

    // MARK: Pinboards

    func createPinboard(pinning items: [ClipItem] = []) {
        guard let store = Services.store else { return }
        let color = PinboardColor.allCases[pinboards.count % PinboardColor.allCases.count]
        do {
            let board = try store.createPinboard(name: L10n.untitled, color: color)
            if !items.isEmpty { pin(items, to: board.id) }
            reloadPinboards()
            toolbar?.layoutSubtreeIfNeeded()
            toolbar?.tabBar.beginRename(board.id)
        } catch { Alerts.error("Couldn't create the pinboard.", error) }
    }

    func renamePinboard(_ id: UUID, to name: String) {
        guard let store = Services.store, var board = store.pinboards.first(where: { $0.id == id }) else { return }
        board.name = name
        do { try store.updatePinboard(board) } catch { Alerts.error("Couldn't rename the pinboard.", error) }
        reloadPinboards()
    }

    func recolorPinboard(_ id: UUID, to color: PinboardColor) {
        guard let store = Services.store, var board = store.pinboards.first(where: { $0.id == id }) else { return }
        board.color = color
        do { try store.updatePinboard(board) } catch { Alerts.error("Couldn't change the colour.", error) }
        reloadPinboards()
        cards?.refreshVisibleCards()
    }

    func deletePinboard(_ id: UUID) {
        guard let store = Services.store, let board = pinboards.first(where: { $0.id == id }) else { return }
        hideSuppression += 1
        defer { hideSuppression -= 1 }
        guard Alerts.confirm(L10n.deletePinboardTitle(board.name), info: L10n.deletePinboardText,
                             confirmTitle: L10n.delete, destructive: true) else { return }
        panel?.makeKey()
        do {
            try store.deletePinboard(id)
            if scope == .pinboard(id) { setScope(.history) }
            reloadPinboards()
        } catch { Alerts.error("Couldn't delete the pinboard.", error) }
    }

    func eraseHistory() {
        guard let store = Services.store else { return }
        hideSuppression += 1
        defer { hideSuppression -= 1 }
        let info = Services.sync?.folder != nil ? L10n.eraseHistoryText + " " + L10n.eraseHistorySyncedText : L10n.eraseHistoryText
        guard Alerts.confirm(L10n.eraseHistoryTitle, info: info, confirmTitle: L10n.erase, destructive: true) else { return }
        panel?.makeKey()
        do { try store.eraseHistory() } catch { Alerts.error("Couldn't erase the history.", error) }
    }
}
