import Foundation

enum ProxyProtocolKind: String, Codable, CaseIterable, Identifiable {
    case shadowsocks
    case vmess
    case vless

    var id: Self { self }
}

struct StoredProxyServer: Codable, Identifiable, Hashable {
    var id = UUID()
    var groupID: UUID
    var name: String
    var countryCode: String = ""
    var type: ProxyProtocolKind
    var address: String
    var port: Int
    var password: String = ""
    var method: String = ""
    var userID: String = ""
    var alterID: Int = 0
    var security: String = "auto"
    var transport: String = "tcp"
    var tlsMode: String = "none"
    var serverName: String = ""
    var host: String = ""
    var path: String = ""
    var flow: String = ""
    var realityPublicKey: String = ""
    var realityShortID: String = ""
    var utlsFingerprint: String?
    var allowInsecure = false
    var latencyMilliseconds: Int?
    var speedMegabytesPerSecond: Double?
}

struct StoredProxyGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var subscriptionURL: String?
    var selectedServerID: UUID?
    var servers: [StoredProxyServer] = []
}

enum RouteTarget: String, Codable, CaseIterable, Identifiable {
    case proxy
    case direct
    case block

    var id: Self { self }
}

enum RouteMatchKind: String, Codable, CaseIterable, Identifiable {
    case domain
    case domainSuffix
    case domainKeyword
    case ipCIDR
    case ruleSet

    var id: Self { self }
}

struct StoredRouteRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var matchKind: RouteMatchKind
    var value: String
    var target: RouteTarget
    var enabled = true
}

struct StoredRemoteRuleSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var tag: String
    var url: String
    var format: String = "binary"
    var updateInterval: String = "1d"
}

struct StoredRouteConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var subscriptionURL: String?
    var rules: [StoredRouteRule] = []
    // Optional keeps snapshots written by earlier builds decodable.
    var remoteRuleSets: [StoredRemoteRuleSet]?
    // Identifies a config managed by a proxy-group subscription.
    var sourceGroupID: UUID?
}

enum StoredRoutingMode: String, Codable {
    case config
    case global
    case direct
}

struct ProxyAppSnapshot: Codable {
    var groups: [StoredProxyGroup]
    var routeConfigs: [StoredRouteConfig]
    var selectedConfigID: UUID?
    var routingMode: StoredRoutingMode

    static let initial = ProxyAppSnapshot(
        groups: [StoredProxyGroup(name: "Default")],
        routeConfigs: [StoredRouteConfig(name: "Default")],
        selectedConfigID: nil,
        routingMode: .config
    )
}
