import AppKit
import AudioToolbox
import Carbon.HIToolbox
import LinkPresentation
import QuickLookThumbnailing
import UniformTypeIdentifiers
import SuperPasteCore

// The real macOS side of `ClipboardEnvironment`: the general pasteboard, key events, app activation, sounds,
// LinkPresentation and Quick Look.

extension ClipboardEnvironment {
    /// The environment the app runs with.
    static func live() -> ClipboardEnvironment {
        let pasteboard = NSPasteboard.general
        let records = AppRecords(store: { Services.store })
        let hotkey = StackHotkey()
        return ClipboardEnvironment(
            pasteboard: pasteboard,
            ownBundleID: SuperPastePaths.bundleID,
            store: { Services.store },
            frontmostApp: { NSWorkspace.shared.frontmostApplication.map(PasteTarget.init) },
            appRecord: records.record(for:),
            now: Date.init,
            after: { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
            },
            playSound: SystemSounds.play,
            showHUD: { title, symbol, subtitle in HUD.show(title, symbol: symbol, subtitle: subtitle) },
            beep: { NSSound.beep() },
            needsPasteboardAccess: {
                guard #available(macOS 26, *) else { return false }
                return [.ask, .alwaysDeny].contains(pasteboard.accessBehavior)
            },
            showPasteboardAccess: { Services.permissions?.showPasteboardAccess() },
            fetchLinkPreview: LinkPreviewFetcher.fetch,
            fileThumbnail: FileThumbnails.make,
            reportSaveFailure: { message in Alerts.notice(SaveFailure.title, message) },
            isAccessibilityTrusted: { Permissions.isAccessibilityTrusted },
            isSecureInputEnabled: { IsSecureEventInputEnabled() },
            activate: Keystrokes.activate,
            postPasteKeystroke: Keystrokes.postCommandV,
            hideStrip: { completion in
                if let strip = Services.strip { strip.hide(then: completion) } else { completion() }
            },
            askDirectPaste: { name, completion in
                guard let permissions = Services.permissions else { return completion(.copyToClipboard) }
                permissions.requestDirectPaste(into: name, completion: completion)
            },
            showAccessibilityAccess: { Services.permissions?.showAccessibilityAccess() },
            registerStackHotkey: hotkey.register,
            unregisterStackHotkey: hotkey.unregister)
    }
}

extension PasteTarget {
    init(_ app: NSRunningApplication) {
        self.init(bundleID: app.bundleIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "", processID: app.processIdentifier)
    }
}

/// The capture and paste sounds: short macOS system sounds, nothing bundled.
@MainActor
enum SystemSounds {
    private static let files: [SoundEffect: String] = [
        .copy: "/System/Library/Sounds/Pop.aiff",
        .paste: "/System/Library/Sounds/Tink.aiff",
    ]
    private static var ids: [SoundEffect: SystemSoundID] = [:]

    static func play(_ effect: SoundEffect) {
        if ids[effect] == nil, let path = files[effect] {
            var id: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(URL(fileURLWithPath: path) as CFURL, &id) == noErr { ids[effect] = id }
        }
        if let id = ids[effect] { AudioServicesPlaySystemSound(id) }
    }
}

/// Activating the paste target and typing ⌘V into it (needs Accessibility).
@MainActor
enum Keystrokes {
    /// The key that types "v" on the current layout (the ANSI V key when none does).
    static var vKeyCode: CGKeyCode {
        CGKeyCode(Shortcut(keyEquivalent: "v", modifiers: .command)?.keyCode ?? UInt32(kVK_ANSI_V))
    }

    static func activate(_ target: PasteTarget) {
        guard let app = NSRunningApplication(processIdentifier: target.processID), !app.isTerminated, !app.isActive else { return }
        NSApp.yieldActivation(to: app)
        if !app.activate(from: .current, options: []) { app.activate() }
    }

    /// Types ⌘V: a key down and up for the V key of the current layout, carrying only the Command flag (whatever
    /// the user still holds, such as ⇧ from a plain-text paste), posted at the HID tap so it reaches the frontmost
    /// app the way a real keystroke does. The strip must be off screen first (`Pasting.paste` waits for that), or
    /// the keystroke lands in the strip, which is the key window while it shows.
    static func postCommandV() {
        let key = vKeyCode
        let source = CGEventSource(stateID: .combinedSessionState)
        // Keys the user is still holding don't leak into the synthetic ⌘V.
        source?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                           state: .eventSuppressionStateSuppressionInterval)
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | UInt64(NX_DEVICELCMDKEYMASK))
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// The Paste Stack's temporary global ⌘V (behaviour.md §3.6), through `HotkeyCenter`.
@MainActor
final class StackHotkey {
    private var token: UInt32?

    func register(_ handler: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        let shortcut = Shortcut(keyCode: UInt32(Keystrokes.vKeyCode), modifiers: .command)
        token = HotkeyCenter.shared.register(shortcut) { MainActor.assumeIsolated { handler() } }
        return token != nil
    }

    func unregister() {
        if let token { HotkeyCenter.shared.unregister(token) }
        token = nil
    }
}

/// LinkPresentation fetches (behaviour.md §2.8).
enum LinkPreviewFetcher {
    static let timeout: TimeInterval = 15
    /// Favicon side in pixels (the 42 pt favicon at 3×).
    static let iconPixels = 128
    /// Longest side of the preview image in pixels (a large card at 2×).
    static let imagePixels = 720

    /// Providers are single-use; each is kept until its fetch has answered.
    @MainActor private static var inFlight: [UUID: LPMetadataProvider] = [:]

    @MainActor static func fetch(_ url: URL, completion: @escaping @MainActor (LinkPreview?) -> Void) {
        let provider = LPMetadataProvider()
        provider.timeout = timeout
        let key = UUID()
        inFlight[key] = provider
        let finish: @Sendable (LinkPreview?) -> Void = { preview in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    inFlight[key] = nil
                    completion(preview)
                }
            }
        }
        provider.startFetchingMetadata(for: url) { metadata, error in
            guard let metadata, error == nil else { return finish(nil) }
            let title = metadata.title
            let imageProvider = metadata.imageProvider
            load(metadata.iconProvider, maxPixels: iconPixels, png: true) { icon in
                load(imageProvider, maxPixels: imagePixels, png: false) { image in
                    finish(LinkPreview(title: title, icon: icon, image: image))
                }
            }
        }
    }

    private static func load(_ provider: NSItemProvider?, maxPixels: Int, png: Bool, then: @escaping (Data?) -> Void) {
        guard let provider, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return then(nil) }
        _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            then(data.flatMap { ImageEncoding.downscaled($0, maxPixels: maxPixels, png: png) })
        }
    }
}

/// Quick Look thumbnails of copied files (`isFileItemQLThumbnailImageEnabled`).
enum FileThumbnails {
    /// The thumbnail source size (ui-reference §4.5: 256 × 256).
    static let side: CGFloat = 256

    @MainActor static func make(_ url: URL, completion: @escaping @MainActor (Data?) -> Void) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: 1,
                                                   representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let png = representation.flatMap { ImageEncoding.png($0.cgImage) }
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(png) } }
        }
    }
}
