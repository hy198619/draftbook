import AppKit
import Markdown
import SwiftUI

/// CommonMark parsing is delegated to cmark through Swift Markdown. Soft breaks
/// are displayed as newlines, a CommonMark-permitted presentation choice.
struct MarkdownDraftPreview: View {
    let source: String

    var body: some View {
        blocks(Document(parsing: source, options: [.disableSmartOpts]))
            .font(.system(size: 14))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            return AnyView(NativeMarkdownText(content: nativeInline(heading, size: size, bold: true)))
        case let paragraph as Paragraph:
            return AnyView(NativeMarkdownText(content: nativeInline(paragraph)))
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
                            NativeMarkdownText(content: nativeInline(cells[cell], bold: index == 0))
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
                      italic: Bool = false, strike: Bool = false, link: Bool = false) -> NSAttributedString {
        if let text = node as? Markdown.Text {
            return nativeText(text.string, size: size, bold: bold, italic: italic, strike: strike, link: link)
        }
        if node is SoftBreak || node is LineBreak {
            return nativeText("\n", size: size, bold: bold, italic: italic, strike: strike, link: link)
        }
        if let code = node as? InlineCode {
            return NSAttributedString(string: code.code, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.12)
            ])
        }
        if let html = node as? InlineHTML {
            return nativeText(html.rawHTML, size: size, bold: bold, italic: italic, strike: strike, link: link)
        }
        if let image = node as? Markdown.Image {
            return nativeText("[图片：\(image.plainText)](\(image.source ?? ""))", size: size,
                              bold: bold, italic: italic, strike: strike, link: link)
        }
        let result = NSMutableAttributedString(string: "")
        for child in node.children {
            result.append(nativeInline(child, size: size, bold: bold || node is Strong,
                                       italic: italic || node is Emphasis,
                                       strike: strike || node is Strikethrough,
                                       link: link || node is Markdown.Link))
        }
        return result
    }

    private func nativeText(_ text: String, size: CGFloat, bold: Bool, italic: Bool,
                            strike: Bool, link: Bool) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular),
            .foregroundColor: link ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        if italic { attributes[.obliqueness] = 0.25 }
        if strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if link { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        attributes[.paragraphStyle] = paragraph
        return NSAttributedString(string: text, attributes: attributes)
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

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithAttributedString: content)
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.isBordered = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.attributedStringValue = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: NSTextField,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let bounds = content.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
        return CGSize(width: width, height: max(ceil(bounds.height) + 2, 18))
    }
}
