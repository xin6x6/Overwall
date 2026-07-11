import Foundation

enum SubscriptionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case emptySubscription
    case unsupportedContent

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The subscription URL is invalid."
        case .invalidResponse: "The subscription server returned an invalid response."
        case .emptySubscription: "The subscription does not contain any supported servers or rules."
        case .unsupportedContent: "This subscription format is not supported."
        }
    }
}

struct ImportedRouteSubscription {
    var rules: [StoredRouteRule]
    var remoteRuleSets: [StoredRemoteRuleSet]
}

struct ImportedGroupSubscription {
    var servers: [StoredProxyServer]
    var routeConfig: ImportedRouteSubscription?
}

struct SubscriptionService {
    func fetchGroupSubscription(from urlString: String, groupID: UUID) async throws -> ImportedGroupSubscription {
        let data = try await fetch(urlString)
        let servers = parseServers(from: data, groupID: groupID)
        guard !servers.isEmpty else { throw SubscriptionError.emptySubscription }
        return ImportedGroupSubscription(
            servers: servers,
            routeConfig: try? parseRouteConfig(from: data)
        )
    }

    func fetchServers(from urlString: String, groupID: UUID) async throws -> [StoredProxyServer] {
        let data = try await fetch(urlString)
        let servers = parseServers(from: data, groupID: groupID)
        guard !servers.isEmpty else { throw SubscriptionError.emptySubscription }
        return servers
    }

    private func parseServers(from data: Data, groupID: UUID) -> [StoredProxyServer] {
        let text = decodedSubscriptionText(data)
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { parseServer($0, groupID: groupID) }
    }

    func fetchRouteConfig(from urlString: String) async throws -> ImportedRouteSubscription {
        let data = try await fetch(urlString)
        return try parseRouteConfig(from: data)
    }

    private func parseRouteConfig(from data: Data) throws -> ImportedRouteSubscription {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try parseJSONRoute(root)
        }

