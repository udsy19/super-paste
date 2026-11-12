import Foundation

/// Copied files in the Mac App Store edition. Reading a file URL from the pasteboard lets a sandboxed app into that
/// file for the rest of the launch, but no longer: after a relaunch the pasteboard silently drops a file URL the app
/// can't reach (it would paste nothing), and Quick Look, Open and Share fail the same way. So each path is kept with a
/// security-scoped bookmark made while access is fresh, and resumed before the path is used again. Access is held for
/// the life of the process: the pasteboard checks it after the write returns.
///
/// In the direct edition (not sandboxed) both calls are plain: nothing is remembered and paths become URLs.
public enum SandboxFileAccess {
    /// The most recent paths kept; older ones are forgotten (pasting them falls back to the path alone).
    public static let limit = 2_000

    /// Called with the paths of a capture, right after the pasteboard was read.
    public static func remember(_ paths: [String]) {
        #if APP_STORE
        guard !paths.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var book = loadedBook()
        for path in paths {
            guard let data = try? URL(fileURLWithPath: path)
                .bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
                Log.app.error("Couldn't bookmark a copied file; it pastes only until Super Paste quits")
                continue
            }
            book.removeAll { $0.path == path }
            book.append(Bookmark(path: path, data: data))
        }
        if book.count > limit { book.removeFirst(book.count - limit) }
        self.book = book
        save(book)
        #endif
    }

    /// URLs for `paths`, with access resumed where a bookmark has it.
    public static func urls(_ paths: [String]) -> [URL] {
        #if APP_STORE
        lock.lock(); defer { lock.unlock() }
        let book = loadedBook()
        for path in paths where !held.contains(path) {
            guard let bookmark = book.last(where: { $0.path == path }) else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark.data, options: .withSecurityScope, relativeTo: nil,
                                     bookmarkDataIsStale: &stale), url.startAccessingSecurityScopedResource() else { continue }
            held.insert(path)
        }
        #endif
        return paths.map { URL(fileURLWithPath: $0) }
    }

    #if APP_STORE
    private struct Bookmark: Codable {
        var path: String
        var data: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var book: [Bookmark]?
    nonisolated(unsafe) private static var held: Set<String> = []
    private static var file: URL { SuperPastePaths.support.appendingPathComponent("File Access.plist") }

    private static func loadedBook() -> [Bookmark] {
        if let book { return book }
        let loaded = (try? Data(contentsOf: file)).flatMap { try? PropertyListDecoder().decode([Bookmark].self, from: $0) } ?? []
        book = loaded
        return loaded
    }

    private static func save(_ book: [Bookmark]) {
        do {
            try PropertyListEncoder().encode(book).write(to: file, options: .atomic)
        } catch {
            Log.app.error("Couldn't save file bookmarks: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}
