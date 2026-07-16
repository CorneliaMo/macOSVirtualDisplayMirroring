import CoreGraphics
import Foundation

@MainActor
public final class NativeStreamCoordinator {
    private let display = VirtualDisplaySession()
    private let capture = DisplayCapture()
    private var webRTC: WebRTCSession?
    private var server: BrowserServer?
    private var snapshot = HealthSnapshot(displayID: 0, width: 0, height: 0, fps: 0, viewerConnected: false)

    public init() {}

    public func start(_ configuration: StreamConfiguration) async throws -> HealthSnapshot {
        let displayID = try await display.start(configuration: configuration)
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            display.stop(); throw StreamError.screenCapturePermissionDenied
        }
        let width = Int(CGDisplayPixelsWide(displayID)); let height = Int(CGDisplayPixelsHigh(displayID))
        guard width > 0, height > 0 else { display.stop(); throw StreamError.captureCreationFailed }
        snapshot = .init(displayID: displayID, width: width, height: height, fps: configuration.fps, viewerConnected: false)
        let state = SnapshotBox(snapshot)
        let sessionBox = SessionBox()
        let serverBox = ServerBox()
        let server = BrowserServer(health: { state.value }, onMessage: { sessionBox.session?.receive($0) },
                                   onConnected: { state.viewerConnected = true; sessionBox.session?.start() },
                                   onDisconnected: { state.viewerConnected = false; sessionBox.session?.stop() })
        do {
            let webRTC = WebRTCSession(width: width, height: height, fps: configuration.fps,
                                       bitrate: configuration.bitrate) { serverBox.server?.send($0) }
            sessionBox.session = webRTC; serverBox.server = server
            self.webRTC = webRTC; self.server = server
            try server.start(port: configuration.port)
            try await capture.start(displayID: displayID, width: width, height: height, fps: configuration.fps,
                              showCursor: configuration.showCursor) { [weak webRTC] buffer, pts in webRTC?.push(buffer, presentationTime: pts) }
            return snapshot
        } catch { await stop(); throw error }
    }

    public func stop() async {
        server?.stop(); server = nil; await capture.stop(); webRTC?.stop(); webRTC = nil; display.stop()
    }
}

@MainActor
public final class StreamCoordinator {
    private var native: NativeStreamCoordinator?
    private var chromium: ChromiumStreamCoordinator?

    public init() {}

    public func start(_ configuration: StreamConfiguration) async throws -> HealthSnapshot {
        switch configuration.backend {
        case .native:
            let coordinator = NativeStreamCoordinator(); native = coordinator
            return try await coordinator.start(configuration)
        case .chromium:
            let coordinator = ChromiumStreamCoordinator(); chromium = coordinator
            return try await coordinator.start(configuration)
        }
    }

    public func stop() async {
        await native?.stop(); native = nil
        chromium?.stop(); chromium = nil
    }
}

private final class SnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: HealthSnapshot
    init(_ value: HealthSnapshot) { stored = value }
    var value: HealthSnapshot { lock.withLock { stored } }
    var viewerConnected: Bool {
        get { lock.withLock { stored.viewerConnected } }
        set { lock.withLock { stored.viewerConnected = newValue } }
    }
}
private final class SessionBox: @unchecked Sendable { var session: WebRTCSession? }
private final class ServerBox: @unchecked Sendable { var server: BrowserServer? }
