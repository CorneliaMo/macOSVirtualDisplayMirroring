import Foundation
import Network

public struct HealthSnapshot: Sendable {
    public var displayID: UInt32
    public var width: Int
    public var height: Int
    public var fps: Int
    public var viewerConnected: Bool
}

public final class HTTPStreamServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "VirtualDisplayStream.http")
    private var listener: NWListener?
    private var viewer: NWConnection?
    private var viewerReady = false
    private var sending = false
    private var pending: EncodedAccessUnit?
    private let health: @Sendable () -> HealthSnapshot
    private let onViewerConnected: @Sendable () -> Void

    public init(health: @escaping @Sendable () -> HealthSnapshot,
                onViewerConnected: @escaping @Sendable () -> Void) {
        self.health = health; self.onViewerConnected = onViewerConnected
    }

    public func start(port: UInt16) throws {
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw StreamError.listener("invalid port \(port)") }
            let listener = try NWListener(using: .tcp, on: nwPort)
            let startup = ListenerStartupState()
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.stateUpdateHandler = { state in
                guard !startup.isResolved else {
                    if case .failed(let error) = state { fputs("HTTP listener failed: \(error)\n", stderr) }
                    return
                }
                switch state {
                case .ready:
                    startup.resolve()
                case .failed(let error):
                    startup.resolve(error: error)
                case .cancelled:
                    startup.resolve()
                default:
                    break
                }
            }
            self.listener = listener; listener.start(queue: queue)
            guard startup.wait(timeout: .now() + 5) else {
                listener.cancel(); self.listener = nil
                throw StreamError.listener("listener did not become ready within five seconds")
            }
            if let startupError = startup.error {
                listener.cancel(); self.listener = nil
                throw StreamError.listener(startupError.localizedDescription)
            }
        } catch { throw StreamError.listener(error.localizedDescription) }
    }

    public func publish(_ unit: EncodedAccessUnit) {
        queue.async {
            guard self.viewer != nil else { return }
            if !self.viewerReady { guard unit.isKeyFrame else { return }; self.viewerReady = true }
            if self.sending { self.pending = unit; return }
            self.send(unit)
        }
    }

    public func stop() {
        queue.sync { self.viewer?.cancel(); self.viewer = nil; self.listener?.cancel(); self.listener = nil; self.pending = nil }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        guard accumulated.count < 8192 else {
            respond(connection, status: "431 Request Header Fields Too Large", body: "Request headers too large\n")
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - accumulated.count) { [weak self, weak connection] data, _, complete, error in
            guard let self, let connection else { return }
            if let error { connection.cancel(); fputs("HTTP request failed: \(error)\n", stderr); return }
            var requestData = accumulated
            if let data { requestData.append(data) }
            guard requestData.count <= 8192 else { self.respond(connection, status: "431 Request Header Fields Too Large", body: "Request headers too large\n"); return }
            guard requestData.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if complete { self.respond(connection, status: "400 Bad Request", body: "Incomplete request\n") }
                else { self.receiveRequest(on: connection, accumulated: requestData) }
                return
            }
            let request = String(data: requestData, encoding: .utf8) ?? ""
            let path = request.components(separatedBy: "\r\n").first?.split(separator: " ").dropFirst().first.map(String.init)
            guard request.hasPrefix("GET "), let path else { self.respond(connection, status: "400 Bad Request", body: "Bad Request\n"); return }
            switch path {
            case "/stream.h264": self.attachViewer(connection)
            case "/healthz": self.sendHealth(connection)
            default: self.respond(connection, status: "404 Not Found", body: "Not Found\n")
            }
        }
    }

    private func attachViewer(_ connection: NWConnection) {
        guard viewer == nil else { respond(connection, status: "409 Conflict", body: "A viewer is already connected.\n"); return }
        viewer = connection; viewerReady = false; sending = false; pending = nil
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state { self?.clearViewer(connection) }
            if case .cancelled = state { self?.clearViewer(connection) }
        }
        let header = "HTTP/1.0 200 OK\r\nContent-Type: video/H264\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else { self?.clearViewer(connection); return }
            self?.onViewerConnected()
        })
    }

    private func send(_ unit: EncodedAccessUnit) {
        guard let viewer else { return }; sending = true
        viewer.send(content: unit.data, completion: .contentProcessed { [weak self, weak viewer] error in
            guard let self else { return }; self.sending = false
            if error != nil { self.clearViewer(viewer); return }
            if let next = self.pending { self.pending = nil; self.send(next) }
        })
    }

    private func clearViewer(_ connection: NWConnection?) {
        guard let connection, let currentViewer = viewer, connection === currentViewer else { return }
        connection.cancel(); viewer = nil; viewerReady = false; sending = false; pending = nil
    }

    private func sendHealth(_ connection: NWConnection) {
        var value = health(); value.viewerConnected = viewer != nil
        let json = "{\"displayID\":\(value.displayID),\"width\":\(value.width),\"height\":\(value.height),\"fps\":\(value.fps),\"viewerConnected\":\(value.viewerConnected)}\n"
        respond(connection, status: "200 OK", body: json, contentType: "application/json")
    }

    private func respond(_ connection: NWConnection, status: String, body: String, contentType: String = "text/plain") {
        let response = "HTTP/1.0 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

private final class ListenerStartupState: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var resolved = false
    private var storedError: NWError?

    var isResolved: Bool { lock.withLock { resolved } }
    var error: NWError? { lock.withLock { storedError } }

    func resolve(error: NWError? = nil) {
        let shouldSignal = lock.withLock {
            guard !resolved else { return false }
            storedError = error
            resolved = true
            return true
        }
        if shouldSignal { semaphore.signal() }
    }

    func wait(timeout: DispatchTime) -> Bool {
        semaphore.wait(timeout: timeout) == .success
    }
}
