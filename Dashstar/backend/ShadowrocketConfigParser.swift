import Foundation

struct ShadowrocketConfigParser {
    func parse(_ text: String, name: String = "Default") -> StoredRouteConfig {
        var section = ""
        var options: [StoredConfigOption] = []
        var rules: [StoredRouteRule] = []
        var ruleSets: [StoredRemoteRuleSet] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("//") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            if section == "general", let separator = line.firstIndex(of: "=") {
                let key = line[..<separator].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                options.append(StoredConfigOption(key: key, value: value))
            } else if section == "rule", let rule = parseRule(line) {
                rules.append(rule)
                if rule.matchKind == .geoIP {
                    let tag = "geoip-\(rule.value.lowercased())"
                    if !ruleSets.contains(where: { $0.tag == tag }) {
                        ruleSets.append(StoredRemoteRuleSet(
                            tag: tag,
                            url: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/\(tag).srs"
                        ))
                    }
                }
            }
        }

        return StoredRouteConfig(
            name: name,
            rules: rules,
            remoteRuleSets: ruleSets,
            generalOptions: options
        )
    }

    private func parseRule(_ line: String) -> StoredRouteRule? {
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count >= 2 else { return nil }
        let type = fields[0].uppercased()
        let kind: RouteMatchKind
        let value: String
        let policy: String
        switch type {
        case "DOMAIN": kind = .domain
        case "DOMAIN-SUFFIX": kind = .domainSuffix
        case "DOMAIN-KEYWORD": kind = .domainKeyword
        case "IP-CIDR", "IP-CIDR6": kind = .ipCIDR
        case "RULE-SET": kind = .ruleSet
        case "GEOIP": kind = .geoIP
        case "USER-AGENT": kind = .userAgent
        case "FINAL", "MATCH":
            kind = .final
            value = "All unmatched traffic"
            policy = fields[1]
            return StoredRouteRule(matchKind: kind, value: value, target: target(policy))
        default: return nil
        }
        guard fields.count >= 3 else { return nil }
        value = fields[1]
        policy = fields[2]
        return StoredRouteRule(matchKind: kind, value: value, target: target(policy))
    }

    private func target(_ policy: String) -> RouteTarget {
        switch policy.uppercased() {
        case "DIRECT": return .direct
        case "REJECT", "REJECT-DROP", "REJECT-NO-DROP", "BLOCK": return .block
        default: return .proxy
        }
    }
}
