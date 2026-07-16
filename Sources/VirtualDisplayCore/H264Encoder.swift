import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public struct EncodedAccessUnit: Sendable {
    public let data: Data
    public let isKeyFrame: Bool
    public let presentationTime: CMTime
}

public enum AnnexBConverter {
    public static func convertAVCC(_ data: Data, nalLengthSize: Int = 4) throws -> Data {
        guard (1...4).contains(nalLengthSize) else { throw StreamError.encoder("invalid NAL length size") }
        var output = Data(); var offset = 0
        while offset < data.count {
            guard offset + nalLengthSize <= data.count else { throw StreamError.encoder("truncated AVCC NAL length") }
            var length = 0
            for byte in data[offset..<(offset + nalLengthSize)] { length = (length << 8) | Int(byte) }
            offset += nalLengthSize
            guard length > 0, offset + length <= data.count else { throw StreamError.encoder("invalid AVCC NAL length") }
            output.append(contentsOf: [0, 0, 0, 1]); output.append(data[offset..<(offset + length)])
            offset += length
        }
        return output
    }
}

public final class H264Encoder: @unchecked Sendable {
    public typealias Output = @Sendable (Result<EncodedAccessUnit, Error>) -> Void
    private let queue = DispatchQueue(label: "VirtualDisplayStream.encoder")
    private var session: VTCompressionSession?
    private var forceKeyFrame = true
    private let output: Output

    public init(width: Int, height: Int, fps: Int, bitrate: Int, output: @escaping Output) throws {
        self.output = output
        var created: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: encoderCallback, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &created
        )
        guard status == noErr, let created else { throw StreamError.encoder("VTCompressionSessionCreate returned \(status)") }
        session = created
        try set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel)
        try set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        try set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: bitrate))
        try set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: fps))
        try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: fps))
        let prepare = VTCompressionSessionPrepareToEncodeFrames(created)
        guard prepare == noErr else { throw StreamError.encoder("prepare returned \(prepare)") }
    }

    deinit { stop() }
    public func requestKeyFrame() { queue.async { self.forceKeyFrame = true } }
    public func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        queue.async {
            guard let session = self.session else { return }
            let properties = self.forceKeyFrame ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
            self.forceKeyFrame = false
            let status = VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: presentationTime,
                duration: .invalid, frameProperties: properties, sourceFrameRefcon: nil, infoFlagsOut: nil)
            if status != noErr { self.output(.failure(StreamError.encoder("encode returned \(status)"))) }
        }
    }
    public func stop() {
        queue.sync {
            guard let session else { return }
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session); self.session = nil
        }
    }
    private func set(_ key: CFString, _ value: CFTypeRef) throws {
        guard let session else { return }
        let status = VTSessionSetProperty(session, key: key, value: value)
        guard status == noErr else { throw StreamError.encoder("setting \(key) returned \(status)") }
    }

    fileprivate func handle(status: OSStatus, flags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) {
        guard status == noErr, !flags.contains(.frameDropped), let sampleBuffer,
              CMSampleBufferDataIsReady(sampleBuffer), let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            if status != noErr { output(.failure(StreamError.encoder("callback returned \(status)"))) }; return
        }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let keyFrame = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool != true
        let total = CMBlockBufferGetDataLength(block)
        guard total > 0 else { output(.failure(StreamError.encoder("encoded access unit is empty"))); return }
        var encodedBytes = Data(count: total)
        let blockStatus = encodedBytes.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return OSStatus(-1) }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: total, destination: baseAddress)
        }
        guard blockStatus == noErr else { output(.failure(StreamError.encoder("cannot copy encoded bytes"))); return }
        do {
            var data = Data()
            var nalLengthSize = 4
            if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var count = 0; var nalLength: Int32 = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: 0, parameterSetPointerOut: nil,
                    parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: &nalLength)
                nalLengthSize = Int(nalLength)
                if keyFrame {
                    for index in 0..<count {
                        var bytes: UnsafePointer<UInt8>?; var size = 0
                        let s = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, parameterSetIndex: index,
                            parameterSetPointerOut: &bytes, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                        if s == noErr, let bytes { data.append(contentsOf: [0,0,0,1]); data.append(bytes, count: size) }
                    }
                }
            }
            data.append(try AnnexBConverter.convertAVCC(encodedBytes, nalLengthSize: nalLengthSize))
            output(.success(.init(data: data, isKeyFrame: keyFrame, presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))))
        } catch { output(.failure(error)) }
    }
}

private let encoderCallback: VTCompressionOutputCallback = { refcon, _, status, flags, sampleBuffer in
    guard let refcon else { return }
    Unmanaged<H264Encoder>.fromOpaque(refcon).takeUnretainedValue().handle(status: status, flags: flags, sampleBuffer: sampleBuffer)
}
