import Darwin
import Foundation
import Network

struct TunnelProbeRequest: Codable {
    let type: String
    let testKind: String
    let method: String
    let probes: [TunnelProbeItem]
}

struct TunnelProbeItem: Codable {
    let id: UUID
    let address: String
    let port: Int
    let outboundTag: String
    let speedTestPort: Int?
}

struct TunnelProbeResponse: Codable {
    let results: [TunnelProbeResult]
    let error: String?
}

struct TunnelProbeResult: Codable {
    let id: UUID
    let latency: Int?
    let speedMegabytesPerSecond: Double?
}

struct TunnelProbeService {
    func run(_ request: TunnelProbeRequest) async -> TunnelProbeResponse {
        var latencies: [UUID: Int?] = [:]
        if request.testKind == "latency" {
            latencies = await withTaskGroup(of: (UUID, Int?).self, returning: [UUID: Int?].self) { group in
                for probe in request.probes {
                    group.addTask {
                        let latency: Int?
                        switch request.method.lowercased() {
                        case "icmp": latency = await icmpLatency(host: probe.address)
                        case "connect": latency = await outboundConnectLatency(tag: probe.outboundTag)
                        default: latency = await tcpLatency(host: probe.address, port: probe.port)
                        }
                        return (probe.id, latency)
                    }
                }
                var values: [UUID: Int?] = [:]
                for await (id, value) in group { values[id] = value }
                return values
            }
        }
        var results: [TunnelProbeResult] = []
        if request.testKind == "speed" {
            // Test up to three nodes at once: substantially faster than fully
            // serial testing without letting a large subscription saturate
            // the device with dozens of competing downloads.
            for start in stride(from: 0, to: request.probes.count, by: 3) {
                let batch = request.probes[start..<min(start + 3, request.probes.count)]
                let batchResults = await withTaskGroup(of: TunnelProbeResult.self, returning: [TunnelProbeResult].self) { group in
                    for probe in batch {
                        group.addTask {
                            let speed = if let port = probe.speedTestPort {
                                await downloadSpeed(proxyPort: port)
                            } else {
                                nil as Double?
                            }
                            return TunnelProbeResult(id: probe.id, latency: nil, speedMegabytesPerSecond: speed)
                        }
                    }
                    var values: [TunnelProbeResult] = []
                    for await value in group { values.append(value) }
                    return values
                }
                results.append(contentsOf: batchResults)
            }
        } else {
            results = request.probes.map {
                TunnelProbeResult(id: $0.id, latency: latencies[$0.id] ?? nil, speedMegabytesPerSecond: nil)
            }
        }
        return TunnelProbeResponse(results: results, error: nil)
    }
}

struct TunnelTrafficResponse: Codable {
    let uploadTotal: Int64
    let downloadTotal: Int64
    let directUploadTotal: Int64
    let directDownloadTotal: Int64
    let proxyUploadTotal: Int64
    let proxyDownloadTotal: Int64
    let connectedAt: Date?
    let error: String?
}

private let tunnelTrafficMonitor = TunnelTrafficMonitor()

func currentTunnelTraffic() async -> TunnelTrafficResponse {
    await tunnelTrafficMonitor.read()
}

private actor TunnelTrafficMonitor {
    private struct Counters {
        let upload: Int64
        let download: Int64
    }

    private var previousConnections: [String: Counters] = [:]
    private var directUpload: Int64 = 0
    private var directDownload: Int64 = 0
    private var proxyUpload: Int64 = 0
    private var proxyDownload: Int64 = 0
    private var connectedAt: Date?
    private var previousGlobal: Counters?

    func read() async -> TunnelTrafficResponse {
        guard let url = URL(string: "http://127.0.0.1:9090/connections") else {
            return response(error: "Invalid Clash API URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer dashstar-local-probe", forHTTPHeaderField: "Authorization")
        do {
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return response(error: "Unable to read tunnel traffic.")
        }
        let upload = (object["uploadTotal"] as? NSNumber)?.int64Value ?? 0
        let download = (object["downloadTotal"] as? NSNumber)?.int64Value ?? 0
        if connectedAt == nil || upload < (previousGlobal?.upload ?? 0) || download < (previousGlobal?.download ?? 0) {
            connectedAt = Date()
            previousConnections.removeAll()
            directUpload = 0
            directDownload = 0
            proxyUpload = 0
            proxyDownload = 0
        }
        previousGlobal = Counters(upload: upload, download: download)
        let connections = object["connections"] as? [[String: Any]] ?? []
        var currentConnections: [String: Counters] = [:]
        for connection in connections {
            guard let id = connection["id"] as? String else { continue }
            let counters = Counters(
                upload: (connection["upload"] as? NSNumber)?.int64Value ?? 0,
                download: (connection["download"] as? NSNumber)?.int64Value ?? 0
            )
            currentConnections[id] = counters
            guard let previous = previousConnections[id] else { continue }
            let uploadDelta = max(0, counters.upload - previous.upload)
            let downloadDelta = max(0, counters.download - previous.download)
            if usesProxy(connection) {
                proxyUpload += uploadDelta
                proxyDownload += downloadDelta
            } else {
                directUpload += uploadDelta
                directDownload += downloadDelta
            }
        }
        previousConnections = currentConnections
        return TunnelTrafficResponse(
            uploadTotal: upload,
            downloadTotal: download,
            directUploadTotal: directUpload,
            directDownloadTotal: directDownload,
            proxyUploadTotal: proxyUpload,
            proxyDownloadTotal: proxyDownload,
            connectedAt: connectedAt,
            error: nil
        )
        } catch {
            return response(error: error.localizedDescription)
        }
    }

    private func usesProxy(_ connection: [String: Any]) -> Bool {
        let metadata = connection["metadata"] as? [String: Any]
        let outbound = (metadata?["outbound"] as? String)
            ?? (connection["outbound"] as? String)
            ?? ""
        let chains = connection["chains"] as? [String] ?? []
        return ([outbound] + chains).contains {
            $0 == "proxy" || $0.hasPrefix("server-")
        }
    }

    private func response(error: String) -> TunnelTrafficResponse {
        TunnelTrafficResponse(
            uploadTotal: 0,
            downloadTotal: 0,
            directUploadTotal: directUpload,
            directDownloadTotal: directDownload,
            proxyUploadTotal: proxyUpload,
            proxyDownloadTotal: proxyDownload,
            connectedAt: connectedAt,
            error: error
        )
    }
}

