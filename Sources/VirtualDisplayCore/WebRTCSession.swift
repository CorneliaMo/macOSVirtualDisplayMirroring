import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import WebRTC

public final class WebRTCSession: NSObject, @unchecked Sendable {
    public typealias SignalHandler = @Sendable (SignalMessage) -> Void

    private let queue = DispatchQueue(label: "VirtualDisplayStream.webrtc")
    private let factory: RTCPeerConnectionFactory
    private let source: RTCVideoSource
    private let capturer: RTCVideoCapturer
    private let signal: SignalHandler
    private let bitrate: Int
    private let frames = LatestValueMailbox<PendingFrame>()
    private var peer: RTCPeerConnection?
    private var pendingCandidates: [RTCIceCandidate] = []
    private var remoteDescriptionSet = false

    public init(width: Int, height: Int, fps: Int, bitrate: Int, signal: @escaping SignalHandler) {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
        let videoSource = factory.videoSource(forScreenCast: true)
        source = videoSource
        capturer = RTCVideoCapturer(delegate: videoSource)
        self.bitrate = bitrate
        self.signal = signal
        super.init()
        videoSource.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: Int32(fps))
    }

    deinit { RTCCleanupSSL() }

    public func start() {
        queue.async { self.createPeerAndOffer() }
    }

    public func receive(_ message: SignalMessage) {
        queue.async {
            guard let peer = self.peer else { return }
            switch message.type {
            case .answer:
                let description = RTCSessionDescription(type: .answer, sdp: message.sdp!)
                peer.setRemoteDescription(description) { error in
                    self.queue.async {
                        guard self.peer === peer else { return }
                        if let error { self.fail(error.localizedDescription); return }
                        self.remoteDescriptionSet = true
                        let candidates = self.pendingCandidates; self.pendingCandidates.removeAll()
                        candidates.forEach { self.add($0, to: peer) }
                    }
                }
            case .candidate:
                let candidate = RTCIceCandidate(sdp: message.candidate!, sdpMLineIndex: message.sdpMLineIndex!, sdpMid: message.sdpMid)
                if self.remoteDescriptionSet { self.add(candidate, to: peer) } else { self.pendingCandidates.append(candidate) }
            default: break
            }
        }
    }

    public func push(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard frames.offer(PendingFrame(pixelBuffer, presentationTime)) else { return }
        queue.async { self.drainLatestFrame() }
    }

    public func stop() {
        frames.deactivateAndClear()
        queue.sync { self.peer?.close(); self.peer = nil; self.pendingCandidates.removeAll(); self.remoteDescriptionSet = false }
    }

    private func createPeerAndOffer() {
        frames.deactivateAndClear()
        peer?.close(); pendingCandidates.removeAll(); remoteDescriptionSet = false
        let configuration = RTCConfiguration()
        configuration.iceServers = []
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
            fail("peer connection creation failed")
            return
        }
        self.peer = peer
        let track = factory.videoTrack(with: source, trackId: "virtual-display-video")
        guard let sender = peer.add(track, streamIds: ["virtual-display"]) else {
            peer.close()
            self.peer = nil
            fail("video sender creation failed")
            return
        }
        frames.activate()
        let parameters = sender.parameters
        parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
        if let encoding = parameters.encodings.first {
            encoding.scaleResolutionDownBy = NSNumber(value: 1.0)
            encoding.maxBitrateBps = NSNumber(value: bitrate)
        }
        sender.parameters = parameters
        peer.offer(for: constraints) { description, error in
            self.queue.async {
                guard self.peer === peer else { return }
                guard let description else { self.fail(error?.localizedDescription ?? "offer creation failed"); return }
                peer.setLocalDescription(description) { error in
                    self.queue.async {
                        guard self.peer === peer else { return }
                        if let error { self.fail(error.localizedDescription); return }
                        self.signal(.init(type: .offer, sdp: description.sdp))
                    }
                }
            }
        }
    }

    private func add(_ candidate: RTCIceCandidate, to peer: RTCPeerConnection) {
        peer.add(candidate) { error in
            guard let error else { return }
            self.queue.async {
                guard self.peer === peer else { return }
                self.fail("ICE candidate rejected: \(error.localizedDescription)")
            }
        }
    }

    private func drainLatestFrame() {
        if let pending = frames.take(), peer != nil {
            let seconds = CMTimeGetSeconds(pending.presentationTime)
            let timestamp = seconds.isFinite && seconds >= 0
                ? Int64(seconds * 1_000_000_000)
                : Int64(DispatchTime.now().uptimeNanoseconds)
            let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pending.pixelBuffer),
                                      rotation: ._0, timeStampNs: timestamp)
            source.capturer(capturer, didCapture: frame)
        }
        if frames.finishDrain() { queue.async { self.drainLatestFrame() } }
    }

    private func fail(_ message: String) { signal(.init(type: .error, message: message)) }
}

extension WebRTCSession: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let value: String
        switch newState {
        case .new: value = "new"
        case .checking: value = "checking"
        case .connected: value = "connected"
        case .completed: value = "connected"
        case .failed: value = "failed"
        case .disconnected: value = "disconnected"
        case .closed: value = "closed"
        case .count: return
        @unknown default: return
        }
        queue.async {
            guard self.peer === peerConnection else { return }
            self.signal(.init(type: .state, value: value))
        }
    }
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        queue.async {
            guard self.peer === peerConnection else { return }
            self.signal(.init(type: .candidate, candidate: candidate.sdp, sdpMid: candidate.sdpMid,
                              sdpMLineIndex: candidate.sdpMLineIndex))
        }
    }
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

private final class PendingFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    init(_ pixelBuffer: CVPixelBuffer, _ presentationTime: CMTime) {
        self.pixelBuffer = pixelBuffer
        self.presentationTime = presentationTime
    }
}
