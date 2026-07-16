enum SDPTransform {
    /// Mirrors Deskreen's SDP transform: advertise an effectively unrestricted
    /// LAN video bandwidth while preserving unrelated bandwidth modifiers.
    static func settingVideoBandwidth(_ sdp: String, kilobitsPerSecond: Int) -> String {
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: separator)
        guard let mediaIndex = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else { return sdp }

        var bandwidthIndex = mediaIndex + 1
        while bandwidthIndex < lines.count,
              lines[bandwidthIndex].hasPrefix("i=") || lines[bandwidthIndex].hasPrefix("c=") {
            bandwidthIndex += 1
        }

        let firstBandwidthIndex = bandwidthIndex
        while bandwidthIndex < lines.count, lines[bandwidthIndex].hasPrefix("b=") {
            bandwidthIndex += 1
        }

        let bandwidth = "b=AS:\(kilobitsPerSecond)"
        if let existingIndex = lines[firstBandwidthIndex..<bandwidthIndex]
            .firstIndex(where: { $0.hasPrefix("b=AS:") }) {
            lines[existingIndex] = bandwidth
        } else {
            lines.insert(bandwidth, at: firstBandwidthIndex)
        }
        return lines.joined(separator: separator)
    }

    /// Matches Deskreen's usual Chromium negotiation by preferring VP8 while
    /// preserving the relative order of every payload inside each partition.
    static func preferringVP8(_ sdp: String) -> String {
        let separator = sdp.contains("\r\n") ? "\r\n" : "\n"
        var lines = sdp.components(separatedBy: separator)
        guard let mediaIndex = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else { return sdp }
        let sectionEnd = lines[(mediaIndex + 1)...].firstIndex(where: { $0.hasPrefix("m=") }) ?? lines.endIndex

        let rtpMapPrefix = "a=rtpmap:"
        var vp8Payloads = Set<String>()
        for line in lines[(mediaIndex + 1)..<sectionEnd] where line.hasPrefix(rtpMapPrefix) {
            let mapping = line.dropFirst(rtpMapPrefix.count)
            let parts = mapping.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { continue }
            let payload = String(parts[0])
            let codec = parts[1].split(separator: "/", maxSplits: 1).first
            if codec?.uppercased() == "VP8" { vp8Payloads.insert(payload) }
        }
        guard !vp8Payloads.isEmpty else { return sdp }

        var media = lines[mediaIndex].split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard media.count > 3 else { return sdp }
        let payloads = Array(media.dropFirst(3))
        let preferred = payloads.filter(vp8Payloads.contains)
        guard !preferred.isEmpty else { return sdp }
        media = Array(media.prefix(3)) + preferred + payloads.filter { !vp8Payloads.contains($0) }
        lines[mediaIndex] = media.joined(separator: " ")
        return lines.joined(separator: separator)
    }
}
