import Foundation

public struct SignalMessage: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case offer, answer, candidate, state, error }

    public let type: Kind
    public let sdp: String?
    public let candidate: String?
    public let sdpMid: String?
    public let sdpMLineIndex: Int32?
    public let value: String?
    public let message: String?

    public init(type: Kind, sdp: String? = nil, candidate: String? = nil,
                sdpMid: String? = nil, sdpMLineIndex: Int32? = nil,
                value: String? = nil, message: String? = nil) {
        self.type = type; self.sdp = sdp; self.candidate = candidate
        self.sdpMid = sdpMid; self.sdpMLineIndex = sdpMLineIndex
        self.value = value; self.message = message
    }

    public static func decode(_ text: String) throws -> SignalMessage {
        guard let data = text.data(using: .utf8), data.count <= 64 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StreamError.signaling("message must be a JSON object no larger than 64 KiB")
        }
        let allowed = Set(["type", "sdp", "candidate", "sdpMid", "sdpMLineIndex", "value", "message"])
        guard Set(object.keys).isSubset(of: allowed) else { throw StreamError.signaling("message contains unknown fields") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        switch value.type {
        case .answer:
            guard let sdp = value.sdp, !sdp.isEmpty else { throw StreamError.signaling("answer requires sdp") }
        case .candidate:
            guard let candidate = value.candidate, !candidate.isEmpty,
                  value.sdpMLineIndex != nil else { throw StreamError.signaling("candidate requires candidate and sdpMLineIndex") }
        case .offer:
            throw StreamError.signaling("the browser cannot send an offer")
        case .state, .error:
            throw StreamError.signaling("the browser cannot send \(value.type.rawValue)")
        }
        return value
    }

    public func encoded() throws -> String {
        guard let text = String(data: try JSONEncoder().encode(self), encoding: .utf8) else {
            throw StreamError.signaling("could not encode message")
        }
        return text
    }
}
