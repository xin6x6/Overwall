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

    func latencyTest(method: String, servers: [StoredProxyServer], snapshot: ProxyAppSnapshot) async throws -> [UUID: Int] {
        if status != .connected {
            await setEnabled(true, snapshot: snapshot)
            try await waitUntilConnected()
        }
        guard let session = manager?.connection as? NETunnelProviderSession else {
            throw TunnelProbeError.sessionUnavailable
        }
        let request = TunnelProbeRequest(
            type: "latencyTest",
            method: method,
            probes: servers.map {
                TunnelProbeItem(
                    id: $0.id,
                    address: $0.address,
                    port: $0.port,
                    outboundTag: SingBoxConfigBuilder.outboundTag(for: $0.id)
                )
            }
        )
        let data = try JSONEncoder().encode(request)
        let responseData = try await send(data: data, through: session)
        guard let responseData else { throw TunnelProbeError.emptyResponse }
        let response = try JSONDecoder().decode(TunnelProbeResponse.self, from: responseData)
        if let error = response.error { throw TunnelProbeError.providerRejected(error) }
        return Dictionary(uniqueKeysWithValues: response.results.compactMap { item in
            item.latency.map { (item.id, $0) }
        })
    }

    func trafficTotals() async throws -> TunnelTrafficTotals? {
        guard status == .connected || status == .reasserting,
              let session = manager?.connection as? NETunnelProviderSession else { return nil }
        let request = try JSONSerialization.data(withJSONObject: ["type": "trafficStats"])
        guard let data = try await send(data: request, through: session) else { return nil }
        let response = try JSONDecoder().decode(TunnelTrafficResponse.self, from: data)
        if let error = response.error { throw TunnelProbeError.providerRejected(error) }
        return TunnelTrafficTotals(
            upload: response.uploadTotal,
            download: response.downloadTotal,
            directUpload: response.directUploadTotal,
            directDownload: response.directDownloadTotal,
            proxyUpload: response.proxyUploadTotal,
            proxyDownload: response.proxyDownloadTotal,
            connectedAt: response.connectedAt
        )
    }

    private func waitUntilConnected() async throws {
        for _ in 0..<100 {
            refreshStatus()
            if status == .connected { return }
            if status == .invalid || status == .disconnected, lastError != nil {
                throw TunnelProbeError.providerRejected(lastError ?? "VPN failed to connect.")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw TunnelProbeError.connectionTimedOut
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
        let response = try await send(data: Data(config.utf8), through: session)
        return response.flatMap { String(data: $0, encoding: .utf8) }
    }

    private func send(data: Data, through session: NETunnelProviderSession) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(data) { response in
                    continuation.resume(returning: response)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private struct TunnelProbeRequest: Codable {
    let type: String
    let method: String
    let probes: [TunnelProbeItem]
}

private struct TunnelProbeItem: Codable {
    let id: UUID
    let address: String
    let port: Int
    let outboundTag: String
}

private struct TunnelProbeResponse: Codable {
    let results: [TunnelProbeResult]
    let error: String?
}

struct TunnelTrafficTotals: Equatable {
    let upload: Int64
    let download: Int64
    let directUpload: Int64
    let directDownload: Int64
    let proxyUpload: Int64
    let proxyDownload: Int64
    let connectedAt: Date?
}

private struct TunnelTrafficResponse: Codable {
    let uploadTotal: Int64
    let downloadTotal: Int64
    let directUploadTotal: Int64
    let directDownloadTotal: Int64
    let proxyUploadTotal: Int64
    let proxyDownloadTotal: Int64
    let connectedAt: Date?
    let error: String?
}

private struct TunnelProbeResult: Codable {
    let id: UUID
    let latency: Int?
}

private enum TunnelProbeError: LocalizedError {
    case sessionUnavailable
    case connectionTimedOut
    case emptyResponse
    case providerRejected(String)

    var errorDescription: String? {
        switch self {
        case .sessionUnavailable: "The VPN tunnel session is unavailable."
        case .connectionTimedOut: "The VPN did not finish connecting before the test timed out."
        case .emptyResponse: "The packet tunnel returned no connectivity-test result."
        case .providerRejected(let message): message
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
