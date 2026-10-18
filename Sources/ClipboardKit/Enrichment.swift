import Foundation
import SuperPasteCore

/// What capture adds to an item after the store saved it: link previews (behaviour.md §2.8, behind Generate Link
/// Previews) and Quick Look thumbnails of copied files (`isFileItemQLThumbnailImageEnabled`).
@MainActor
final class CaptureEnricher {
    /// Link previews kept for this session, so a link copied again isn't fetched again.
    static let cacheLimit = 64

    private let env: ClipboardEnvironment
    private var previews: [String: (preview: LinkPreview, fetchedAt: Date)] = [:]
    private var previewOrder: [String] = []
    /// Items waiting for a fetch in flight, by URL.
    private var waiting: [String: [UUID]] = [:]

    init(environment: ClipboardEnvironment) {
        env = environment
    }

    func enrich(_ item: ClipItem) {
        if item.kind == .link, let link = item.link, link.fetchedAt == nil, Defaults[.isLinkPreviewsEnabled] {
            preview(link.url, for: item.id)
        }
        if item.kind == .files, item.thumbnail == nil, Defaults[.isFileItemQLThumbnailImageEnabled],
           let path = item.filePaths.first {
            let id = item.id
            env.fileThumbnail(URL(fileURLWithPath: path)) { [weak self] png in
                guard let png else { return }
                self?.update(id) { store, item in
                    guard item.thumbnail == nil else { return false }
                    item.thumbnail = try store.saveBlob(png)
                    return true
                }
            }
        }
    }

    private func preview(_ url: String, for id: UUID) {
        if let cached = previews[url] { return apply(cached.preview, fetchedAt: cached.fetchedAt, url: url, to: id) }
        if waiting[url] != nil { waiting[url]?.append(id); return }
        guard let target = URL(string: url) else { return }
        waiting[url] = [id]
        env.fetchLinkPreview(target) { [weak self] preview in
            guard let self else { return }
            let ids = waiting.removeValue(forKey: url) ?? []
            guard let preview else {
                Log.clipboard.info("No link preview for a copied link")
                return
            }
            let fetchedAt = env.now()
            remember(preview, fetchedAt: fetchedAt, url: url)
            for id in ids { apply(preview, fetchedAt: fetchedAt, url: url, to: id) }
        }
    }

    private func remember(_ preview: LinkPreview, fetchedAt: Date, url: String) {
        previews[url] = (preview, fetchedAt)
        previewOrder.removeAll { $0 == url }
        previewOrder.append(url)
        while previewOrder.count > Self.cacheLimit { previews[previewOrder.removeFirst()] = nil }
    }

    /// Fills the item's link metadata; a title the pasteboard gave (`public.url-name`) is kept.
    private func apply(_ preview: LinkPreview, fetchedAt: Date, url: String, to id: UUID) {
        update(id) { store, item in
            guard item.kind == .link, var link = item.link, link.url == url else { return false }
            link.title = link.title ?? preview.title
            link.icon = try preview.icon.map { try store.saveBlob($0) }
            link.image = try preview.image.map { try store.saveBlob($0) }
            link.fetchedAt = fetchedAt
            item.link = link
            return true
        }
    }

    /// Changes the stored item; `change` returns false to leave it as it is.
    private func update(_ id: UUID, _ change: (ItemStoring, inout ClipItem) throws -> Bool) {
        guard let store = env.store(), var item = store.item(id) else { return }
        do {
            if try change(store, &item) { try store.update(item) }
        } catch {
            Log.clipboard.error("Couldn't save capture details: \(error.localizedDescription, privacy: .public)")
        }
    }
}
