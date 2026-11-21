import AppKit
import Markdown
import SwiftUI

/// CommonMark parsing is delegated to cmark through Swift Markdown. Soft breaks
/// are displayed as newlines, a CommonMark-permitted presentation choice.
struct MarkdownDraftPreview: View {
    let source: String
    var attachmentDirectory: URL? = nil
    var onEdit: () -> Void = {}

    var body: some View {
        blocks(Self.document(for: source))
            .font(.system(size: 14))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// DraftBook treats block quotes as explicit, line-prefixed blocks. CommonMark
    /// otherwise permits an unprefixed line to lazily continue the quote paragraph,
    /// which makes the line after `> 引用` look quoted until the user inserts a
    /// blank line. Add that block boundary only for rendering and keep the stored
    /// source untouched.
    static func document(for source: String) -> Document {
        Document(parsing: sourceWithExplicitBlockQuoteBoundaries(source), options: [.disableSmartOpts])
    }

    static func sourceWithExplicitBlockQuoteBoundaries(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        guard lines.count > 1 else { return source }

        var result: [String] = []
        result.reserveCapacity(lines.count)
        var previousLineWasExplicitQuote = false

        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isExplicitQuote = lineIsExplicitBlockQuote(line)
            if previousLineWasExplicitQuote, !isBlank, !isExplicitQuote {
                result.append("")
            }
            result.append(line)
            previousLineWasExplicitQuote = isExplicitQuote
        }

        return result.joined(separator: "\n")
    }

    /// v1 only promotes images that sit alone in a paragraph; an image mixed
    /// with text keeps the literal fallback so inline flow stays untouched.
    static func imageOnlyParagraph(_ paragraph: Paragraph) -> Markdown.Image? {
        let meaningful = paragraph.children.filter { child in
            if let text = child as? Markdown.Text {
                return !text.string.trimmingCharacters(in: .whitespaces).isEmpty
            }
            return true
        }
        guard meaningful.count == 1, let image = meaningful.first as? Markdown.Image else {
            return nil
        }
        return image
    }

    /// A line that holds a picture, or a line of text.
    enum PreviewLine {
        case text([any Markup])
        case image(source: String)
    }

    /// CommonMark ends a paragraph on a *blank* line, so a caption typed on the
    /// next line keeps itself and the image in one paragraph, and the picture
    /// would fall back to literal `[图片：…](…)` text. The product promise is a
    /// picture alone on its line, so split the paragraph on soft breaks and
    /// promote any such line. Returns nil when no line is image-shaped, leaving
    /// genuine inline flow untouched.
    static func previewLines(of paragraph: Paragraph) -> [PreviewLine]? {
        var lines: [[any Markup]] = [[]]
        for child in Array(paragraph.children) {
            if child is SoftBreak || child is LineBreak {
                lines.append([])
                continue
            }
            lines[lines.count - 1].append(child)
        }

        let mapped: [PreviewLine] = lines.flatMap { nodes -> [PreviewLine] in
            let meaningful = nodes.filter { !isBlankText($0) }
            if meaningful.count == 1, let image = meaningful.first as? Markdown.Image {
                return [.image(source: image.source ?? "")]
            }
            return splitLeadingImage(nodes) ?? [.text(nodes)]
        }

        let hasImageLine = mapped.contains { line in
            if case .image = line { return true }
            return false
        }
        return hasImageLine ? mapped : nil
    }

    /// Pasting an image and then typing without a newline puts the caption on
    /// the *same* line: `![图片](…)配文`. The image is still what the user meant
    /// to place, so draw the picture and push whatever followed it under the
    /// picture. Text ahead of the image means real inline flow, which stays as
    /// literal text.
    static func splitLeadingImage(_ nodes: [any Markup]) -> [PreviewLine]? {
        guard let imageIndex = nodes.firstIndex(where: { $0 is Markdown.Image }) else { return nil }
        guard nodes[0..<imageIndex].allSatisfy(isBlankText) else { return nil }
        let image = nodes[imageIndex]
        guard let source = (image as? Markdown.Image)?.source else { return nil }

        var result: [PreviewLine] = [.image(source: source)]
        let trailing = Array(nodes[(imageIndex + 1)...])
        if trailing.contains(where: { !isBlankText($0) }) {
            result.append(.text(trailing))
        }
        return result
    }

