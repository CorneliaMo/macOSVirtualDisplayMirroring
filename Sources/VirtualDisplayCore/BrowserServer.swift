import Foundation
@preconcurrency import Swifter

public final class BrowserServer: @unchecked Sendable {
    public typealias MessageHandler = @Sendable (SignalMessage) -> Void

    private let queue = DispatchQueue(label: "VirtualDisplayStream.browser")
    private let server = HttpServer()
    private let health: @Sendable () -> HealthSnapshot
    private let onMessage: MessageHandler
    private let onConnected: @Sendable () -> Void
    private let onDisconnected: @Sendable () -> Void
    private var viewer: WebSocketSession?

    public init(health: @escaping @Sendable () -> HealthSnapshot,
                onMessage: @escaping MessageHandler,
                onConnected: @escaping @Sendable () -> Void,
                onDisconnected: @escaping @Sendable () -> Void) {
        self.health = health; self.onMessage = onMessage
        self.onConnected = onConnected; self.onDisconnected = onDisconnected
        configureRoutes()
    }

    public func start(port: UInt16) throws {
        do { try server.start(port, forceIPv4: false) }
        catch { throw StreamError.listener(error.localizedDescription) }
    }

    public func send(_ message: SignalMessage) {
        queue.async {
            guard let viewer = self.viewer else { return }
            guard let payload = try? message.encoded() else { return }
            viewer.writeText(payload)
        }
    }

    public func stop() {
        queue.sync { if let viewer { disconnect(viewer) }; server.stop() }
    }

    private func configureRoutes() {
        server["/"] = { _ in Self.resource("index", extension: "html", contentType: "text/html; charset=utf-8") }
        server["/viewer.js"] = { _ in Self.resource("viewer", extension: "js", contentType: "text/javascript; charset=utf-8") }
        server["/viewer.css"] = { _ in Self.resource("viewer", extension: "css", contentType: "text/css; charset=utf-8") }
        server["/healthz"] = { [health] _ in
            let value = health()
            let body = "{\"displayID\":\(value.displayID),\"width\":\(value.width),\"height\":\(value.height),\"fps\":\(value.fps),\"viewerConnected\":\(value.viewerConnected)}"
            return .ok(.data(Data(body.utf8), contentType: "application/json; charset=utf-8"))
        }
        server["/signal"] = websocket(
            text: { [weak self] session, text in self?.receive(text, from: session) },
            connected: { [weak self] session in self?.connect(session) },
            disconnected: { [weak self] session in self?.scheduleDisconnect(session) }
        )
    }

    private func connect(_ session: WebSocketSession) {
        let session = WebSocketBox(session)
        queue.async {
            guard self.viewer == nil else {
                if let message = try? SignalMessage(type: .error, message: "Another viewer is already connected").encoded() {
                    session.value.writeText(message)
                }
                session.value.writeCloseFrame()
                return
            }
            self.viewer = session.value
            self.onConnected()
        }
    }

    private func receive(_ text: String, from session: WebSocketSession) {
        let session = WebSocketBox(session)
        queue.async {
            guard let viewer = self.viewer, viewer === session.value else { return }
            do { self.onMessage(try SignalMessage.decode(text)) }
            catch {
                if let message = try? SignalMessage(type: .error, message: error.localizedDescription).encoded() {
                    viewer.writeText(message)
                }
            }
        }
    }

    private func disconnect(_ session: WebSocketSession) {
        guard let viewer, viewer === session else { return }
        self.viewer = nil
        session.writeCloseFrame()
        onDisconnected()
    }

    private func scheduleDisconnect(_ session: WebSocketSession) {
        let session = WebSocketBox(session)
        queue.async { self.disconnect(session.value) }
    }

    private static func resource(_ name: String, extension ext: String, contentType: String) -> HttpResponse {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: url) else { return .internalServerError(nil) }
        return .ok(.data(data, contentType: contentType))
    }
}

private final class WebSocketBox: @unchecked Sendable {
    let value: WebSocketSession
    init(_ value: WebSocketSession) { self.value = value }
}
