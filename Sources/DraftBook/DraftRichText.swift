import AppKit
import DraftBookCore
import Foundation
import Markdown

/// Turns a draft into rich content for the clipboard: RTF and HTML with the
/// images embedded, plus the original Markdown as plain text. Pasting into
/// Feishu, Word or Mail therefore keeps both the layout and the pictures, while
/// pasting into a code editor still yields the raw syntax.
@MainActor
enum DraftRichText {
    static let maxImageWidth: CGFloat = 420

    static func copy(_ draft: Draft, store: DraftStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let attributed = attributedString(
            for: draft.content,
            attachmentDirectory: store.attachmentsDirectoryURL
        )
        let item = NSPasteboardItem()
        item.setString(draft.content, forType: .string)

        if let rtf = rtfData(from: attributed) {
            item.setData(rtf, forType: .rtf)
        }
        if let html = htmlString(
            for: draft.content,
            attachmentDirectory: store.attachmentsDirectoryURL
        ) {
            item.setData(Data(html.utf8), forType: .html)
        }

        pasteboard.writeObjects([item])
        store.markCopied(id: draft.id)
    }

    // MARK: - Attributed string (RTF)

    static func attributedString(
        for source: String,
        attachmentDirectory: URL
    ) -> NSAttributedString {
        let document = MarkdownDraftPreview.document(for: source)
        let output = NSMutableAttributedString()

        for block in document.children {
            output.append(blockString(block, directory: attachmentDirectory, depth: 0))
        }

        if output.length > 0 {
            output.deleteCharacters(in: NSRange(location: output.length - 2, length: 2))
        }
        return output
    }

    private static func blockString(
        _ node: any Markup,
        directory: URL,
        depth: Int
    ) -> NSAttributedString {
        switch node {
        case let heading as Heading:
            let size = CGFloat(max(15, 26 - heading.level * 2))
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 3
            paragraph.paragraphSpacing = 10
            let text = NSMutableAttributedString(
                attributedString: inlineString(heading, directory: directory, bold: true, size: size)
            )
            text.append(NSAttributedString(string: "\n\n", attributes: [.paragraphStyle: paragraph]))
            return text

        case let paragraph as Paragraph:
            if let image = MarkdownDraftPreview.imageOnlyParagraph(paragraph),
               let attachment = attachmentString(
                forSource: image.source,
                directory: directory
               ) {
                return attachment
            }
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            style.paragraphSpacing = 10
            let text = NSMutableAttributedString(
                attributedString: inlineString(paragraph, directory: directory)
            )
            text.append(NSAttributedString(string: "\n\n", attributes: [.paragraphStyle: style]))
            return text

        case let quote as BlockQuote:
            let inner = NSMutableAttributedString()
            for child in quote.children {
                inner.append(blockString(child, directory: directory, depth: depth + 1))
            }
            inner.addAttribute(
                .foregroundColor,
                value: NSColor.secondaryLabelColor,
                range: NSRange(location: 0, length: inner.length)
            )
            return inner

        case let list as OrderedList:
            return listString(list, directory: directory, start: Int(list.startIndex))
        case let list as UnorderedList:
            return listString(list, directory: directory, start: nil)

        case let code as CodeBlock:
            let body = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            return NSAttributedString(
                string: "\(body)\n\n",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.1)
                ]
            )

        case is ThematicBreak:
            return NSAttributedString(string: "———\n\n")

        case let table as Markdown.Table:
            var rows: [String] = []
            for row in [table.head] + Array(table.body.children) {
                rows.append(row.children.map { plainText($0) }.joined(separator: "  |  "))
            }
            return NSAttributedString(string: rows.joined(separator: "\n") + "\n\n")

        case let html as HTMLBlock:
            return NSAttributedString(string: html.rawHTML + "\n\n")

