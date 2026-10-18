import AppKit
import Combine
import SwiftUI
import SuperPasteCore

/// The MCP server through `Services.mcp` (behaviour.md §14.3).
@MainActor
final class MCPModel: ObservableObject {
    @Published private(set) var state: MCPServerState
    @Published private(set) var clients: [MCPClientInfo]
    @Published var portText: String
    private let service: MCPServing?
    private var cancellables: Set<AnyCancellable> = []

    init(service: MCPServing?) {
        self.service = service
        state = service?.state ?? .off
        clients = service?.clients ?? []
        portText = String(service?.port ?? Defaults[.mcpPort])
        service?.stateChanges.receive(on: DispatchQueue.main)
            .sink { [weak self] state in MainActor.assumeIsolated { self?.state = state } }
            .store(in: &cancellables)
        service?.clientChanges.receive(on: DispatchQueue.main)
            .sink { [weak self] clients in MainActor.assumeIsolated { self?.clients = clients } }
            .store(in: &cancellables)
    }

    var port: Int { service?.port ?? Defaults[.mcpPort] }
    var isRunning: Bool { if case .running = state { true } else { false } }

    /// The `/mcp` endpoint: the running server's, or the one it will have.
    var serverURL: URL {
        if case .running(let url) = state { return url }
        return MCPConfig.serverURL(port: port)
    }

    func setEnabled(_ enabled: Bool) {
        Defaults[.isMCPEnabled] = enabled
        enabled ? service?.start() : service?.stop()
    }

    func changePort() {
        guard let service else { return }
        guard let port = MCPConfig.newPort(from: portText, current: service.port) else {
            if Int(portText) != service.port { Alerts.error(Strings.Integrations.changeFailed, PortError()) }
            portText = String(service.port)
            return
        }
        guard Alerts.confirm(Strings.Integrations.portWarning, confirmTitle: Strings.Integrations.change) else {
            portText = String(service.port)
            return
        }
        do { try service.changePort(to: port) } catch { Alerts.error(Strings.Integrations.changeFailed, error) }
        portText = String(service.port)
    }

    /// Asks for a name and adds a token client; the token is returned once, for the connection sheet.
    func addClient() -> NewClient? {
        guard let service, let name = Dialogs.ask(Strings.Integrations.addClientTitle,
                                                  message: Strings.Integrations.addClientMessage,
                                                  placeholder: Strings.Integrations.namePlaceholder,
                                                  confirm: Strings.Action.create) else { return nil }
        do {
            let (client, token) = try service.addTokenClient(name: name)
            return NewClient(client: client, token: token)
        } catch {
            Alerts.error(Strings.Integrations.addFailed, error)
            return nil
        }
    }

    func disconnect(_ client: MCPClientInfo) {
        guard Alerts.confirm(Strings.Integrations.disconnectTitle(client.name),
                             info: Strings.Integrations.disconnectText(client.name),
                             confirmTitle: Strings.Integrations.disconnectConfirm, destructive: true) else { return }
        service?.revoke(client.id)
    }

    private struct PortError: LocalizedError {
        var errorDescription: String? { Strings.Integrations.invalidPort }
    }
}

/// A token client just added, with its one-time token.
struct NewClient: Identifiable {
    let client: MCPClientInfo
    let token: String
    var id: UUID { client.id }
}

