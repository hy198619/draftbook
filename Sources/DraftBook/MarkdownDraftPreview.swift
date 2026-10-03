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
            return AnyView(SwiftUI.Text(styledInline(heading, size: size, weight: .bold))
                .font(.system(size: size, weight: .bold)))
        case let paragraph as Paragraph:
            return AnyView(SwiftUI.Text(styledInline(paragraph)))
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
                            SwiftUI.Text(styledInline(cells[cell], weight: index == 0 ? .semibold : .regular))
                                .fontWeight(index == 0 ? .semibold : .regular)
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

    // SwiftUI does not reliably turn presentation intent into a visible italic
    // font once a parent view supplies its own font. Give emphasized runs an
    // explicit font while leaving plain text and inline code unchanged.
    func styledInline(
        _ node: any Markup,
        size: CGFloat = 14,
        weight: SwiftUI.Font.Weight = .regular
    ) -> AttributedString {
        var result = inline(node)
        for run in result.runs {
            let intent = run.inlinePresentationIntent ?? []
            guard run.font == nil,
                  intent.contains(.emphasized) || intent.contains(.stronglyEmphasized) else { continue }
            var font = SwiftUI.Font.system(
                size: size,
                weight: intent.contains(.stronglyEmphasized) ? .bold : weight
            )
            if intent.contains(.emphasized) { font = font.italic() }
            result[run.range].font = font
        }
        return result
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
