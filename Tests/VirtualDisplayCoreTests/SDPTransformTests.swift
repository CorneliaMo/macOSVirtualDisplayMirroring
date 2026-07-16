import Testing
@testable import VirtualDisplayCore

@Test func insertsVideoBandwidthAfterConnectionLineAndPreservesCRLF() {
    let input = "v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96 97 98\r\nc=IN IP4 0.0.0.0\r\na=rtpmap:96 VP8/90000\r\n"
    let output = SDPTransform.settingVideoBandwidth(input, kilobitsPerSecond: 500_000)
    #expect(output == "v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96 97 98\r\nc=IN IP4 0.0.0.0\r\nb=AS:500000\r\na=rtpmap:96 VP8/90000\r\n")
}

@Test func replacesExistingBandwidth() {
    let input = "m=video 9 RTP/AVP 96\ni=display\nc=IN IP4 0.0.0.0\nb=TIAS:12000\na=rtpmap:96 VP8/90000"
    #expect(SDPTransform.settingVideoBandwidth(input, kilobitsPerSecond: 500_000).contains("c=IN IP4 0.0.0.0\nb=AS:500000\nb=TIAS:12000\na=rtpmap"))
}

@Test func replacesOnlyASAndPreservesOtherBandwidthModifiers() {
    let input = "m=video 9 RTP/AVP 96\r\nc=IN IP4 0.0.0.0\r\nb=CT:2000\r\nb=AS:12000\r\na=rtpmap:96 VP8/90000"
    let output = SDPTransform.settingVideoBandwidth(input, kilobitsPerSecond: 500_000)
    #expect(output.contains("b=CT:2000\r\nb=AS:500000\r\n"))
    #expect(!output.contains("b=AS:12000"))
}

@Test func leavesSdpWithoutVideoUnchanged() {
    let input = "v=0\r\nm=audio 9 RTP/AVP 0\r\n"
    #expect(SDPTransform.settingVideoBandwidth(input, kilobitsPerSecond: 500_000) == input)
}

@Test func prefersEveryVP8PayloadAndKeepsOtherPayloadsStable() {
    let input = "m=video 9 UDP/TLS/RTP/SAVPF 102 98 96 121 97\r\n" +
        "a=rtpmap:102 H264/90000\r\na=rtpmap:98 VP9/90000\r\n" +
        "a=rtpmap:96 VP8/90000\r\na=rtpmap:121 vp8/90000\r\na=rtpmap:97 rtx/90000\r\n"
    let output = SDPTransform.preferringVP8(input)
    #expect(output.hasPrefix("m=video 9 UDP/TLS/RTP/SAVPF 96 121 102 98 97\r\n"))
}

@Test func doesNotUseAudioCodecMappingsWhenReorderingVideo() {
    let input = "m=audio 9 RTP/AVP 96\r\na=rtpmap:96 VP8/90000\r\n" +
        "m=video 9 RTP/AVP 102 98\r\na=rtpmap:102 H264/90000\r\na=rtpmap:98 VP9/90000"
    #expect(SDPTransform.preferringVP8(input) == input)
}
