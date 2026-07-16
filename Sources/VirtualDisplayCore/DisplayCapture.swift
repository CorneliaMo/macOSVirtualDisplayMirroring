import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import IOSurface

public final class DisplayCapture: @unchecked Sendable {
    public typealias FrameHandler = @Sendable (CVPixelBuffer, CMTime) -> Void
    private let queue = DispatchQueue(label: "VirtualDisplayStream.capture")
    private var stream: CGDisplayStream?
    private var frameNumber: Int64 = 0

    public init() {}
    public func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, showCursor: Bool,
                      onFrame: @escaping FrameHandler) throws {
        let properties: [CFString: Any] = [
            kCGDisplayStreamShowCursor: showCursor,
            kCGDisplayStreamMinimumFrameTime: 1.0 / Double(fps),
            kCGDisplayStreamQueueDepth: 3,
        ]
        guard let created = CGDisplayStream(dispatchQueueDisplay: displayID, outputWidth: width, outputHeight: height,
            pixelFormat: Int32(kCVPixelFormatType_32BGRA), properties: properties as CFDictionary,
            queue: queue, handler: { [weak self] status, _, surface, _ in
                guard status == .frameComplete, let surface else { return }
                var buffer: CVPixelBuffer?
                let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
                guard CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, attributes, &buffer) == kCVReturnSuccess,
                      let buffer else { return }
                self?.frameNumber += 1
                let pts = CMTime(value: self?.frameNumber ?? 0, timescale: CMTimeScale(fps))
                onFrame(buffer, pts)
            }) else { throw StreamError.captureCreationFailed }
        stream = created
        let status = CGDisplayStreamStart(created)
        guard status == .success else { stream = nil; throw StreamError.captureStopped("start returned \(status.rawValue)") }
    }
    public func stop() { if let stream { CGDisplayStreamStop(stream) }; stream = nil }
}
