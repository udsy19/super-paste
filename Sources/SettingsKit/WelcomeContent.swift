import AppKit
import SwiftUI
import SuperPasteCore

/// The Welcome pinboard onboarding seeds when Quick Start completes (behaviour.md §8.4, ui-reference §12): four
/// pinned notes (Welcome Aboard, Keep, Organize, Search) and three links, each with its own preview art, so the
/// strip opens on real cards instead of "History is empty". Seeded once; "Getting Started" later only reopens it.
@MainActor
public enum WelcomeContent {
    public static let pinboardName = "Welcome"
    static let pinboardColor = PinboardColor.blue

    public struct Note {
        public var title: String
        public var body: String
    }

    public struct Link {
        public var title: String
        public var name: String
        public var url: String
        var symbol: String
        var colors: [NSColor]
    }

    public static let notes = [
        Note(title: "Welcome Aboard",
             body: "We've pinned a few items here to help you get the most out of Super Paste.\n\nTo open any link, select Open in the context menu or press ⌘O."),
        Note(title: "Keep",
             body: "Access and reuse anything you've copied.\n\nActivate Super Paste with ⇧⌘V, select the items, and press Return to paste them into any app."),
        Note(title: "Organize",
             body: "Pin items to pinboards using the context menu or drag-and-drop.\n\nPinned items are kept when you erase your history, and sync to your other Macs."),
        Note(title: "Search",
             body: "Start typing to search. Filter by content type or the source app.\n\nFor example, search for “mail link meeting slides” to find a link to the slides you copied from Mail."),
    ]

    public static let links = [
        Link(title: "Getting Started", name: "Start using Super Paste", url: "https://udsy19.github.io/super-paste/",
             symbol: "flag.fill", colors: [NSColor(hex: "#FFD66B"), NSColor(hex: "#FF8A5B"), NSColor(hex: "#F06292")]),
        Link(title: "Help and Support", name: "Ask a question or report a problem",
             url: "https://github.com/udsy19/super-paste/issues", symbol: "lifepreserver.fill",
             colors: [NSColor(hex: "#9BE7FF"), NSColor(hex: "#5AA9FF"), NSColor(hex: "#7B6CF6")]),
        Link(title: "Stay Tuned", name: "See what's new in each release",
             url: "https://github.com/udsy19/super-paste/releases", symbol: "sparkles",
             colors: [NSColor(hex: "#C9F2D2"), NSColor(hex: "#5FD68E"), NSColor(hex: "#1FA2A6")]),
    ]

    /// The seeded pinboard while it still exists.
    public static var pinboard: Pinboard? {
        guard let id = UUID(uuidString: Defaults[.welcomePinboardID]) else { return nil }
        return Services.store?.pinboards.first { $0.id == id }
    }

    /// Creates the pinboard and its items once; later calls return the existing pinboard (nil once the user deleted
    /// it, or when the store is unavailable).
    @discardableResult
    public static func seedIfNeeded() -> Pinboard? {
        if let existing = pinboard { return existing }
        guard Defaults[.welcomePinboardID].isEmpty, let store = Services.store else { return nil }
        do {
            let board = try store.createPinboard(name: pinboardName, color: pinboardColor)
            Defaults[.welcomePinboardID] = board.id.uuidString
            for note in notes {
                try store.insert(.text(note.body, title: note.title, copiedAt: nil, pinboardID: board.id))
            }
            for link in links {
                var draft = ClipDraft.text(link.url, title: link.title, copiedAt: nil, pinboardID: board.id)
                let image = try art(for: link).flatMap { try store.saveBlob($0) }
                draft.link = LinkMetadata(url: link.url, title: link.name, image: image, fetchedAt: Date())
                try store.insert(draft)
            }
            return board
        } catch {
            Log.app.error("Couldn't seed the Welcome pinboard: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The link's preview picture (640 × 360 PNG at 2×): its symbol on a stack of glass cards over a gradient.
    public static func art(for link: Link) -> Data? {
        let renderer = ImageRenderer(content: WelcomeArt(symbol: link.symbol, colors: link.colors.map { Color(nsColor: $0) })
            .frame(width: 640, height: 360))
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

/// A gradient with a tilted stack of translucent cards and a symbol on the front one.
struct WelcomeArt: View {
    let symbol: String
    let colors: [Color]

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach([(-9.0, 18.0, 0.55), (7.0, 8.0, 0.75), (0.0, 0.0, 0.95)], id: \.0) { angle, offset, opacity in
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.white.opacity(opacity))
                    .frame(width: 150, height: 150)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .rotationEffect(.degrees(angle))
                    .offset(x: offset, y: offset * 0.6)
            }
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
        }
    }
}
