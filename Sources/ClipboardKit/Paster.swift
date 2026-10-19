import AppKit
import Combine
import SuperPasteCore

/// Writes items back and pastes them (behaviour.md §3): direct paste into the target app with ⌘V when Accessibility
/// allows it, plain text, several items, and the Paste Stack with its temporary ⌘V.
@MainActor
package final class Paster: Pasting {
    /// How long a paste waits for the target app to come forward, and how often it looks.
    package static let activationTimeout: TimeInterval = 1
    package static let activationCheckInterval: TimeInterval = 0.025
    /// Lets the target's key window settle (after it came forward, or after the strip gave focus back) before ⌘V.
    package static let activationSettle: TimeInterval = 0.05
    /// Between the writes of a sequential multi-item paste, so each ⌘V reads its own content.
    package static let stepInterval: TimeInterval = 0.2
    /// The Paste Stack's ⌘V comes back this long after a synthetic ⌘V, so it doesn't catch that one.
    package static let hotkeyResumeDelay: TimeInterval = 0.25
    /// The "Copied" toast's hint when the content went to the clipboard instead of straight into the app.
    package static let pasteHint = "Press ⌘V to paste"

    private let env: ClipboardEnvironment
    private let monitor: ClipboardMonitor
    private var stack = PasteStackEngine()
    private let stackSubject: CurrentValueSubject<PasteStackState, Never>
    private var stackHotkeyRegistered = false
    private var hotkeyResumeGeneration = 0
    private var pasteGeneration = 0
    private var lastTarget: PasteTarget?
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []

    package init(environment: ClipboardEnvironment, monitor: ClipboardMonitor) {
        env = environment
        self.monitor = monitor
        stack.setDirection(Defaults[.pasteStackDirection])
        stackSubject = CurrentValueSubject(stack.state)
        if let front = environment.frontmostApp() { noteActivation(front) }
        monitor.captures.sink { [weak self] item in self?.captured(item) }.store(in: &cancellables)
        environment.store()?.changes.sink { [weak self] change in self?.storeChanged(change) }.store(in: &cancellables)
    }

    // MARK: Paste target

    package var target: PasteTarget? { lastTarget }

    /// Follows app activations to know where pastes go.
    func trackActivations() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                                     queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let target = PasteTarget(app)
            MainActor.assumeIsolated { self?.noteActivation(target) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                                     queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.noteTermination(processID: pid) }
        })
        workspaceObservers.append(NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyboardLayoutChanged() }
        })
    }

    /// The V key may sit elsewhere on the new layout: a registered stack ⌘V moves with it.
    package func keyboardLayoutChanged() {
        guard stackHotkeyRegistered else { return }
        env.unregisterStackHotkey()
        stackHotkeyRegistered = false
        syncStackHotkey()
    }

    /// An app came to the front: it becomes the paste target unless it is Super Paste.
    package func noteActivation(_ app: PasteTarget) {
        guard !isOwn(app) else { return }
        lastTarget = app
    }

    package func noteTermination(processID: pid_t) {
        if lastTarget?.processID == processID { lastTarget = nil }
    }

    private func isOwn(_ app: PasteTarget) -> Bool {
        app.processID == getpid() || app.bundleID?.caseInsensitiveCompare(env.ownBundleID) == .orderedSame
    }

    // MARK: Pasting

    /// The strip goes first: while it shows it is the key window, so a ⌘V typed before it is off screen lands in the
    /// strip instead of the app. The paste itself runs once the strip has gone (at once when it wasn't showing).
    package func paste(_ items: [ClipItem], plainText: Bool) {
        let steps = plan(items, plainText: plainText || Defaults[.isPasteAsPlainTextEnabled])
        guard !steps.isEmpty else { return env.beep() }
        pasteGeneration += 1
        let generation = pasteGeneration
        let target = lastTarget
        let directly = Defaults[.isDirectPasteEnabled]
        env.hideStrip { [weak self] in
            guard let self, generation == self.pasteGeneration else { return }
            self.deliver(steps, to: target, directly: directly, generation: generation)
        }
    }

    package func copy(_ items: [ClipItem], plainText: Bool) {
        let steps = plan(items, plainText: plainText)
        guard !steps.isEmpty else { return env.beep() }
        write(PastePlan.merged(steps))
        used(steps)
    }

    package func pasteboardWriters(for items: [ClipItem], plainText: Bool) -> [NSPasteboardWriting] {
        let merged = PastePlan.merged(plan(items, plainText: plainText))
        return PasteboardIO.pasteboardItems(for: PasteContent.marked(merged.entries, itemID: merged.itemIDs.first,
                                                                     sourceBundleID: env.ownBundleID))
    }

    private func plan(_ items: [ClipItem], plainText: Bool) -> [PasteStep] {
        let store = env.store()
        return PastePlan.steps(for: items, plainText: plainText) { store?.data(for: $0) }
    }

    /// Direct paste types each step into `target` with ⌘V, one after another; otherwise everything goes on the
    /// pasteboard at once and "Copied" shows (behaviour.md §3.1).
    private func deliver(_ steps: [PasteStep], to target: PasteTarget?, directly: Bool, generation: Int) {
        used(steps)
        guard directly else {
            write(PastePlan.merged(steps))
            return env.showHUD("Copied", "checkmark", nil)
        }
        guard env.isAccessibilityTrusted() else {
            write(PastePlan.merged(steps))
            return copiedWithoutAccessibility(into: target)
        }
        guard !env.isSecureInputEnabled() else {
            // A password field (or a terminal with secure entry on) swallows synthetic keystrokes: the content is on
            // the clipboard, and the user pastes it with a real ⌘V.
            Log.paste.info("Secure keyboard entry is on; copied instead of typing ⌘V")
            write(PastePlan.merged(steps))
            return env.showHUD("Copied", "checkmark", Self.pasteHint)
        }
        whenFrontmost(target, generation: generation) { [weak self] in
            self?.run(steps, from: 0, generation: generation)
        } otherwise: { [weak self] in
            guard let self else { return }
            Log.paste.info("The paste target didn't come forward; copied instead")
            write(PastePlan.merged(steps))
            env.showHUD("Copied", "checkmark", Self.pasteHint)
        }
    }

    private func run(_ steps: [PasteStep], from index: Int, generation: Int) {
        guard generation == pasteGeneration, index < steps.count else { return }
        write(steps[index])
        postPaste()
        guard index + 1 < steps.count else { return }
        env.after(Self.stepInterval) { [weak self] in self?.run(steps, from: index + 1, generation: generation) }
    }

    /// Brings `target` forward and runs `work` once it is frontmost, after a short settle so its key window has the
    /// focus back. Without a target, waits for any app other than Super Paste to be in front. `otherwise` runs when
    /// that doesn't happen in time. A newer paste cancels both.
    private func whenFrontmost(_ target: PasteTarget?, generation: Int, then work: @escaping @MainActor () -> Void,
                               otherwise fail: @escaping @MainActor () -> Void) {
        let isReady = { [env] () -> Bool in
            guard let front = env.frontmostApp() else { return target == nil }
            return target.map { $0.processID == front.processID } ?? !self.isOwn(front)
        }
        let settled: @MainActor () -> Void = { [weak self] in
            guard let self, generation == self.pasteGeneration else { return }
            work()
        }
        if isReady() { return env.after(Self.activationSettle, settled) }
        if let target { env.activate(target) }
        var attempts = Int((Self.activationTimeout / Self.activationCheckInterval).rounded())
        func check() {
            guard generation == pasteGeneration else { return }
            if isReady() {
                env.after(Self.activationSettle, settled)
            } else if attempts > 0 {
                attempts -= 1
                env.after(Self.activationCheckInterval, check)
            } else {
                fail()
            }
        }
        check()
    }

    /// Accessibility is missing: the content is on the clipboard; ask whether to enable direct paste, unless the
    /// user said not to ask again.
    private func copiedWithoutAccessibility(into target: PasteTarget?) {
        let copied = { [env] in env.showHUD("Copied", "checkmark", Self.pasteHint) }
        if Defaults[.isDirectPastePromptSuppressed] { return copied() }
        env.askDirectPaste(target?.name) { [env] choice in
            switch choice {
            case .enableAccessibility:
                env.showAccessibilityAccess()
            case .copyToClipboard:
                copied()
            case .copyToClipboardAndDontAskAgain:
                Defaults[.isDirectPastePromptSuppressed] = true
                copied()
            }
        }
    }

    private func write(_ step: PasteStep) {
        let entries = PasteContent.marked(step.entries, itemID: step.itemIDs.first, sourceBundleID: env.ownBundleID)
        monitor.noteOwnWrite(changeCount: PasteboardIO.write(entries, to: env.pasteboard))
    }

    /// Records the paste or copy-out and plays the paste sound.
    private func used(_ steps: [PasteStep]) {
        var seen = Set<UUID>()
        let ids = steps.flatMap(\.itemIDs).filter { seen.insert($0).inserted }
        do { try env.store()?.markUsed(ids, at: env.now()) } catch {
            Log.paste.error("Couldn't record a paste: \(error.localizedDescription, privacy: .public)")
        }
        if Defaults[.isSoundEffectsEnabled] { env.playSound(.paste) }
    }

    /// Posts ⌘V; the Paste Stack's own ⌘V steps aside meanwhile so it doesn't catch it, and comes back a moment
    /// later while the stack still holds snippets.
    private func postPaste() {
        if stackHotkeyRegistered {
            env.unregisterStackHotkey()
            stackHotkeyRegistered = false
        }
        env.postPasteKeystroke()
        guard stackWantsHotkey else { return }
        hotkeyResumeGeneration += 1
        let generation = hotkeyResumeGeneration
        env.after(Self.hotkeyResumeDelay) { [weak self] in
            guard let self, generation == hotkeyResumeGeneration else { return }
            syncStackHotkey()
        }
    }

    // MARK: Paste Stack

    package var pasteStack: PasteStackState { stack.state }
    package var pasteStackChanges: AnyPublisher<PasteStackState, Never> { stackSubject.eraseToAnyPublisher() }

    /// Opens the stack. ⌘V stays the app's own until the first copy lands in it (`syncStackHotkey`).
    package func startPasteStack() {
        guard !stack.state.isActive else { return }
        stack.start(direction: Defaults[.pasteStackDirection])
        syncStackHotkey()
        publishStack()
        Log.paste.info("Paste Stack started")
    }

    package func stopPasteStack() {
        guard stack.state.isActive else { return }
        stack.stop()
        syncStackHotkey()
        publishStack()
        Log.paste.info("Paste Stack ended")
    }

    /// The Paste Stack's ⌘V: the next snippet goes into the frontmost app (the paste target when Super Paste is in
    /// front), whatever the Paste Items setting. Pasting the last snippet ends the stack.
    package func pasteNextFromStack() {
        guard stack.state.isActive else { return }
        guard let item = stack.popNext() else { return env.beep() }
        if stack.state.items.isEmpty {
            stack.stop()
            Log.paste.info("Paste Stack ended: its last snippet was pasted")
        }
        syncStackHotkey()
        publishStack()
        let steps = plan([item], plainText: Defaults[.isPasteAsPlainTextEnabled])
        guard !steps.isEmpty else { return env.beep() }
        let front = env.frontmostApp().flatMap { isOwn($0) ? nil : $0 } ?? lastTarget
        pasteGeneration += 1
        deliver(steps, to: front, directly: true, generation: pasteGeneration)
    }

    package func removeFromPasteStack(_ ids: [UUID]) {
        stack.remove(Set(ids))
        syncStackHotkey()
        publishStack()
    }

    package func setPasteStackDirection(_ direction: StackDirection) {
        Defaults[.pasteStackDirection] = direction
        stack.setDirection(direction)
        publishStack()
    }

    /// ⌘V belongs to the stack only while it is open and holds a snippet; an open, empty stack leaves ⌘V alone, so
    /// pasting keeps working as usual (behaviour.md §3.6 note).
    private var stackWantsHotkey: Bool { stack.state.isActive && !stack.state.items.isEmpty }

    /// Registers or releases the stack's ⌘V to match `stackWantsHotkey`. Every change to the stack ends here, so a
    /// registration can never outlive the snippets it serves.
    private func syncStackHotkey() {
        if stackWantsHotkey, !stackHotkeyRegistered {
            stackHotkeyRegistered = env.registerStackHotkey { [weak self] in self?.pasteNextFromStack() }
            if !stackHotkeyRegistered { Log.paste.error("⌘V is taken by another app; the Paste Stack can't use it") }
        } else if !stackWantsHotkey, stackHotkeyRegistered {
            hotkeyResumeGeneration += 1
            env.unregisterStackHotkey()
            stackHotkeyRegistered = false
        }
    }

    private func captured(_ item: ClipItem) {
        guard stack.state.isActive else { return }
        stack.append(item)
        syncStackHotkey()
        publishStack()
    }

    private func storeChanged(_ change: StoreChange) {
        guard stack.state.isActive, !stack.state.items.isEmpty, let store = env.store() else { return }
        switch change {
        case .deleted(let ids): stack.remove(Set(ids))
        case .updated, .reloaded: stack.refresh { store.item($0) }
        case .inserted, .pinboards: return
        }
        syncStackHotkey()
        publishStack()
    }

    private func publishStack() {
        if stackSubject.value != stack.state { stackSubject.send(stack.state) }
    }
}
