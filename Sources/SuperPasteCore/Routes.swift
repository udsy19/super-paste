import Foundation

/// A `superpaste://` URL (behaviour.md §15):
///
///     superpaste://                      show the strip as it was
///     superpaste://new-text-item
///     superpaste://search?q=<query>
///     superpaste://list/<history|pinboard id>
///     superpaste://preview-item/<item id>
///     superpaste://edit-item/<item id>
///     superpaste://settings[/<pane>]
public enum AppRoute: Hashable, Sendable {
    case strip(StripRoute?)
    case settings(SettingsPane?)

    public static let scheme = "superpaste"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (components.host ?? "").lowercased()
        let argument = components.path.split(separator: "/").first.map(String.init)
        switch host {
        case "":
            self = .strip(nil)
        case "new-text-item":
            self = .strip(.newTextItem)
        case "search":
            let query = components.queryItems?.first { $0.name == "q" }?.value ?? ""
            self = .strip(.search(query))
        case "list":
            guard let argument, let scope = ListScope(id: argument) else { return nil }
            self = .strip(.list(scope))
        case "preview-item", "edit-item":
            guard let argument, let id = UUID(uuidString: argument) else { return nil }
            self = .strip(host == "edit-item" ? .edit(id) : .preview(id))
        case "settings", "preferences":
            guard let argument else { self = .settings(nil); return }
            guard let pane = SettingsPane(rawValue: argument.lowercased()) else { return nil }
            self = .settings(pane)
        default:
            return nil
        }
    }
}
