import Foundation

struct Chapter: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let start: Double
    var end: Double
}

enum ChapterParser {
    static func parseDuration(_ iso: String) -> Double {
        guard let regex = try? NSRegularExpression(pattern: #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?"#),
              let match = regex.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)) else {
            return 0
        }
        func group(_ index: Int) -> Double {
            guard let range = Range(match.range(at: index), in: iso) else { return 0 }
            return Double(iso[range]) ?? 0
        }
        return group(1) * 3600 + group(2) * 60 + group(3)
    }

    static func parseChapters(description: String, duration: Double) -> [Chapter] {
        let lines = description.components(separatedBy: "\n")
        guard let regex = try? NSRegularExpression(pattern: #"(?:(\d{1,2}):)?(\d{1,2}):(\d{2})"#) else {
            return []
        }

        struct Found { let start: Double; let title: String }
        var found: [Found] = []

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let matchRange = Range(match.range, in: line) else { continue }

            func group(_ index: Int) -> Double {
                guard let r = Range(match.range(at: index), in: line) else { return 0 }
                return Double(line[r]) ?? 0
            }
            let start = group(1) * 3600 + group(2) * 60 + group(3)

            var title = line
            title.removeSubrange(matchRange)
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "-\u{2013}\u{2014}:. "))
            if title.isEmpty { title = "Chapter \(found.count + 1)" }
            found.append(Found(start: start, title: title))
        }

        found.sort { $0.start < $1.start }
        var deduped: [Found] = []
        for f in found {
            if let last = deduped.last, last.start == f.start { continue }
            deduped.append(f)
        }
        guard deduped.count >= 2 else { return [] }

        var chapters: [Chapter] = []
        for (i, f) in deduped.enumerated() {
            let end = i + 1 < deduped.count ? deduped[i + 1].start : (duration > 0 ? duration : f.start)
            chapters.append(Chapter(title: f.title, start: f.start, end: end))
        }
        return chapters
    }

    static func formatTime(_ totalSeconds: Double) -> String {
        let s = max(0, Int(totalSeconds.rounded()))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}