    private static func isBlankText(_ node: any Markup) -> Bool {
        guard let text = node as? Markdown.Text else { return false }
        return text.string.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func attributedLine(_ nodes: [any Markup]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for node in nodes {
            result.append(nativeInline(node))
        }
        return result
    }

    private static func lineIsExplicitBlockQuote(_ line: String) -> Bool {
        var index = line.startIndex
        var leadingSpaces = 0
        while index < line.endIndex, line[index] == " ", leadingSpaces < 4 {
            leadingSpaces += 1
            index = line.index(after: index)
        }
        return leadingSpaces <= 3 && index < line.endIndex && line[index] == ">"
    }

    private func blocks(_ node: any Markup) -> AnyView {
        let children = Array(node.children)
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            ForEach(children.indices, id: \.self) { index in
                block(children[index])
            }
        })
    }

    private func block(_ node: any Markup) -> AnyView {
        switch node {
        case let heading as Heading:
            let size = CGFloat(max(15, 26 - heading.level * 2))
            return AnyView(NativeMarkdownText(content: nativeInline(heading, size: size, bold: true), onEdit: onEdit))
        case let paragraph as Paragraph:
            if let image = Self.imageOnlyParagraph(paragraph) {
                return AnyView(DraftImageView(
                    relativePath: image.source ?? "",
                    directoryURL: attachmentDirectory
                ))
            }
            if let lines = Self.previewLines(of: paragraph) {
                return AnyView(VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines.indices, id: \.self) { index in
                        switch lines[index] {
                        case .image(let source):
                            DraftImageView(relativePath: source, directoryURL: attachmentDirectory)
                        case .text(let nodes):
                            NativeMarkdownText(content: attributedLine(nodes), onEdit: onEdit)
                        }
                    }
                })
            }
            return AnyView(NativeMarkdownText(content: nativeInline(paragraph), onEdit: onEdit))
        case let code as CodeBlock:
            return AnyView(SwiftUI.Text(code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code)
                .font(.system(size: 13, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8).background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5)))
        case let quote as BlockQuote:
            return AnyView(HStack(alignment: .top, spacing: 8) {
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 3)
                blocks(quote)
            }.fixedSize(horizontal: false, vertical: true))
        case let list as OrderedList:
            return listView(list, start: Int(list.startIndex))
        case let list as UnorderedList:
            return listView(list, start: nil)
        case let table as Markdown.Table:
            let rows: [any Markup] = [table.head] + Array(table.body.children)
            return AnyView(Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(rows.indices, id: \.self) { index in
                    let cells = Array(rows[index].children)
                    GridRow {
                        ForEach(cells.indices, id: \.self) { cell in
                            NativeMarkdownText(content: nativeInline(cells[cell], bold: index == 0), onEdit: onEdit)
                        }
                    }
                    if index == 0 { Divider() }
                }
            })
        case is ThematicBreak:
            return AnyView(Divider().padding(.vertical, 4))
        case let html as HTMLBlock:
            return AnyView(SwiftUI.Text(html.rawHTML))
        default:
            return blocks(node)
        }
    }

    private func listView(_ node: any Markup, start: Int?) -> AnyView {
        let items = Array(node.children)
        return AnyView(VStack(alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 6) {
                    SwiftUI.Text(listMarker(items[index], index: index, start: start))
                    blocks(items[index]).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        })
    }

    private func listMarker(_ item: any Markup, index: Int, start: Int?) -> String {
        if let checkbox = (item as? ListItem)?.checkbox {
            return checkbox == .checked ? "☑" : "☐"
        }
        return start.map { "\($0 + index)." } ?? "•"
    }

    /// NSTextField applies obliqueness to CJK fallback glyphs, unlike SwiftUI's
    /// italic font trait, which can leave Chinese glyphs visibly upright.
    func nativeInline(_ node: any Markup, size: CGFloat = 14, bold: Bool = false,
                      italic: Bool = false, strike: Bool = false) -> NSAttributedString {
        if let text = node as? Markdown.Text {
            return nativeText(text.string, size: size, bold: bold, italic: italic, strike: strike)
        }
        if node is SoftBreak || node is LineBreak {
            return nativeText("\n", size: size, bold: bold, italic: italic, strike: strike)
        }
        if let code = node as? InlineCode {
            return NSAttributedString(string: code.code, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.12)
            ])
        }
        if let html = node as? InlineHTML {
            return nativeText(html.rawHTML, size: size, bold: bold, italic: italic, strike: strike, detectLinks: false)
        }
        if let image = node as? Markdown.Image {
            return nativeText("[图片：\(image.plainText)](\(image.source ?? ""))", size: size,
                              bold: bold, italic: italic, strike: strike, detectLinks: false)
        }
        let result = NSMutableAttributedString(string: "")
        for child in node.children {
            result.append(nativeInline(child, size: size, bold: bold || node is Strong,
                                       italic: italic || node is Emphasis,
                                       strike: strike || node is Strikethrough))
        }
        if let link = node as? Markdown.Link,
           let url = DraftLink.markdownDestination(link.destination), result.length > 0 {
            result.addAttributes(linkAttributes(for: url), range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    private func nativeText(_ text: String, size: CGFloat, bold: Bool, italic: Bool,
                            strike: Bool, detectLinks: Bool = true) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular),
            .foregroundColor: NSColor.labelColor
        ]
        if italic { attributes[.obliqueness] = 0.25 }
        if strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        attributes[.paragraphStyle] = paragraph
        let result = NSMutableAttributedString(string: text, attributes: attributes)
        if detectLinks {
            for match in DraftLink.detect(in: text) {
                result.addAttributes(linkAttributes(for: match.url), range: match.range)
            }
        }
        return result
    }

    private func linkAttributes(for url: URL) -> [NSAttributedString.Key: Any] {
        [
            .link: url,
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .toolTip: "⌘ 单击打开：\(url.isFileURL ? url.path : url.absoluteString)"
        ]
    }

    func inline(_ node: any Markup) -> AttributedString {
        switch node {
        case let text as Markdown.Text:
            return AttributedString(text.string)
        case is SoftBreak, is LineBreak:
            return AttributedString("\n")
        case let code as InlineCode:
            var result = AttributedString(code.code)
            result.font = .system(size: 13, design: .monospaced)
            result.backgroundColor = .secondary.opacity(0.12)
            return result
        case let html as InlineHTML:
            return AttributedString(html.rawHTML)
        case let image as Markdown.Image:
            return AttributedString("[图片：\(image.plainText)](\(image.source ?? ""))")
        default:
            var result = node.children.reduce(into: AttributedString()) { $0 += inline($1) }
            if node is Strong || node is Emphasis {
                let intent: InlinePresentationIntent = node is Strong ? .stronglyEmphasized : .emphasized
                for run in result.runs {
                    result[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(intent)
                }
            }
            if node is Strikethrough { result.strikethroughStyle = .single }
            if node is Markdown.Link {
                // Render links visibly without stealing the single-click edit gesture.
                result.foregroundColor = .accentColor
                result.underlineStyle = .single
            }
            return result
        }
    }
}

private struct NativeMarkdownText: NSViewRepresentable {
    let content: NSAttributedString
    let onEdit: () -> Void

    func makeNSView(context: Context) -> DraftLinkTextField {
        let field = DraftLinkTextField(frame: .zero)
        field.attributedStringValue = content
        field.onEdit = onEdit
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.isBordered = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        return field
    }

    func updateNSView(_ field: DraftLinkTextField, context: Context) {
        field.attributedStringValue = content
        field.onEdit = onEdit
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: DraftLinkTextField,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let bounds = content.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: width, height: max(ceil(bounds.height) + 2, 18))
    }
}
