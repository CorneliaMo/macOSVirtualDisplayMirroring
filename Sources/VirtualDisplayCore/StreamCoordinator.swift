import CoreGraphics
import Foundation

@MainActor
public final class StreamCoordinator {
    private let display = VirtualDisplaySession()
    private let capture = DisplayCapture()
    private var encoder: H264Encoder?
    private var server: HTTPStreamServer?
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
        let encoderBox = EncoderBox()
        let server = HTTPStreamServer(health: { state.value }, onViewerConnected: { encoderBox.encoder?.requestKeyFrame() })
        do {
            let encoder = try H264Encoder(width: width, height: height, fps: configuration.fps, bitrate: configuration.bitrate) { result in
                switch result { case .success(let unit): server.publish(unit); case .failure(let error): fputs("Encoder: \(error)\n", stderr) }
            }
            encoderBox.encoder = encoder; self.encoder = encoder; self.server = server
            try server.start(port: configuration.port)
            try await capture.start(displayID: displayID, width: width, height: height, fps: configuration.fps,
                              showCursor: configuration.showCursor) { [weak encoder] buffer, pts in encoder?.encode(buffer, presentationTime: pts) }
            return snapshot
        } catch { await stop(); throw error }
    }

    public func stop() async {
        server?.stop(); server = nil; await capture.stop(); encoder?.stop(); encoder = nil; display.stop()
    }
}

private final class SnapshotBox: @unchecked Sendable {
    let value: HealthSnapshot
    init(_ value: HealthSnapshot) { self.value = value }
}
private final class EncoderBox: @unchecked Sendable { var encoder: H264Encoder? }
