import Foundation

/// Response from the backend `song/:isrc/lyrics` endpoint (proxied LRCLib).
struct LyricsResponse: Codable {
    var plainLyrics: String?
    var syncedLyrics: String?
}

/// A single timestamped line of synced lyrics.
struct LyricLine: Identifiable {
    let id = UUID()
    let time: Double  // seconds from start
    let text: String
}

/// Parse an LRC-format string (`[mm:ss.xx] text`) into sorted lyric lines.
/// Tolerates multiple timestamps per line, blank lines, and metadata tags.
func parseLRC(_ synced: String) -> [LyricLine] {
    var lines: [LyricLine] = []

    // Matches one timestamp like [01:23.45] or [01:23]
    let timeTag = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    guard let timeTag else { return [] }

    for raw in synced.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = timeTag.matches(in: line, range: range)
        guard !matches.isEmpty, let last = matches.last else { continue }

        // Text is whatever follows the final timestamp on this line.
        let textStart = line.index(line.startIndex, offsetBy: last.range.location + last.range.length)
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespaces)
        if text.isEmpty { continue }

        for match in matches {
            guard
                let minRange = Range(match.range(at: 1), in: line),
                let secRange = Range(match.range(at: 2), in: line),
                let minutes = Double(line[minRange]),
                let seconds = Double(line[secRange])
            else { continue }

            var fraction = 0.0
            if let fracRange = Range(match.range(at: 3), in: line), let frac = Double(line[fracRange]) {
                // Normalize 2- or 3-digit fractions (".45" -> 0.45, ".450" -> 0.450)
                fraction = frac / pow(10.0, Double(line[fracRange].count))
            }

            lines.append(LyricLine(time: minutes * 60 + seconds + fraction, text: text))
        }
    }

    return lines.sorted { $0.time < $1.time }
}
