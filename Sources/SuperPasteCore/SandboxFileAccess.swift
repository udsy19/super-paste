import Foundation

/// Copied files in the Mac App Store edition. Reading a file URL from the pasteboard lets a sandboxed app into that
/// file for the rest of the launch, but no longer: after a relaunch the pasteboard silently drops a file URL the app
/// can't reach (it would paste nothing), and Quick Look, Open and Share fail the same way. So each path is kept with a
/// security-scoped bookmark made while access is fresh, and resumed before the path is used again.
///
/// Access is held after use (the pasteboard checks it after the write returns) for the `heldLimit` most recently used
/// paths; the least recently used one beyond that is released. Bookmarks are forgotten when their items are deleted,
/// erased or pruned (`retain(only:)`), and written to disk off the main thread, debounced.
///
/// In the direct edition (not sandboxed) every call is plain: nothing is remembered and paths become URLs.
public enum SandboxFileAccess {
    /// The most recent paths kept; older ones are forgotten (pasting them falls back to the path alone).
    public static let limit = 2_000
    /// Paths whose access is held at once.
    public static let heldLimit = 64

    /// Called with the paths of a capture, right after the pasteboard was read.
    public static func remember(_ paths: [String]) {
        #if APP_STORE
        guard !paths.isEmpty else { return }
        let made = paths.compactMap { path -> Bookmark? in
            guard let data = try? URL(fileURLWithPath: path)
                .bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
                Log.app.error("Couldn't bookmark a copied file; it pastes only until Super Paste quits")
                return nil
            }
            return Bookmark(path: path, data: data)
        }
        guard !made.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var book = loadedBook()
        let paths = Set(made.map(\.path))
        book.removeAll { paths.contains($0.path) }
        book += made
        if book.count > limit { book.removeFirst(book.count - limit) }
        self.book = book
        scheduleSave()
        #endif
    }

    /// URLs for `paths`, with access resumed where a bookmark has it.
    public static func urls(_ paths: [String]) -> [URL] {
        #if APP_STORE
        lock.lock(); defer { lock.unlock() }
        let book = loadedBook()
        for path in paths {
            if let index = held.firstIndex(where: { $0.path == path }) {
                held.append(held.remove(at: index))  // most recently used last
                continue
            }
            guard let bookmark = book.last(where: { $0.path == path }) else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark.data, options: .withSecurityScope, relativeTo: nil,
                                     bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() else { continue }
            held.append((path, url))
            while held.count > heldLimit { held.removeFirst().url.stopAccessingSecurityScopedResource() }
        }
        #endif
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Forgets the bookmarks (and releases the access) of every path not in `paths`: the files of items that still
    /// exist. Called after deletes, Erase History and pruning.
    public static func retain(only paths: Set<String>) {
        #if APP_STORE
        lock.lock(); defer { lock.unlock() }
        let book = loadedBook()
        let kept = book.filter { paths.contains($0.path) }
        held.removeAll { entry in
            guard !paths.contains(entry.path) else { return false }
            entry.url.stopAccessingSecurityScopedResource()
            return true
        }
        guard kept.count != book.count else { return }
        self.book = kept
        scheduleSave()
        #endif
    }

    #if APP_STORE
    /// Paths with a bookmark, oldest first, and the paths whose access is held (least recently used first).
    public static var rememberedPaths: [String] { lock.withLock { loadedBook().map(\.path) } }
    public static var heldPaths: [String] { lock.withLock { held.map(\.path) } }

    /// Writes the book now (self-test; quitting needs nothing, a pending write is at most half a second old).
    public static func flush() {
        let snapshot: [Bookmark] = lock.withLock { book ?? [] }
        try? PropertyListEncoder().encode(snapshot).write(to: file, options: .atomic)
    }

    /// Forgets everything in memory and releases all access, as at a relaunch (self-test).
    public static func resetForTesting() {
        lock.withLock {
            held.forEach { $0.url.stopAccessingSecurityScopedResource() }
            held = []
            book = nil
        }
    }

    private struct Bookmark: Codable {
        var path: String
        var data: Data
    }

    private static let lock = NSLock()
    private static let saveQueue = DispatchQueue(label: "SandboxFileAccess.save", qos: .utility)
    nonisolated(unsafe) private static var book: [Bookmark]?
    nonisolated(unsafe) private static var held: [(path: String, url: URL)] = []
    nonisolated(unsafe) private static var savePending = false
    private static var file: URL { SuperPastePaths.support.appendingPathComponent("File Access.plist") }

    private static func loadedBook() -> [Bookmark] {
        if let book { return book }
        let loaded = (try? Data(contentsOf: file)).flatMap { try? PropertyListDecoder().decode([Bookmark].self, from: $0) } ?? []
        book = loaded
        return loaded
    }

    /// Writes the book on a background queue, at most once per half second (called with the lock held).
    private static func scheduleSave() {
        guard !savePending else { return }
        savePending = true
        let file = self.file
        saveQueue.asyncAfter(deadline: .now() + 0.5) {
            let snapshot: [Bookmark] = lock.withLock { savePending = false; return book ?? [] }
            do {
                try PropertyListEncoder().encode(snapshot).write(to: file, options: .atomic)
            } catch {
                Log.app.error("Couldn't save file bookmarks: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    #endif
}
