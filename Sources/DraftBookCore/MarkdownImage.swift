import Foundation

/// Pure text helpers for image references. Drafts store plain Markdown, so all
/// of this stays testable without touching AppKit.
public enum MarkdownImage {
    public static let defaultAlt = "图片"

    public static func reference(forRelativePath path: String, alt: String = defaultAlt) -> String {
        let escaped = path.replacingOccurrences(of: " ", with: "%20")
        return "![\(alt)](\(escaped))"
    }

    public struct Insertion: Equatable {
        public let range: NSRange
        public let text: String
        /// Caret position after applying the insertion.
        public let caretLocation: Int
    }

    /// Images occupy their own paragraph. Markdown needs a blank line to end a
    /// paragraph, so a single newline would leave the image glued to the text
    /// above it as a soft break; the insert adds as many newlines as needed and
    /// never more.
    public static func insertion(
        forReference reference: String,
        in content: String,
        selection: NSRange
    ) -> Insertion {
        let ns = content as NSString
        let location = min(max(selection.location, 0), ns.length)
        let length = min(max(selection.length, 0), ns.length - location)
        let range = NSRange(location: location, length: length)

        let before = ns.substring(to: location)
        let after = ns.substring(from: location + length)

        let leading: String
        if before.isEmpty || before.hasSuffix("\n\n") {
            leading = ""
        } else if before.hasSuffix("\n") {
            leading = "\n"
        } else {
            leading = "\n\n"
        }

        let trailing: String
        if after.isEmpty || after.hasPrefix("\n\n") {
            trailing = ""
        } else if after.hasPrefix("\n") {
            trailing = "\n"
        } else {
            trailing = "\n\n"
        }

        let text = leading + reference + trailing
        let caret = location + (text as NSString).length
        return Insertion(range: range, text: text, caretLocation: caret)
    }

    /// File names referenced as `Attachments/…` anywhere in the text.
    public static func referencedFileNames(in content: String) -> Set<String> {
        let pattern = #"!\[[^\]]*\]\(\s*<?([^)>\s]+)>?(?:\s+"[^"]*")?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = content as NSString
        var names: Set<String> = []

        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let destination = ns.substring(with: match.range(at: 1))
            let decoded = destination.removingPercentEncoding ?? destination
            guard decoded.hasPrefix(AttachmentStore.directoryName + "/") else { continue }
            let name = (decoded as NSString).lastPathComponent
            if !name.isEmpty { names.insert(name) }
        }
        return names
    }
}
