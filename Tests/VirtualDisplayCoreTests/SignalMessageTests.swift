import Foundation
import Testing
@testable import VirtualDisplayCore

@Test func signalRoundTrip() throws {
    let original = SignalMessage(type: .candidate, candidate: "candidate:1 1 UDP 1 192.168.1.2 5000 typ host",
                                 sdpMid: "0", sdpMLineIndex: 0)
    #expect(try SignalMessage.decode(original.encoded()) == original)
}

@Test func acceptsAnswer() throws {
    let value = try SignalMessage.decode(#"{"type":"answer","sdp":"v=0\\r\\n"}"#)
    #expect(value.type == .answer)
}

@Test func stateUsesValueField() throws {
    let text = try SignalMessage(type: .state, value: "connected").encoded()
    #expect(text.contains(#""value":"connected""#))
    #expect(!text.contains(#""state":"#))
}

@Test(arguments: [
    #"{"type":"answer"}"#,
    #"{"type":"candidate","candidate":"abc"}"#,
    #"{"type":"offer","sdp":"v=0"}"#,
    #"{"type":"answer","sdp":"v=0","unexpected":true}"#,
    #"[]"#,
])
func rejectsInvalidSignal(_ text: String) {
    #expect(throws: Error.self) { try SignalMessage.decode(text) }
}
