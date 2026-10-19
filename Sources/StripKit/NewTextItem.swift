import AppKit
import SuperPasteCore

extension Defaults.Keys {
    /// Text typed into New Text Item but not yet created: kept across a quit or crash and put back next time.
    static let stripKitNewTextDraft = Key<String>("stripKit.newTextItemDraft", default: "")
}

/// "New Text Item" (behaviour.md §4.9, ui-reference §7): a floating panel with a text editor; Create (⌘S) adds the
/// text to the list the strip shows (History, or the pinboard as a pinned-only item). What is typed is kept as a
/// draft until it is created or deliberately discarded, so a quit, a crash or a stray Esc can't lose it.
@MainActor
final class NewTextItemController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    weak var strip: StripController?
    private(set) var window: NSPanel?
    private var textView: NSTextView?
    private var scope: ListScope = .history

    /// The text in the window, or the saved draft while it is closed.
    var text: String { textView?.string ?? Defaults[.stripKitNewTextDraft] }

    /// Opens the window (activating Super Paste so it takes typing); `activating: false` only builds it (renders).
    func show(in scope: ListScope, activating: Bool = true) {
        self.scope = scope
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let size = PreviewController.initialSize(for: NSScreen.main)
        let min = SPMetrics.CreateItem.minWindowSize
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: max(size.width, min.width), height: max(size.height, min.height)),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
                            backing: .buffered, defer: true)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = L10n.newTextItem
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.minSize = min
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .documentWindow
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let view = NewTextItemView(style: strip?.style ?? .current)
        view.onCancel = { [weak self] in self?.cancel() }
        view.onCreate = { [weak self] in self?.create() }
        panel.contentView = view
        textView = view.textView
        view.textView.delegate = self
        view.textView.string = Defaults[.stripKitNewTextDraft]
        window = panel
        panel.center()
        guard activating else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view.textView)
    }

    private func create() {
        let text = textView?.string ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let store = Services.store else { NSSound.beep(); return }
        let draft: ClipDraft
        switch scope {
        case .pinboard(let id): draft = .text(text, copiedAt: nil, pinboardID: id)
        case .history, .all: draft = .text(text)
        }
        do {
            let result = try store.insert(draft)
            Defaults[.stripKitNewTextDraft] = ""
            close()
            if let strip, strip.isVisible { strip.reveal(result.item, in: scope == .all ? .history : scope) }
        } catch { Alerts.error("Couldn't create the item.", error) }
    }

    /// Cancel and Esc: text that is there is discarded only after asking.
    private func cancel() {
        let text = textView?.string ?? ""
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !Alerts.confirm(L10n.discardTextTitle, info: L10n.discardTextText, confirmTitle: L10n.discardEdits,
                           cancelTitle: L10n.keepEditing, destructive: true) { return }
        Defaults[.stripKitNewTextDraft] = ""
        close()
    }

    /// Closes the window; a draft that is there stays saved for next time.
    func close() {
        window?.close()
        window = nil
        textView = nil
    }

    func textDidChange(_ notification: Notification) {
        Defaults[.stripKitNewTextDraft] = textView?.string ?? ""
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        textView = nil
    }
}

private final class NewTextItemView: FlippedView {
    let textView: NSTextView
    private let scroll = NSTextView.scrollableTextView()
    private let border = FillView()
    private let title = Labels.make(L10n.newTextItem, font: SPFont.style(.headline), color: .labelColor, alignment: .center)
    private let cancel: ToolbarButton
    private let createButton: ToolbarButton
    var onCancel: (() -> Void)?
    var onCreate: (() -> Void)?

    init(style: SPStyle) {
        textView = scroll.documentView as! NSTextView
        cancel = ToolbarButton(size: .regular, style: style, title: L10n.cancel)
        createButton = ToolbarButton(size: .regular, style: style, title: L10n.create)
        super.init(frame: .zero)
        textView.font = SPFont.style(.body)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.drawsBackground = false
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        border.borderColor = SPColor.ink10
        border.borderWidth = SPMetrics.Preview.contentBorderWidth
        border.cornerRadius = SPMetrics.Preview.contentBorderRadius
        cancel.toolTip = L10n.discardChanges
        cancel.action = { [weak self] _ in self?.onCancel?() }
        createButton.isPrimary = true
        createButton.toolTip = "\(L10n.createTextItem) (⌘S)"
        createButton.action = { [weak self] _ in self?.onCreate?() }
        [scroll, border, title, cancel, createButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let h = SPMetrics.Preview.headerHeight
        let createSize = createButton.fittingSize, cancelSize = cancel.fittingSize
        createButton.frame = NSRect(x: bounds.width - 8 - createSize.width, y: round((h - createSize.height) / 2),
                                    width: createSize.width, height: createSize.height)
        cancel.frame = NSRect(x: createButton.frame.minX - 8 - cancelSize.width, y: createButton.frame.minY,
                              width: cancelSize.width, height: cancelSize.height)
        let titleHeight = title.labelSize.height
        let side = bounds.width - cancel.frame.minX + 8
        title.frame = NSRect(x: side, y: round((h - titleHeight) / 2), width: max(0, bounds.width - 2 * side), height: titleHeight)
        scroll.frame = NSRect(x: 8, y: h, width: max(0, bounds.width - 16), height: max(0, bounds.height - h - 8))
        border.frame = scroll.frame
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let key = KeyStroke(event: event)
        if key.modifiers == .command, key.characters.lowercased() == "s" { onCreate?(); return true }
        if key.modifiers.isEmpty, key.keyCode == 53 { onCancel?(); return true }
        if let action = StripController.editingAction(for: key) { return NSApp.sendAction(action, to: nil, from: self) }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
