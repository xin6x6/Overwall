import Darwin
import Foundation

struct RoutingTestResult: Equatable {
    let target: RouteTarget
    let reason: String
    let detail: String
}

enum RoutingTestError: LocalizedError {
    case invalidAddress
    case noConfig

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            String(localized: "Enter a valid URL or host name.")
        case .noConfig:
            String(localized: "No routing config is available.")
        }
    }
}

struct RoutingRuleTester {
    func test(_ input: String, snapshot: ProxyAppSnapshot) throws -> RoutingTestResult {
        let host = try normalizedHost(input)

        switch snapshot.routingMode {
        case .global:
            return RoutingTestResult(
                target: .proxy,
                reason: String(localized: "Global mode"),
                detail: String(localized: "All traffic uses Proxy while Global routing mode is selected.")
            )
        case .direct:
            return RoutingTestResult(
                target: .direct,
                reason: String(localized: "Direct mode"),
                detail: String(localized: "All traffic uses Direct while Direct routing mode is selected.")
            )
        case .config:
            break
        }

        guard let config = snapshot.routeConfigs.first(where: { $0.id == snapshot.selectedConfigID })
                ?? snapshot.routeConfigs.first else {
            throw RoutingTestError.noConfig
        }

        let enabledRules = config.rules.filter(\.enabled)
        var runtimeOnlyKinds = Set<RouteMatchKind>()
        for (index, rule) in enabledRules.enumerated() {
            let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch rule.matchKind {
            case .domain where host == normalizedDomain(value):
                return match(rule, index: index, label: "Domain")
            case .domainSuffix where matchesSuffix(host, suffix: value):
                return match(rule, index: index, label: "Domain Suffix")
            case .domainKeyword where !value.isEmpty && host.contains(value.lowercased()):
                return match(rule, index: index, label: "Domain Keyword")
            case .ipCIDR where matchesIPv4CIDR(host, cidr: value):
                return match(rule, index: index, label: "IP CIDR")
            case .ruleSet:
                runtimeOnlyKinds.insert(.ruleSet)
            case .geoIP:
                runtimeOnlyKinds.insert(.geoIP)
            case .final:
                let skipped = runtimeOnlyDescription(runtimeOnlyKinds)
                return RoutingTestResult(
                    target: rule.target,
                    reason: String(localized: "Final (Unmatched)"),
                    detail: String(
                        format: String(localized: "Rule %d · No earlier locally testable rule matched.%@"),
                        index + 1,
                        skipped
                    )
                )
            case .userAgent:
                break
            default:
                break
            }
        }

        let skipped = runtimeOnlyDescription(runtimeOnlyKinds)
        return RoutingTestResult(
            target: .proxy,
            reason: String(localized: "Final (Unmatched)"),
            detail: String(localized: "No enabled rule matched; Dashstar defaults to Proxy.") + skipped
        )
    }

    private func match(_ rule: StoredRouteRule, index: Int, label: String) -> RoutingTestResult {
        RoutingTestResult(
            target: rule.target,
            reason: String(localized: String.LocalizationValue(label)),
            detail: String(
                format: String(localized: "Rule %d · %@ = %@"),
                index + 1,
                String(localized: String.LocalizationValue(label)),
                rule.value
            )
        )
    }

    private func normalizedHost(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RoutingTestError.invalidAddress }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: candidate)?.host?.lowercased(), !host.isEmpty else {
            throw RoutingTestError.invalidAddress
        }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func normalizedDomain(_ value: String) -> String {
        value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func matchesSuffix(_ host: String, suffix: String) -> Bool {
        let suffix = normalizedDomain(suffix)
        return !suffix.isEmpty && (host == suffix || host.hasSuffix(".\(suffix)"))
    }

    private func matchesIPv4CIDR(_ host: String, cidr: String) -> Bool {
        let parts = cidr.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let prefix = Int(parts[1]), (0...32).contains(prefix) else { return false }
        var hostAddress = in_addr()
        var networkAddress = in_addr()
        guard inet_pton(AF_INET, host, &hostAddress) == 1,
              inet_pton(AF_INET, parts[0], &networkAddress) == 1 else { return false }
        let mask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        return UInt32(bigEndian: hostAddress.s_addr) & mask
            == UInt32(bigEndian: networkAddress.s_addr) & mask
    }

    private func runtimeOnlyDescription(_ kinds: Set<RouteMatchKind>) -> String {
        guard !kinds.isEmpty else { return "" }
        let names = kinds.map { $0 == .geoIP ? "GeoIP" : "Geosite/Rule Set" }.sorted().joined(separator: ", ")
        return " " + String(
            format: String(localized: "Note: %@ membership is evaluated by the live VPN engine and cannot be expanded locally."),
            names
        )
    }
}
