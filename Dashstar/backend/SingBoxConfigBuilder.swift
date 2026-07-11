import Foundation

enum SingBoxConfigError: LocalizedError {
    case noProxyServer
    case noValidProxyServer

    var errorDescription: String? {
        switch self {
        case .noProxyServer:
            "Add and select at least one proxy server before starting the VPN."
        case .noValidProxyServer:
            "No valid proxy server is available. Check the selected server's address, port and authentication fields."
        }
    }
}

struct SingBoxConfigBuilder {
    func build(from snapshot: ProxyAppSnapshot) throws -> String {
        let allServers = snapshot.groups.flatMap(\.servers)
        guard !allServers.isEmpty || snapshot.routingMode == .direct else {
            throw SingBoxConfigError.noProxyServer
        }
        let servers = allServers.filter(Self.isUsable)
        guard !servers.isEmpty || snapshot.routingMode == .direct else {
            throw SingBoxConfigError.noValidProxyServer
        }

        let taggedServers = servers.enumerated().map { index, server in
            (server: server, tag: Self.outboundTag(for: server.id), probePort: 21_000 + index)
        }
        let serverTags = taggedServers.map(\.tag)
        let usableIDs = Set(servers.map(\.id))
        let selectedID = snapshot.groups.compactMap(\.selectedServerID).first(where: usableIDs.contains)
        let selectedTag = selectedID.flatMap { selectedID in
            taggedServers.first(where: { $0.server.id == selectedID })?.tag
        } ?? serverTags.first

        var outbounds = taggedServers.map { outbound($0.server, tag: $0.tag) }
        if !serverTags.isEmpty {
            outbounds.insert([
                "type": "selector",
                "tag": "proxy",
                "outbounds": serverTags,
                "default": selectedTag as Any,
            ], at: 0)
        }
        outbounds.append(["type": "direct", "tag": "direct"])

        var rules: [[String: Any]] = [
            ["action": "sniff"],
            ["protocol": "dns", "action": "hijack-dns"],
        ]
        rules.append(contentsOf: taggedServers.map {
            ["inbound": ["probe-\($0.server.id.uuidString)"], "action": "route", "outbound": $0.tag]
        })
        if snapshot.routingMode == .config,
           let config = snapshot.routeConfigs.first(where: { $0.id == snapshot.selectedConfigID })
                ?? snapshot.routeConfigs.first {
            let ruleSetTags = Set((config.remoteRuleSets ?? []).map(\.tag))
            rules.append(contentsOf: config.rules.filter {
                $0.enabled
                    && $0.matchKind != .final
                    && $0.matchKind != .userAgent
                    && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && ($0.matchKind != .ruleSet || ruleSetTags.contains($0.value))
                    && ($0.matchKind != .geoIP || ruleSetTags.contains("geoip-\($0.value.lowercased())"))
            }.map(routeRule))
        }

        let finalOutbound: String
        switch snapshot.routingMode {
        case .direct: finalOutbound = "direct"
        case .global: finalOutbound = serverTags.isEmpty ? "direct" : "proxy"
        case .config:
            let selectedConfig = snapshot.routeConfigs.first(where: { $0.id == snapshot.selectedConfigID })
                ?? snapshot.routeConfigs.first
            let configuredTarget = selectedConfig?.rules.last(where: { $0.enabled && $0.matchKind == .final })?.target
            switch configuredTarget {
            case .direct: finalOutbound = "direct"
            case .block: finalOutbound = "block"
            case .proxy, .none: finalOutbound = serverTags.isEmpty ? "direct" : "proxy"
            }
        }

        if finalOutbound == "block", !outbounds.contains(where: { ($0["tag"] as? String) == "block" }) {
            outbounds.append(["type": "block", "tag": "block"])
        }

        var route: [String: Any] = [
            "rules": rules,
            "final": finalOutbound,
            // Resolve proxy server hostnames without entering the proxy first.
            "default_domain_resolver": ["server": "local"],
        ]
        if snapshot.routingMode == .config,
           let config = snapshot.routeConfigs.first(where: { $0.id == snapshot.selectedConfigID })
                ?? snapshot.routeConfigs.first {
            let remoteRuleSets = (config.remoteRuleSets ?? []).filter {
                !$0.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && URL(string: $0.url)?.scheme != nil
            }
            if !remoteRuleSets.isEmpty {
                route["rule_set"] = remoteRuleSets.map { ruleSet in
                    [
                        "type": "remote",
                        "tag": ruleSet.tag,
                        "format": ruleSet.format,
                        "url": ruleSet.url,
                        "download_detour": finalOutbound,
                        "update_interval": ruleSet.updateInterval,
                    ]
                }
            }
        }

        let probeInbounds: [[String: Any]] = taggedServers.map {
            [
                "type": "mixed",
                "tag": "probe-\($0.server.id.uuidString)",
                "listen": "127.0.0.1",
                "listen_port": $0.probePort,
            ]
        }
        let configuration: [String: Any] = [
            "log": ["level": "info", "timestamp": true],
            "dns": [
                "servers": [
                    ["type": "local", "tag": "local"],
                    [
                        "type": "https",
                        "tag": "remote",
                        "server": "1.1.1.1",
                        "detour": finalOutbound,
                    ],
                ],
                "final": finalOutbound == "direct" ? "local" : "remote",
            ],
            "inbounds": [[
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                "auto_route": true,
            ]] + probeInbounds,
            "outbounds": outbounds,
            "route": route,
            "experimental": [
                "clash_api": [
                    "external_controller": "127.0.0.1:9090",
                    "secret": "dashstar-local-probe",
                ],
            ],
        ]

        let data = try JSONSerialization.data(
            withJSONObject: configuration,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    static func outboundTag(for serverID: UUID) -> String {
        "server-\(serverID.uuidString)"
    }

    static func probePortMap(from snapshot: ProxyAppSnapshot) -> [UUID: Int] {
        let servers = snapshot.groups.flatMap(\.servers).filter(Self.isUsable)
        return Dictionary(uniqueKeysWithValues: servers.enumerated().map { index, server in
            (server.id, 21_000 + index)
        })
    }

    private func outbound(_ server: StoredProxyServer, tag: String) -> [String: Any] {
        var result: [String: Any] = [
            "type": server.type.rawValue,
            "tag": tag,
            "server": server.address,
            "server_port": server.port,
        ]

        switch server.type {
        case .shadowsocks:
            result["method"] = server.method
            result["password"] = server.password
        case .vmess:
            result["uuid"] = server.userID
            result["security"] = server.security
            result["alter_id"] = server.alterID
        case .vless:
            result["uuid"] = server.userID
            if !server.flow.isEmpty && server.flow != "none" { result["flow"] = server.flow }
        }

        let transportType = normalizedTransport(server.transport)
        if transportType != "tcp" {
            var transport: [String: Any] = ["type": transportType]
            if !server.path.isEmpty {
                transport[transportType == "grpc" ? "service_name" : "path"] = server.path
            }
            if !server.host.isEmpty { transport["headers"] = ["Host": server.host] }
            result["transport"] = transport
        }

        if server.tlsMode != "none" {
            var tls: [String: Any] = [
                "enabled": true,
                "server_name": server.serverName.isEmpty ? server.address : server.serverName,
                "insecure": server.allowInsecure,
            ]
            if server.tlsMode == "reality" {
                tls["reality"] = [
                    "enabled": true,
                    "public_key": server.realityPublicKey,
                    "short_id": server.realityShortID,
                ]
            }
            let fingerprint = server.utlsFingerprint?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if server.tlsMode == "reality" || !fingerprint.isEmpty {
                tls["utls"] = [
                    "enabled": true,
                    "fingerprint": fingerprint.isEmpty ? "chrome" : fingerprint,
                ]
            }
            result["tls"] = tls
        }
        return result
    }

    private func routeRule(_ rule: StoredRouteRule) -> [String: Any] {
        let field: String
        switch rule.matchKind {
        case .domain: field = "domain"
        case .domainSuffix: field = "domain_suffix"
        case .domainKeyword: field = "domain_keyword"
        case .ipCIDR: field = "ip_cidr"
        case .ruleSet: field = "rule_set"
        case .geoIP:
            field = "rule_set"
        case .userAgent, .final:
            // These are filtered before conversion. Keep this fallback structurally valid.
            field = "domain"
        }
        let value = rule.matchKind == .geoIP ? "geoip-\(rule.value.lowercased())" : rule.value
        if rule.target == .block {
            return [field: [value], "action": "reject"]
        }
        return [field: [value], "action": "route", "outbound": rule.target.rawValue]
    }

    nonisolated private static func isUsable(_ server: StoredProxyServer) -> Bool {
        guard !server.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...65_535).contains(server.port) else { return false }
        switch server.type {
        case .shadowsocks:
            return !server.method.isEmpty && !server.password.isEmpty
        case .vmess, .vless:
            guard UUID(uuidString: server.userID) != nil else { return false }
            if server.tlsMode == "reality" {
                return !server.realityPublicKey.isEmpty
            }
            return true
        }
    }

    private func normalizedTransport(_ transport: String) -> String {
        switch transport.lowercased() {
        case "h2": "http"
        case "websocket": "ws"
        default: transport.lowercased()
        }
    }
}
