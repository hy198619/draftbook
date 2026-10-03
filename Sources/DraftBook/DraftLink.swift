import AppKit
import Foundation

/// Links are presentation metadata only. Draft contents remain unchanged plain text.
enum DraftLink {
    struct Match {
        let range: NSRange
        let url: URL
    }

    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    private static let fileURLPattern = try! NSRegularExpression(
        pattern: #"(?<!\S)file://[^\s<>]+"#, options: [.caseInsensitive]
    )
    private static let pathPattern = try! NSRegularExpression(
        pattern: #"(?<!\S)(?:~/|/(?!/))[^\r\n<>]+"#
    )
    private static let trailingPunctuation = CharacterSet(
        charactersIn: ".,;:!?)]}，。；：！？）】"
    )

    static func markdownDestination(_ destination: String?) -> URL? {
        guard let destination, !destination.isEmpty else { return nil }
        if destination.hasPrefix("/") || destination.hasPrefix("~/") {
            return localPath(destination)
        }
        if destination.lowercased().hasPrefix("www.") {
            return webURL("https://" + destination)
        }
        if destination.lowercased().hasPrefix("file://") {
            return fileURL(destination)
        }
        return webURL(destination)
    }

    static func detect(in text: String) -> [Match] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        var candidates: [Match] = []

        for result in detector?.matches(in: text, range: range) ?? [] {
            let raw = (text as NSString).substring(with: result.range)
            let url = raw.lowercased().hasPrefix("www.")
                ? webURL("https://" + raw)
                : result.url.flatMap { webURL($0.absoluteString) }
            if let url { candidates.append(Match(range: result.range, url: url)) }
        }

        for result in fileURLPattern.matches(in: text, range: range) {
            if let match = trimmedLocalMatch(in: text, range: result.range, resolver: fileURL) {
                candidates.append(match)
            }
        }
        for result in pathPattern.matches(in: text, range: range) {
            if let match = trimmedLocalMatch(in: text, range: result.range, resolver: localPath) {
                candidates.append(match)
            }
        }

        // A text run must never receive two destinations over the same characters.
        var accepted: [Match] = []
        for candidate in candidates.sorted(by: { $0.range.location < $1.range.location }) {
            if !accepted.contains(where: { NSIntersectionRange($0.range, candidate.range).length > 0 }) {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    static func needsOpenConfirmation(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let riskyExtensions: Set<String> = ["app", "command", "tool", "sh", "scpt", "applescript", "workflow"]
        if riskyExtensions.contains(url.pathExtension.lowercased()) { return true }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true && FileManager.default.isExecutableFile(atPath: url.path)
    }

    private static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private static func fileURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.isFileURL,
              url.host == nil || url.host?.lowercased() == "localhost",
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func localPath(_ string: String) -> URL? {
        let path = (string as NSString).expandingTildeInPath
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func trimmedLocalMatch(
        in text: String,
        range: NSRange,
        resolver: (String) -> URL?
    ) -> Match? {
        var raw = (text as NSString).substring(with: range)
        var length = range.length
        while !raw.isEmpty {
            if let url = resolver(raw) {
                return Match(range: NSRange(location: range.location, length: length), url: url)
            }
            if let last = raw.unicodeScalars.last, trailingPunctuation.contains(last) {
                raw.removeLast()
            } else if let split = raw.lastIndex(where: { $0.isWhitespace || "，。；：！？）】".contains($0) }) {
                raw = String(raw[..<split])
            } else {
                break
            }
            length = (raw as NSString).length
        }
        return nil
    }
}