        let decodedText = decodedSubscriptionText(data)
        if let decodedData = decodedText.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: decodedData) as? [String: Any] {
            return try parseJSONRoute(root)
        }
        return try parseRuleList(decodedText)
    }

    private func parseJSONRoute(_ root: [String: Any]) throws -> ImportedRouteSubscription {
        let route = root["route"] as? [String: Any] ?? root
        let rawRules = route["rules"] as? [[String: Any]] ?? []
        let rawRuleSets = route["rule_set"] as? [[String: Any]] ?? []

        var rules: [StoredRouteRule] = []
        for rawRule in rawRules {
            guard let target = routeTarget(rawRule) else { continue }
            for (jsonKey, kind) in routeFields {
                for value in strings(rawRule[jsonKey]) where !value.isEmpty {
                    rules.append(StoredRouteRule(matchKind: kind, value: value, target: target))
                }
            }
        }

        let ruleSets = rawRuleSets.compactMap { raw -> StoredRemoteRuleSet? in
            guard (raw["type"] as? String ?? "remote") == "remote",
                  let tag = raw["tag"] as? String,
                  let url = raw["url"] as? String,
                  !tag.isEmpty, !url.isEmpty else { return nil }
            return StoredRemoteRuleSet(
                tag: tag,
                url: url,
                format: raw["format"] as? String ?? "binary",
                updateInterval: raw["update_interval"] as? String ?? "1d"
            )
        }
        guard !rules.isEmpty || !ruleSets.isEmpty else { throw SubscriptionError.emptySubscription }
        return ImportedRouteSubscription(rules: rules, remoteRuleSets: ruleSets)
    }

    private func parseRuleList(_ text: String) throws -> ImportedRouteSubscription {
        let kindMapping: [String: RouteMatchKind] = [
            "DOMAIN": .domain,
            "DOMAIN-SUFFIX": .domainSuffix,
            "DOMAIN-KEYWORD": .domainKeyword,
            "IP-CIDR": .ipCIDR,
            "IP-CIDR6": .ipCIDR,
            "RULE-SET": .ruleSet,
        ]
        var rules: [StoredRouteRule] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//"),
                  !line.hasPrefix("[") else { continue }
            if line.hasPrefix("-") {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count >= 3, let kind = kindMapping[fields[0].uppercased()] else { continue }
            let action = fields[2].uppercased()
            let target: RouteTarget = action == "DIRECT" ? .direct
                : (action == "REJECT" || action == "BLOCK" || action == "REJECT-DROP" ? .block : .proxy)
            rules.append(StoredRouteRule(matchKind: kind, value: fields[1], target: target))
        }
        guard !rules.isEmpty else { throw SubscriptionError.unsupportedContent }
        return ImportedRouteSubscription(rules: rules, remoteRuleSets: [])
    }

    private let routeFields: [(String, RouteMatchKind)] = [
        ("domain", .domain),
        ("domain_suffix", .domainSuffix),
        ("domain_keyword", .domainKeyword),
        ("ip_cidr", .ipCIDR),
        ("rule_set", .ruleSet),
    ]

    private func fetch(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { throw SubscriptionError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Overwall/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SubscriptionError.invalidResponse
        }
        guard !data.isEmpty else { throw SubscriptionError.emptySubscription }
        return data
    }

    private func decodedSubscriptionText(_ data: Data) -> String {
        let raw = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.contains("://") { return raw }
        return decodeBase64String(raw).map { String(decoding: $0, as: UTF8.self) } ?? raw
    }

    private func parseServer(_ line: String, groupID: UUID) -> StoredProxyServer? {
        if line.hasPrefix("ss://") { return parseShadowsocks(line, groupID: groupID) }
        if line.hasPrefix("vmess://") { return parseVMess(line, groupID: groupID) }
        if line.hasPrefix("vless://") { return parseVLESS(line, groupID: groupID) }
        return nil
    }

    private func parseShadowsocks(_ line: String, groupID: UUID) -> StoredProxyServer? {
        guard var components = URLComponents(string: line) else { return nil }
        let name = components.fragment?.removingPercentEncoding
        components.fragment = nil

        var method = ""
        var password = ""
        var host = components.host ?? ""
        var port = components.port ?? 0

        if let user = components.user {
            let decodedUser = decodeBase64String(user).map { String(decoding: $0, as: UTF8.self) } ?? user.removingPercentEncoding ?? user
            let credential = components.password.map { decodedUser + ":" + ($0.removingPercentEncoding ?? $0) } ?? decodedUser
            let pieces = credential.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2 else { return nil }
            method = pieces[0]
            password = pieces[1]
        } else {
            let payload = String(line.dropFirst("ss://".count)).split(separator: "#", maxSplits: 1)[0]
            guard let decoded = decodeBase64String(String(payload)) else { return nil }
            let legacy = String(decoding: decoded, as: UTF8.self)
            guard let at = legacy.lastIndex(of: "@") else { return nil }
            let credential = String(legacy[..<at])
            let endpoint = String(legacy[legacy.index(after: at)...])
            let credentialParts = credential.split(separator: ":", maxSplits: 1).map(String.init)
            guard credentialParts.count == 2,
                  let endpointURL = URLComponents(string: "ss://x@\(endpoint)") else { return nil }
            method = credentialParts[0]
            password = credentialParts[1]
            host = endpointURL.host ?? ""
            port = endpointURL.port ?? 0
        }
        guard !host.isEmpty, port > 0, !method.isEmpty else { return nil }
        return StoredProxyServer(groupID: groupID, name: resolvedName(name, host), countryCode: countryCode(name), type: .shadowsocks, address: host, port: port, password: password, method: method)
    }

    private func parseVMess(_ line: String, groupID: UUID) -> StoredProxyServer? {
        let payload = String(line.dropFirst("vmess://".count))
        guard let data = decodeBase64String(payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let address = string(object["add"]),
              let port = int(object["port"]),
              let userID = string(object["id"]),
              !address.isEmpty, port > 0, !userID.isEmpty else { return nil }
        let name = string(object["ps"])
        let tls = string(object["tls"]) ?? ""
        return StoredProxyServer(
            groupID: groupID,
            name: resolvedName(name, address),
            countryCode: countryCode(name),
            type: .vmess,
            address: address,
            port: port,
            userID: userID,
            alterID: int(object["aid"]) ?? 0,
            security: string(object["scy"]) ?? "auto",
            transport: normalizedTransport(string(object["net"]) ?? "tcp"),
            tlsMode: tls.isEmpty || tls == "none" ? "none" : "tls",
            serverName: string(object["sni"]) ?? "",
            host: string(object["host"]) ?? "",
            path: string(object["path"]) ?? "",
            utlsFingerprint: string(object["fp"]),
            allowInsecure: (string(object["allowInsecure"]) == "1")
        )
    }

    private func parseVLESS(_ line: String, groupID: UUID) -> StoredProxyServer? {
        guard let components = URLComponents(string: line),
              let address = components.host, let port = components.port,
              let userID = components.user?.removingPercentEncoding, !userID.isEmpty else { return nil }
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name.lowercased(), $0) }
        })
        let security = query["security"] ?? "none"
        let name = components.fragment?.removingPercentEncoding
        return StoredProxyServer(
            groupID: groupID,
            name: resolvedName(name, address),
            countryCode: countryCode(name),
            type: .vless,
            address: address,
            port: port,
            userID: userID,
            transport: normalizedTransport(query["type"] ?? "tcp"),
            tlsMode: security,
            serverName: query["sni"] ?? "",
            host: query["host"] ?? "",
            path: (query["path"] ?? "").removingPercentEncoding ?? "",
            flow: query["flow"] ?? "",
            realityPublicKey: query["pbk"] ?? "",
            realityShortID: query["sid"] ?? "",
            utlsFingerprint: query["fp"],
            allowInsecure: query["allowinsecure"] == "1"
        )
    }

    private func routeTarget(_ rule: [String: Any]) -> RouteTarget? {
        if let action = rule["action"] as? String, action == "reject" { return .block }
        guard let outbound = rule["outbound"] as? String else { return nil }
        if outbound == "direct" { return .direct }
        if outbound == "block" { return .block }
        return .proxy
    }

    private func strings(_ value: Any?) -> [String] {
        if let string = value as? String { return [string] }
        return value as? [String] ?? []
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func decodeBase64String(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized.removeAll(where: \Character.isWhitespace)
        let remainder = normalized.count % 4
        if remainder != 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: normalized, options: .ignoreUnknownCharacters)
    }

    private func resolvedName(_ name: String?, _ fallback: String) -> String {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleaned = Self.cleanedNodeName(value)
        return cleaned.isEmpty ? fallback : cleaned
    }

    static func cleanedNodeName(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = value.first,
              first.unicodeScalars.count == 2,
              first.unicodeScalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) else {
            return value
        }

        value.removeFirst()
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "+" || value.first == "＋" {
            value.removeFirst()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private func normalizedTransport(_ transport: String) -> String {
        switch transport.lowercased() {
        case "h2": "http"
        case "websocket": "ws"
        default: transport.lowercased()
        }
    }

    private func countryCode(_ name: String?) -> String {
        guard let name else { return "" }
        for scalar in name.unicodeScalars where (0x1F1E6...0x1F1FF).contains(scalar.value) {
            let index = Int(scalar.value - 0x1F1E6)
            guard let first = UnicodeScalar(65 + index) else { continue }
            let following = name.unicodeScalars.drop(while: { $0 != scalar }).dropFirst().first
            if let following, (0x1F1E6...0x1F1FF).contains(following.value),
               let second = UnicodeScalar(65 + Int(following.value - 0x1F1E6)) {
                return String(first) + String(second)
            }
        }
        return ""
    }
}