/// Integrations (replaces Paste's Intelligence pane, behaviour.md §7.4): the MCP server switch and port, the
/// connected clients and the configuration to give a client.
struct IntegrationsPane: View {
    @StateObject private var model = MCPModel(service: Services.mcp)
    @Default(.isMCPEnabled) private var enabled
    @State private var newClient: NewClient?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: Strings.Integrations.section) {
                SettingsRow(title: Strings.Integrations.enable, subtitle: enableSubtitle,
                            subtitleColor: failure == nil ? .secondary : .red) {
                    HStack(spacing: 8) {
                        if model.isRunning {
                            Circle().fill(Color(nsColor: .systemGreen)).frame(width: 6, height: 6)
                        }
                        Toggle(Strings.Integrations.enable, isOn: Binding(get: { enabled }, set: { model.setEnabled($0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                }
                Divider()
                SettingsRow(title: Strings.Integrations.port, subtitle: Strings.Integrations.portWarning) {
                    HStack(spacing: 8) {
                        TextField(Strings.Integrations.port, text: $model.portText)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 64)
                            .onSubmit { model.changePort() }
                        Button(Strings.Integrations.change) { model.changePort() }
                            .disabled(MCPConfig.newPort(from: model.portText, current: model.port) == nil)
                    }
                }
            }
            SettingsGroup(title: Strings.Integrations.clients) {
                if model.clients.isEmpty {
                    Text(Strings.Integrations.empty).font(.sp(.callout)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(model.clients.enumerated()), id: \.element.id) { index, client in
                        if index > 0 { Divider() }
                        ClientRow(client: client) { model.disconnect(client) }
                    }
                }
                Divider()
                HStack {
                    Spacer()
                    Button(Strings.Integrations.addClient) { newClient = model.addClient() }
                }
            }
            SettingsGroup(title: Strings.Integrations.config, subtitle: Strings.Integrations.configInfo) {
                CodeBlock(text: MCPConfig.httpSnippet(url: model.serverURL), secret: false)
            }
        }
        .sheet(item: $newClient) { new in
            ConnectSheet(new: new, url: model.serverURL) { newClient = nil }
        }
    }

    private var failure: String? { if case .failed(let message) = model.state { message } else { nil } }
    private var enableSubtitle: String { failure ?? Strings.Integrations.enableInfo }
}

private struct ClientRow: View {
    let client: MCPClientInfo
    let disconnect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "puzzlepiece.extension").font(.system(size: 13)).frame(width: 16, height: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(client.name).font(.sp(.body)).lineLimit(1)
                Text(Strings.Integrations.clientDetail(
                    connection: client.connection == .oauth ? Strings.Integrations.signedIn : Strings.Integrations.tokenClient,
                    lastUsed: client.lastUsedAt.map {
                    Strings.Integrations.lastUsed(relativeDate($0))
                } ?? Strings.Integrations.neverUsed))
                    .font(.sp(.callout)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(Strings.Integrations.disconnect, action: disconnect)
        }
    }
}

/// Monospaced text with a Copy button.
struct CodeBlock: View {
    let text: String
    /// Copies with the concealed marker, so clipboard managers skip it.
    let secret: Bool
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            Button(copied ? Strings.Action.copied : Strings.Action.copy) {
                Dialogs.copy(text, secret: secret)
                copied = true
            }
            .controlSize(.small)
            .padding(6)
        }
    }
}

/// "Connect %@" for a token client: the server URL, the token and the stdio bridge configuration (behaviour.md
/// §14.4, custom kind).
struct ConnectSheet: View {
    let new: NewClient
    let url: URL
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Strings.Integrations.connectTitle(new.client.name)).font(.sp(.title3, .semibold))
            Text(Strings.Integrations.tokenInstruction).font(.sp(.callout)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            field(Strings.Integrations.serverURL, url.absoluteString, secret: false)
            field(Strings.Integrations.token, new.token, secret: true)
            Text(Strings.Integrations.stdioInstruction).font(.sp(.callout)).foregroundStyle(.secondary)
            CodeBlock(text: MCPConfig.stdioSnippet(url: url, token: new.token), secret: true)
            HStack {
                Spacer()
                Button(Strings.Action.done, action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private func field(_ label: String, _ value: String, secret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.sp(.callout, .medium))
            HStack(spacing: 8) {
                Text(value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
                Button(Strings.Action.copy) { Dialogs.copy(value, secret: secret) }
            }
        }
    }
}
