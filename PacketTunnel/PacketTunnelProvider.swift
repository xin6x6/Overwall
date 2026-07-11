import Foundation
import Libbox
import NetworkExtension
import os

class ExtensionProvider: NEPacketTunnelProvider {
    struct OverridePreferences {
        var includeAllNetworks = false
        var systemProxyEnabled = true
        var excludeDefaultRoute = false
        var autoRouteUseSubRangesByDefault = false
        var excludeAPNsRoute = false
    }

    private static let logger = Logger(
        subsystem: "com.xin.Overwall.PacketTunnel",
        category: "PacketTunnel"
    )

    var overridePreferences: OverridePreferences?
    private(set) var commandServer: LibboxCommandServer?
    private lazy var platformInterface = ExtensionPlatformInterface(self)
    private var configurationContent = ""

    override init() {
        LibboxPrepareCrashSignalHandlers()
        LibboxReinstallCrashSignalHandlers()
        super.init()
    }

    override func startTunnel(options: [String: NSObject]?) async throws {
        clearLastStartupError()
        do {
            try await startTunnelService(options: options)
        } catch {
            recordStartupError(error)
            Self.logger.error("Tunnel startup failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func startTunnelService(options: [String: NSObject]?) async throws {
        guard let configuration = options?["configContent"] as? String
            ?? (protocolConfiguration as? NETunnelProviderProtocol)?
                .providerConfiguration?["configContent"] as? String,
              !configuration.isEmpty else {
            throw TunnelError.missingConfiguration
        }
        configurationContent = configuration

        let baseURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.xin.Overwall"
        ) ?? FileManager.default.temporaryDirectory
        let workingURL = baseURL.appendingPathComponent("LibboxWorking", isDirectory: true)
        let temporaryURL = baseURL.appendingPathComponent("LibboxTemp", isDirectory: true)
        try FileManager.default.createDirectory(at: workingURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        let setup = LibboxSetupOptions()
        setup.basePath = baseURL.path
        setup.workingPath = workingURL.path
        setup.tempPath = temporaryURL.path
        setup.logMaxLines = 2_000
        setup.oomKillerEnabled = true

        var setupError: NSError?
        LibboxSetup(setup, &setupError)
        if let setupError {
            throw setupError
        }
        LibboxPromoteOOMDraft()

        var configError: NSError?
        guard LibboxCheckConfig(configuration, &configError) else {
            throw configError ?? TunnelError.invalidConfiguration
        }

        var serverError: NSError?
        commandServer = LibboxNewCommandServer(platformInterface, platformInterface, &serverError)
        if let serverError {
            throw serverError
        }
        guard let commandServer else {
            throw TunnelError.cannotCreateCommandServer
        }

        try commandServer.start()
        try startService()
        writeMessage("Overwall packet tunnel started")
    }

    private func startService() throws {
        let options = LibboxOverrideOptions()
        try commandServer?.startOrReloadService(configurationContent, options: options)
    }

    func reloadService() async throws {
        reasserting = true
        defer { reasserting = false }
        try startService()
    }

    func stopService() {
        try? commandServer?.closeService()
        platformInterface.reset()
    }

    func writeMessage(_ message: String) {
        commandServer?.writeMessage(2, message: message)
        Self.logger.info("\(message, privacy: .public)")
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        writeMessage("Stopping tunnel: \(reason.rawValue)")
        stopService()
        commandServer?.close()
        commandServer = nil
    }

    private var startupErrorURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.xin.Overwall"
        )?.appendingPathComponent("last-tunnel-error.txt")
    }

    private func clearLastStartupError() {
        guard let startupErrorURL else { return }
        try? FileManager.default.removeItem(at: startupErrorURL)
    }

    private func recordStartupError(_ error: Error) {
        guard let startupErrorURL else { return }
        let message = "Packet Tunnel failed to start: \(error.localizedDescription)"
        try? Data(message.utf8).write(to: startupErrorURL, options: .atomic)
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        if let request = try? JSONDecoder().decode(TunnelProbeRequest.self, from: messageData),
           request.type == "latencyTest" {
            let response = await TunnelProbeService().run(request)
            return try? JSONEncoder().encode(response)
        }
        guard let configuration = String(data: messageData, encoding: .utf8),
              !configuration.isEmpty else {
            return "Invalid configuration".data(using: .utf8)
        }

        configurationContent = configuration
        do {
            try await reloadService()
            return nil
        } catch {
            return error.localizedDescription.data(using: .utf8)
        }
    }
}

final class PacketTunnelProvider: ExtensionProvider {}

private enum TunnelError: LocalizedError {
    case missingConfiguration
    case cannotCreateCommandServer
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            "The sing-box configuration is missing."
        case .cannotCreateCommandServer:
            "Unable to create the sing-box command server."
        case .invalidConfiguration:
            "The generated sing-box configuration is invalid."
        }
    }
}