        default:
            let fallback = NSMutableAttributedString()
            for child in node.children {
                fallback.append(blockString(child, directory: directory, depth: depth))
            }
            return fallback
        }
    }

    private static func listString(
        _ node: any Markup,
        directory: URL,
        start: Int?
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in Array(node.children).enumerated() {
            let marker = start.map { "\($0 + index). " } ?? "• "
            result.append(NSAttributedString(string: marker))
            let body = NSMutableAttributedString()
            for child in item.children {
                body.append(blockString(child, directory: directory, depth: 1))
            }
            if body.string.hasSuffix("\n\n") {
                body.deleteCharacters(in: NSRange(location: body.length - 2, length: 2))
            }
            result.append(body)
            result.append(NSAttributedString(string: "\n"))
        }
        result.append(NSAttributedString(string: "\n"))
        return result
    }

    private static func inlineString(
        _ node: any Markup,
        directory: URL,
        bold: Bool = false,
        italic: Bool = false,
        size: CGFloat = 14
    ) -> NSAttributedString {
        if let text = node as? Markdown.Text {
            return styled(text.string, bold: bold, italic: italic, size: size)
        }
        if node is SoftBreak || node is LineBreak {
            return styled(" ", bold: bold, italic: italic, size: size)
        }
        if let code = node as? InlineCode {
            return NSAttributedString(
                string: code.code,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                    .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.12)
                ]
            )
        }
        if let image = node as? Markdown.Image {
            if let attachment = attachmentString(forSource: image.source, directory: directory) {
                return attachment
            }
            return styled("[图片：\(plainText(image))]", bold: bold, italic: italic, size: size)
        }

        let result = NSMutableAttributedString()
        for child in node.children {
            result.append(inlineString(
                child,
                directory: directory,
                bold: bold || node is Strong,
                italic: italic || node is Emphasis,
                size: size
            ))
        }
        if let link = node as? Markdown.Link,
           let destination = link.destination,
           let url = URL(string: destination) {
            result.addAttribute(
                .link,
                value: url,
                range: NSRange(location: 0, length: result.length)
            )
        }
        return result
    }

    private static func styled(
        _ string: String,
        bold: Bool,
        italic: Bool,
        size: CGFloat
    ) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor
        ]
        if italic { attributes[.obliqueness] = 0.22 }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private static func attachmentString(
        forSource source: String?,
        directory: URL
    ) -> NSAttributedString? {
        guard let source, !source.isEmpty else { return nil }
        let decoded = source.removingPercentEncoding ?? source
        let name = (decoded as NSString).lastPathComponent
        let url = directory.appendingPathComponent(name, isDirectory: false)

        guard let image = AttachmentImageCache.shared.image(for: url, maxPixelSize: 1600),
              image.size.width > 0, image.size.height > 0 else {
            return NSAttributedString(string: "[图片缺失：\(name)]\n\n")
        }

        let ratio = min(1, maxImageWidth / image.size.width)
        let size = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: size)

        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            attachment.fileWrapper = FileWrapper(regularFileWithContents: png)
            attachment.fileWrapper?.preferredFilename = name
        }

        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "\n\n"))
        return result
    }

    private static func rtfData(from attributed: NSAttributedString) -> Data? {
        guard attributed.length > 0 else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    // MARK: - HTML

    static func htmlString(for source: String, attachmentDirectory: URL) -> String? {
        let document = MarkdownDraftPreview.document(for: source)
        var body = ""
        for block in document.children {
            body += htmlBlock(block, directory: attachmentDirectory)
        }
        guard !body.isEmpty else { return nil }
        return """
        <div style="font-family:-apple-system,'PingFang SC',sans-serif;font-size:14px;line-height:1.75;color:#1b1b1f">
        \(body)
        </div>
        """
    }

    private static func htmlBlock(_ node: any Markup, directory: URL) -> String {
        switch node {
        case let heading as Heading:
            let size = 26 - heading.level * 2
            return "<h\(heading.level) style=\"font-size:\(max(size, 15))px;margin:18px 0 8px\">"
                + htmlInline(heading, directory: directory) + "</h\(heading.level)>"

        case let paragraph as Paragraph:
            if let image = MarkdownDraftPreview.imageOnlyParagraph(paragraph),
               let tag = htmlImage(forSource: image.source, directory: directory) {
                return tag
            }
            return "<p style=\"margin:0 0 12px\">" + htmlInline(paragraph, directory: directory) + "</p>"

        case let quote as BlockQuote:
            let inner = quote.children.map { htmlBlock($0, directory: directory) }.joined()
            return "<blockquote style=\"margin:0 0 12px;padding-left:12px;border-left:3px solid #d8d1c2;color:#555\">\(inner)</blockquote>"

        case let list as UnorderedList:
            return "<ul style=\"margin:0 0 12px;padding-left:22px\">"
                + list.children.map { "<li>" + $0.children.map { htmlBlock($0, directory: directory) }.joined() + "</li>" }.joined()
                + "</ul>"

        case let list as OrderedList:
            return "<ol start=\"\(list.startIndex)\" style=\"margin:0 0 12px;padding-left:22px\">"
                + list.children.map { "<li>" + $0.children.map { htmlBlock($0, directory: directory) }.joined() + "</li>" }.joined()
                + "</ol>"

        case let code as CodeBlock:
            let escaped = escape(code.code)
            return "<pre style=\"background:#f4f2ed;padding:10px;border-radius:5px;font-size:13px;overflow:auto\"><code>\(escaped)</code></pre>"

        case is ThematicBreak:
            return "<hr style=\"border:none;border-top:1px solid #ddd;margin:16px 0\">"

        case let html as HTMLBlock:
            return html.rawHTML

        default:
            return node.children.map { htmlBlock($0, directory: directory) }.joined()
        }
    }

    private static func htmlInline(_ node: any Markup, directory: URL) -> String {
        if let text = node as? Markdown.Text {
            return escape(text.string)
        }
        if node is SoftBreak || node is LineBreak {
            return "<br>"
        }
        if let code = node as? InlineCode {
            return "<code style=\"background:#f1efe9;padding:1px 4px;border-radius:3px;font-size:13px\">"
                + escape(code.code) + "</code>"
        }
        if let image = node as? Markdown.Image {
            return htmlImage(forSource: image.source, directory: directory)
                ?? escape("[图片：\(plainText(image))]")
        }

        let inner = node.children.map { htmlInline($0, directory: directory) }.joined()
        if node is Strong { return "<strong>\(inner)</strong>" }
        if node is Emphasis { return "<em>\(inner)</em>" }
        if let link = node as? Markdown.Link, let destination = link.destination {
            return "<a href=\"\(escape(destination))\">\(inner)</a>"
        }
        return inner
    }

    private static func htmlImage(forSource source: String?, directory: URL) -> String? {
        guard let source, !source.isEmpty else { return nil }
        let decoded = source.removingPercentEncoding ?? source
        let name = (decoded as NSString).lastPathComponent
        let url = directory.appendingPathComponent(name, isDirectory: false)

        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return "<p style=\"color:#888\">[图片缺失：\(escape(name))]</p>"
        }

        return "<p style=\"margin:0 0 12px\"><img src=\"data:image/png;base64,\(png.base64EncodedString())\" style=\"max-width:100%;border-radius:6px\"></p>"
    }

    private static func plainText(_ node: any Markup) -> String {
        if let text = node as? Markdown.Text { return text.string }
        if let code = node as? InlineCode { return code.code }
        if node is SoftBreak || node is LineBreak { return " " }
        return node.children.map { plainText($0) }.joined()
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
