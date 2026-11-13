import Combine
import AppKit
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore). The app calls
/// `Services.clipboard.start()` once it has finished launching.
public enum ClipboardKitModule {
    /// Keeps App Nap off: a napped agent app's timers slow to a crawl, and the pasteboard would be read seconds late.
    @MainActor private static var activity: NSObjectProtocol?

    @MainActor public static func install() {
        activity = activity ?? ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                                     reason: "Watching the clipboard")
        let environment = ClipboardEnvironment.live()
        let monitor = ClipboardMonitor(environment: environment)
        let paster = Paster(environment: environment, monitor: monitor)
        paster.trackActivations()
        Services.clipboard = monitor
        Services.pasting = paster
        #if APP_STORE
        pruneFileBookmarks = Services.store?.changes
            .filter { change in
                switch change {
                case .deleted, .reloaded, .pinboards: true
                case .inserted, .updated: false
                }
            }
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { _ in MainActor.assumeIsolated { if let store = Services.store { retainFileBookmarks(in: store) } } }
        #endif
    }

    #if APP_STORE
    @MainActor private static var pruneFileBookmarks: AnyCancellable?

    /// Copied files whose items were deleted, erased, pruned or dropped with their pinboard lose their bookmark.
    @MainActor package static func retainFileBookmarks(in store: ItemStoring) {
        let files = SearchQuery(components: [.filter(.init(.type, "file"))])
        let count = store.count(files, in: .all)
        let paths = store.search(files, in: .all, limit: max(count, 1), offset: 0).flatMap(\.filePaths)
        SandboxFileAccess.retain(only: Set(paths))
    }
    #endif
}
