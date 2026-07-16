import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

public final class DisplayCapture: @unchecked Sendable {
    public typealias FrameHandler = @Sendable (CVPixelBuffer, CMTime) -> Void

    private let queue = DispatchQueue(label: "VirtualDisplayStream.capture")
    private var stream: SCStream?
    private var output: DisplayStreamOutput?

    public init() {}

    public func start(
        displayID: CGDirectDisplayID,
        width: Int,
        height: Int,
        fps: Int,
        showCursor: Bool,
        onFrame: @escaping FrameHandler
    ) async throws {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw StreamError.captureCreationFailed
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.width = width
            configuration.height = height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            configuration.showsCursor = showCursor
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.queueDepth = 3

            let output = DisplayStreamOutput(onFrame: onFrame)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.output = output
            self.stream = stream
        } catch let error as StreamError {
            throw error
        } catch {
            throw StreamError.captureStopped(error.localizedDescription)
        }
    }

    public func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        output = nil
    }
}

private final class DisplayStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFrame: DisplayCapture.FrameHandler

    init(onFrame: @escaping DisplayCapture.FrameHandler) {
        self.onFrame = onFrame
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }
}
