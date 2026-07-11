import Foundation
import Network

struct ConnectivityService {
    func latency(to server: StoredProxyServer, timeout: TimeInterval = 5) async -> Int? {
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: server.port)) else { return nil }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(server.address), port: port, using: .tcp)
            let completion = ProbeCompletion(continuation: continuation, connection: connection)
            let started = DispatchTime.now().uptimeNanoseconds

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - started
                    completion.finish(Int(elapsed / 1_000_000))
                case .failed, .cancelled:
                    completion.finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                completion.finish(nil)
            }
        }
    }
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
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        lock.unlock()
        connection.cancel()
        continuation.resume(returning: latency)
    }
}
