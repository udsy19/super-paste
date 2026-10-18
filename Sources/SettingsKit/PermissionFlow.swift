import AppKit
import Combine
import SuperPasteCore

/// A permission screen's state (behaviour.md §9): it asks, waits for the grant once System Settings is open, and
/// offers help when the grant hasn't arrived after `issueDelay` (Paste's `isPotentialIssueDetected`: usually a stale
/// entry in the list that is switched on but no longer matches the app).
public struct PermissionFlow: Equatable {
    public enum Phase: Equatable {
        case needed
        case waiting(since: Date)
        case issue
        case granted
    }

    public static let issueDelay: TimeInterval = 20

    public private(set) var phase: Phase

    public init(granted: Bool) { phase = granted ? .granted : .needed }

    public var isGranted: Bool { phase == .granted }
    public var showsIssueHelp: Bool { phase == .issue }

    /// The user went to System Settings.
    public mutating func openedSettings(at now: Date) {
        if phase != .granted { phase = .waiting(since: now) }
    }

    /// A status check: the grant ends the flow; a revoked grant starts over; waiting too long turns into the issue.
    public mutating func poll(granted: Bool, at now: Date) {
        if granted { phase = .granted; return }
        switch phase {
        case .granted: phase = .needed
        case .waiting(let since) where now.timeIntervalSince(since) >= Self.issueDelay: phase = .issue
        case .needed, .waiting, .issue: break
        }
    }
}

/// A permission the screens can check and open System Settings for.
enum PermissionKind {
    case accessibility, pasteboard

    @MainActor var isGranted: Bool {
        switch self {
        case .accessibility: return Permissions.isAccessibilityTrusted
        case .pasteboard:
            // Before macOS 15.4 there is no pasteboard privacy; reading always works.
            guard #available(macOS 15.4, *) else { return true }
            return NSPasteboard.general.accessBehavior == .alwaysAllow
        }
    }

    @MainActor func openSettings() {
        switch self {
        case .accessibility:
            // The system prompt adds Super Paste to the list, so the user only has to switch it on.
            Permissions.requestAccessibility()
            Permissions.open(.accessibility)
        case .pasteboard:
            Permissions.open(.pasteboard)
        }
    }
}

/// Polls a permission twice a second while a screen shows it.
@MainActor
final class PermissionMonitor: ObservableObject {
    let kind: PermissionKind
    @Published private(set) var flow: PermissionFlow
    /// Called when a poll finds the permission newly granted.
    var onGrant: (() -> Void)?
    private var timer: Timer?

    init(_ kind: PermissionKind) {
        self.kind = kind
        flow = PermissionFlow(granted: kind.isGranted)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func check() {
        var next = flow
        next.poll(granted: kind.isGranted, at: Date())
        guard next != flow else { return }
        let newlyGranted = next.isGranted && !flow.isGranted
        flow = next
        if newlyGranted { onGrant?() }
    }

    func openSettings() {
        flow.openedSettings(at: Date())
        kind.openSettings()
    }

    /// For the snapshot renderer.
    func show(_ phase: PermissionFlow.Phase) {
        var flow = PermissionFlow(granted: phase == .granted)
        if phase == .issue {
            flow.openedSettings(at: .distantPast)
            flow.poll(granted: false, at: Date())
        }
        self.flow = flow
    }
}