private func tcpLatency(host: String, port: Int, timeout: TimeInterval = 5) async -> Int? {
    guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
    return await withCheckedContinuation { continuation in
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let completion = ProbeCompletion(continuation: continuation, connection: connection)
        let started = DispatchTime.now().uptimeNanoseconds
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                completion.finish(Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000))
            case .failed, .cancelled: completion.finish(nil)
            default: break
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
            completion.finish(nil)
        }
    }
}

private func outboundConnectLatency(tag: String) async -> Int? {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = 9090
    components.path = "/proxies/\(tag)/delay"
    components.queryItems = [
        URLQueryItem(name: "url", value: "https://www.gstatic.com/generate_204"),
        URLQueryItem(name: "timeout", value: "5000"),
    ]
    guard let url = components.url else { return nil }
    var request = URLRequest(url: url)
    request.setValue("Bearer dashstar-local-probe", forHTTPHeaderField: "Authorization")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delay = object["delay"] as? Int else { return nil }
        return delay
    } catch {
        return nil
    }
}

private func downloadSpeed(proxyPort: Int) async -> Double? {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.connectionProxyDictionary = [
        "HTTPEnable": 1,
        "HTTPProxy": "127.0.0.1",
        "HTTPPort": proxyPort,
        "HTTPSEnable": 1,
        "HTTPSProxy": "127.0.0.1",
        "HTTPSPort": proxyPort,
    ]
    let session = URLSession(configuration: configuration)
    do {
        // Establish the proxy, TLS session and congestion window before the
        // timed sample. This prevents handshake latency from dominating fast
        // nodes and producing values such as 0.1–1.5 MiB/s.
        guard let warmupURL = speedTestURL(bytes: 131_072) else { return nil }
        _ = try await session.data(from: warmupURL)

        guard let measuredURL = speedTestURL(bytes: 4_194_304) else { return nil }
        let started = ContinuousClock.now
        let (data, response) = try await session.data(from: measuredURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count >= 4_194_304 else { return nil }
        let duration = started.duration(to: .now).components
        let elapsed = max(
            Double(duration.seconds) + Double(duration.attoseconds) / 1_000_000_000_000_000_000,
            0.001
        )
        return Double(data.count) / 1_048_576 / elapsed
    } catch {
        return nil
    }
}

private func speedTestURL(bytes: Int) -> URL? {
    var components = URLComponents(string: "https://speed.cloudflare.com/__down")
    components?.queryItems = [
        URLQueryItem(name: "bytes", value: String(bytes)),
        URLQueryItem(name: "cache", value: UUID().uuidString),
    ]
    return components?.url
}

private func icmpLatency(host: String) async -> Int? {
    await Task.detached(priority: .userInitiated) { synchronousICMPLatency(host: host) }.value
}

private func synchronousICMPLatency(host: String) -> Int? {
    var hints = addrinfo()
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_DGRAM
    hints.ai_protocol = IPPROTO_ICMP
    var info: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &info) == 0, let info else { return nil }
    defer { freeaddrinfo(info) }

    let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
    guard descriptor >= 0 else { return nil }
    defer { close(descriptor) }
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var packet = [UInt8](repeating: 0, count: 16)
    packet[0] = 8 // ICMP echo request
    packet[4] = UInt8.random(in: 1...254)
    packet[6] = 0
    packet[7] = 1
    let sum = internetChecksum(packet)
    packet[2] = UInt8(sum >> 8)
    packet[3] = UInt8(sum & 0xff)

    let started = DispatchTime.now().uptimeNanoseconds
    let sent = packet.withUnsafeBytes { bytes in
        sendto(descriptor, bytes.baseAddress, bytes.count, 0, info.pointee.ai_addr, info.pointee.ai_addrlen)
    }
    guard sent == packet.count else { return nil }
    var reply = [UInt8](repeating: 0, count: 256)
    let received = reply.withUnsafeMutableBytes { bytes in
        recv(descriptor, bytes.baseAddress, bytes.count, 0)
    }
    guard received > 0 else { return nil }
    return Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
}

private func internetChecksum(_ bytes: [UInt8]) -> UInt16 {
    var sum: UInt32 = 0
    var index = 0
    while index + 1 < bytes.count {
        sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
        index += 2
    }
    if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
    while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
    return ~UInt16(sum)
}

private final class ProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int?, Never>?
    private let connection: NWConnection

    init(continuation: CheckedContinuation<Int?, Never>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ latency: Int?) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        lock.unlock()
        connection.cancel()
        continuation.resume(returning: latency)
    }
}
