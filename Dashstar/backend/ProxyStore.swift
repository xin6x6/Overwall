import Foundation
import Observation

@MainActor
@Observable
final class ProxyStore {
    private(set) var snapshot: ProxyAppSnapshot
    var lastError: String?

    private let persistenceURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let fileManager = FileManager.default
        let baseURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppIdentifiers.appGroup
        ) ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        persistenceURL = baseURL.appendingPathComponent("dashstar-state.json")

        if let data = try? Data(contentsOf: persistenceURL),
           var saved = try? decoder.decode(ProxyAppSnapshot.self, from: data) {
            if let defaultIndex = saved.routeConfigs.firstIndex(where: {
                $0.name == "Default" && $0.sourceGroupID == nil
            }) {
                saved.routeConfigs[defaultIndex].isBuiltIn = true
            }
            var seenServerIDs: Set<UUID> = []
            var repairedDuplicateIDs = false
            var hasGlobalSelection = false
            for groupIndex in saved.groups.indices {
                let originalSelection = saved.groups[groupIndex].selectedServerID
                var repairedSelection: UUID?
                for serverIndex in saved.groups[groupIndex].servers.indices {
                    let originalID = saved.groups[groupIndex].servers[serverIndex].id
                    if seenServerIDs.contains(originalID) {
                        saved.groups[groupIndex].servers[serverIndex].id = UUID()
                        repairedDuplicateIDs = true
                    }
                    let finalID = saved.groups[groupIndex].servers[serverIndex].id
                    seenServerIDs.insert(finalID)
                    if repairedSelection == nil, originalSelection == originalID {
                        repairedSelection = finalID
                    }
                    saved.groups[groupIndex].servers[serverIndex].name = SubscriptionService.cleanedNodeName(
                        saved.groups[groupIndex].servers[serverIndex].name
                    )
                }
                if originalSelection != nil {
                    saved.groups[groupIndex].selectedServerID = repairedSelection
                        ?? saved.groups[groupIndex].servers.first?.id
                }
                if saved.groups[groupIndex].selectedServerID != nil {
                    if hasGlobalSelection {
                        saved.groups[groupIndex].selectedServerID = nil
                        repairedDuplicateIDs = true
                    } else {
                        hasGlobalSelection = true
                    }
                }
            }
            snapshot = saved
            installBundledDefaultIfNeeded()
            if repairedDuplicateIDs,
               let repairedData = try? encoder.encode(saved) {
                try? repairedData.write(to: persistenceURL, options: .atomic)
            }
        } else {
            snapshot = .initial
            installBundledDefaultIfNeeded()
        }
    }

    private func installBundledDefaultIfNeeded() {
        guard snapshot.routeConfigs.count == 1,
              snapshot.routeConfigs[0].name == "Default",
              snapshot.routeConfigs[0].rules.isEmpty,
              let url = Bundle.main.url(forResource: "default", withExtension: "conf"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let id = snapshot.routeConfigs[0].id
        var imported = ShadowrocketConfigParser().parse(text)
        imported.id = id
        imported.isBuiltIn = true
        snapshot.routeConfigs[0] = imported
        snapshot.selectedConfigID = id
        if let data = try? encoder.encode(snapshot) {
            try? FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: persistenceURL, options: .atomic)
        }
    }

    var groups: [StoredProxyGroup] {
        snapshot.groups
    }

    var routeConfigs: [StoredRouteConfig] {
        snapshot.routeConfigs
    }

    func mutate(_ mutation: (inout ProxyAppSnapshot) -> Void) {
        mutation(&snapshot)
        save()
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: persistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(snapshot).write(to: persistenceURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

enum AppIdentifiers {
    static let appGroup = "group.com.xin.Dashstar"
    static let packetTunnelBundle = "com.xin.Dashstar.PacketTunnel"
}
