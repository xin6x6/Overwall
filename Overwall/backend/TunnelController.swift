import Foundation
import NetworkExtension
import Observation

@MainActor
@Observable
final class TunnelController {
    private(set) var status: NEVPNStatus = .invalid
    private(set) var isBusy = false
    var lastError: String?

    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    init() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
        Task { await prepare() }
    }

    var isConnected: Bool {
        status == .connected || status == .connecting || status == .reasserting
    }

    func setEnabled(_ enabled: Bool, snapshot: ProxyAppSnapshot) async {
        isBusy = true
        defer { isBusy = false }
        do {
            if enabled {
                let config = try SingBoxConfigBuilder().build(from: snapshot)
                let manager = try await installedManager(configContent: config)
                try manager.connection.startVPNTunnel(options: ["configContent": config as NSString])
            } else {
                manager?.connection.stopVPNTunnel()
            }
            lastError = nil
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
            refreshStatus()
        }
    }

    func reload(snapshot: ProxyAppSnapshot) async {
        guard status == .connected || status == .reasserting else { return }
        do {
            let config = try SingBoxConfigBuilder().build(from: snapshot)
            guard let session = manager?.connection as? NETunnelProviderSession else { return }
            let response = try await send(config: config, through: session)
            if let response, !response.isEmpty {
                throw TunnelReloadError.providerRejected(response)
            }

            if let tunnelProtocol = manager?.protocolConfiguration as? NETunnelProviderProtocol {
                tunnelProtocol.providerConfiguration = ["configContent": config]
                manager?.protocolConfiguration = tunnelProtocol
                try await manager?.saveToPreferences()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func prepare() async {
        do {
            manager = try await NETunnelProviderManager.loadAllFromPreferences().first
            refreshStatus()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func installedManager(configContent: String) async throws -> NETunnelProviderManager {
        let manager = self.manager ?? NETunnelProviderManager()
        let tunnelProtocol = (manager.protocolConfiguration as? NETunnelProviderProtocol)
            ?? NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = AppIdentifiers.packetTunnelBundle
        tunnelProtocol.serverAddress = "Overwall"
        tunnelProtocol.providerConfiguration = ["configContent": configContent]
        manager.protocolConfiguration = tunnelProtocol
        manager.localizedDescription = "Overwall"
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        self.manager = manager
        return manager
    }

    private func refreshStatus() {
        status = manager?.connection.status ?? .invalid
        if status == .disconnected || status == .invalid {
            loadTunnelStartupError()
        }
    }

    private func loadTunnelStartupError() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup
        ) else { return }
        let errorURL = containerURL.appendingPathComponent("last-tunnel-error.txt")
        guard let data = try? Data(contentsOf: errorURL),
              let message = String(data: data, encoding: .utf8),
              !message.isEmpty else { return }
        lastError = message
        try? FileManager.default.removeItem(at: errorURL)
    }

    private func send(config: String, through session: NETunnelProviderSession) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(Data(config.utf8)) { data in
                    continuation.resume(returning: data.flatMap { String(data: $0, encoding: .utf8) })
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum TunnelReloadError: LocalizedError {
    case providerRejected(String)

    var errorDescription: String? {
        switch self {
        case .providerRejected(let message): message
        }
    }
}
