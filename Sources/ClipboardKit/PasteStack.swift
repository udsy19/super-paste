import Foundation
import SuperPasteCore

/// The Paste Stack's state machine (behaviour.md §3.6), free of pasteboards and hot keys: while active every capture
/// is appended; the next snippet comes from the top (first copied) or the bottom (last copied).
package struct PasteStackEngine: Sendable {
    package private(set) var state = PasteStackState()

    package init() {}

    /// Opens an empty stack. No-op while one is open.
    package mutating func start(direction: StackDirection) {
        guard !state.isActive else { return }
        state = PasteStackState(isActive: true, items: [], direction: direction)
    }

    /// Closes and empties the stack.
    package mutating func stop() {
        state = PasteStackState(isActive: false, items: [], direction: state.direction)
    }

    /// Appends a copy while the stack is open. An item already in the stack (copied again) moves to the end.
    package mutating func append(_ item: ClipItem) {
        guard state.isActive else { return }
        state.items.removeAll { $0.id == item.id }
        state.items.append(item)
    }

    /// Takes the next snippet off the stack, per direction; nil when it is closed or empty.
    package mutating func popNext() -> ClipItem? {
        guard state.isActive, !state.items.isEmpty else { return nil }
        return state.direction == .top ? state.items.removeFirst() : state.items.removeLast()
    }

    package mutating func remove(_ ids: Set<UUID>) {
        state.items.removeAll { ids.contains($0.id) }
    }

    /// Keeps the snippets the store still has, refreshed to their current content.
    package mutating func refresh(_ lookup: (UUID) -> ClipItem?) {
        state.items = state.items.compactMap { lookup($0.id) }
    }

    package mutating func setDirection(_ direction: StackDirection) {
        state.direction = direction
    }
}
