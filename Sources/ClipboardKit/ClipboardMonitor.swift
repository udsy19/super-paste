import AppKit
import Combine
import SuperPasteCore

extension Defaults.Keys {
    /// The last pasteboard change count the monitor processed (behaviour.md §2.1); -1 before the first launch.
    package static let clipboardKitChangeToken = Key<Int>("clipboardKit.changeToken", default: -1)
}

/// Watches the pasteboard and saves every copy to the store (behaviour.md §2.1–§2.7, §2.10).
@MainActor
package final class ClipboardMonitor: ClipboardMonitoring {
    package static let pollInterval: TimeInterval = 0.25
    package static let pollTolerance: TimeInterval = 0.025
    /// A change is read only after the pasteboard has been still this long (multi-type writes arrive in pieces).
    package static let settleDelay: TimeInterval = 0.3
    /// How many of Super Paste's own recent writes are remembered (sequential pastes write several times quickly).
    static let ownWriteMemory = 16

    private let env: ClipboardEnvironment
    private let enricher: CaptureEnricher
    private var pollTimer: Timer?
    private var lastChangeCount: Int?
    private var settleGeneration = 0
    private var ownWrites: [Int] = []
    private var askedForPasteboardAccess = false
    private let pauseSubject = CurrentValueSubject<PauseState, Never>(.running)
    private let captureSubject = PassthroughSubject<ClipItem, Never>()

    package init(environment: ClipboardEnvironment) {
        env = environment
        enricher = CaptureEnricher(environment: environment)
    }

    // MARK: ClipboardMonitoring

    /// Starts polling. What is on the pasteboard now is captured only when it changed since the last change this
    /// Mac's Super Paste processed (a copy made while it wasn't running); never on the very first launch.
    package func start() {
        guard pollTimer == nil else { return }
        let count = env.pasteboard.changeCount
        let token = Defaults[.clipboardKitChangeToken]
        lastChangeCount = count
        checkPasteboardAccess()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = Self.pollTolerance
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        Log.clipboard.info("Start monitoring pasteboard")
        if token >= 0, token != count {
            sync()
        } else {
            Defaults[.clipboardKitChangeToken] = count
        }
    }

    package var pauseState: PauseState { pauseSubject.value }
    package var pauseChanges: AnyPublisher<PauseState, Never> { pauseSubject.eraseToAnyPublisher() }

    package func pause(until date: Date?) {
        if let date, date <= env.now() { return resume() }
        pauseSubject.send(.paused(until: date))
        Log.clipboard.info("Paused")
        env.showHUD("Super Paste Paused", "pause", nil)
    }

    package func resume() {
        guard isPaused else { return }
        pauseSubject.send(.running)
        Log.clipboard.info("Resumed")
        env.showHUD("Super Paste Resumed", "arrow.clockwise", nil)
    }

    package var captures: AnyPublisher<ClipItem, Never> { captureSubject.eraseToAnyPublisher() }

    // MARK: Polling

    /// One poll: ends an expired pause, and on a new change count waits `settleDelay` (restarting on every further
    /// change) before reading.
    package func poll() {
        if case .paused(let until?) = pauseState, until <= env.now() { resume() }
        let count = env.pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        settleGeneration += 1
        let generation = settleGeneration
        env.after(Self.settleDelay) { [weak self] in
            guard let self, generation == settleGeneration else { return }
            sync()
        }
    }

    /// Stops polling (the self-test's monitors).
    package func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        settleGeneration += 1
    }

    /// Tells the monitor that Super Paste itself wrote the pasteboard, leaving it at `changeCount`: a restore, not a copy.
    package func noteOwnWrite(changeCount: Int) {
        ownWrites.append(changeCount)
        if ownWrites.count > Self.ownWriteMemory { ownWrites.removeFirst(ownWrites.count - Self.ownWriteMemory) }
    }

    /// Reads the pasteboard now and captures it unless a filter says otherwise (behaviour.md §2.2, §2.3).
    package func sync() {
        let pasteboard = env.pasteboard
        let count = pasteboard.changeCount
        lastChangeCount = count
        Defaults[.clipboardKitChangeToken] = count
        if ownWrites.contains(count) { return Log.clipboard.debug("Restored an item") }
        // While paused nothing is read at all.
        guard !isPaused else { return Log.clipboard.info("Paused, skipping pasteboard change") }
        checkPasteboardAccess()

        let types = PasteboardIO.types(on: pasteboard)
        let all = Set(types.joined())
        let itemIDMarker = all.contains(PasteboardType.itemID) ? PasteboardIO.marker(PasteboardType.itemID, on: pasteboard) : nil
        let sourceMarker = all.contains(PasteboardType.source) ? PasteboardIO.marker(PasteboardType.source, on: pasteboard) : nil
        let frontmost = env.frontmostApp()
        let decision = CaptureFilter.evaluate(types: types, itemIDMarker: itemIDMarker, sourceMarker: sourceMarker,
                                              frontmost: frontmost, ownBundleID: env.ownBundleID,
                                              ignoredApps: Defaults[.ignoredBundleIdentifiers],
                                              ignoredTypes: Defaults[.ignoredPasteboardTypes])
        let source: CaptureSource
        switch decision {
        case .capture(let resolved):
            source = resolved
        case .ownWrite(let itemID?) where env.store()?.item(itemID) == nil:
            // Written by Super Paste for an item this Mac doesn't have (deleted, or another Mac's): a new copy.
            guard let resolved = CaptureSource.resolve(marker: nil, frontmost: frontmost) else { return }
            source = resolved
        case .ownWrite:
            return Log.clipboard.debug("Restored an item")
        case .noItems:
            return Log.clipboard.info("No items in system pasteboard")
        case .noSource:
            return Log.clipboard.info("Undefined frontmost application, skipping pasteboard change")
        case .ignoredApp(let bundleID):
            return Log.clipboard.info("Ignored application \(bundleID, privacy: .public), skipping pasteboard change")
        case .ignoredType(let type):
            return Log.clipboard.info("Ignored pasteboard type \(type, privacy: .public), skipping pasteboard change")
        }

        let dropped = QuirkRule.droppedTypes(for: source.bundleID)
        let entries = CapturePayload.clean(PasteboardIO.read(from: pasteboard, skipping: dropped), dropping: dropped)
        guard !entries.isEmpty else { return Log.clipboard.info("Empty pasteboard content") }
        capture(entries, from: source, remote: CapturePayload.isRemote(types: types))
    }

    private func capture(_ entries: [EntryData], from source: CaptureSource, remote: Bool) {
        guard let store = env.store() else { return }
        let analysis = Classifier.analyze(entries, bundleID: source.bundleID)
        // Universal Clipboard content was copied on another device, which this Mac can't name.
        let draft = ClipDraft(entries: analysis.entries, kind: analysis.kind, text: analysis.text,
                              sourceApp: env.appRecord(source), device: remote ? nil : .current, copiedAt: env.now(),
                              imageSize: analysis.imageSize, thumbnail: analysis.thumbnail,
                              filePaths: analysis.filePaths, link: analysis.link)
        do {
            let result = try store.insert(draft)
            Log.clipboard.info("Captured a \(analysis.kind.rawValue, privacy: .public) item\(result.isNew ? "" : " (existing)", privacy: .public)")
            if Defaults[.isSoundEffectsEnabled] { env.playSound(.copy) }
            captureSubject.send(result.item)
            enricher.enrich(result.item)
        } catch {
            Log.clipboard.error("Couldn't save a capture: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// macOS 26 pasteboard privacy: asks once per launch for access when reads would prompt or fail.
    private func checkPasteboardAccess() {
        guard !askedForPasteboardAccess, env.needsPasteboardAccess() else { return }
        askedForPasteboardAccess = true
        Log.clipboard.info("Pasteboard access is limited; asking for access")
        env.showPasteboardAccess()
    }
}
