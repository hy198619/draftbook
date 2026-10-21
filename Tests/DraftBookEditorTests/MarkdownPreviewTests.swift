import XCTest
import Markdown
@testable import DraftBook

final class MarkdownPreviewTests: XCTestCase {
    func testPlainLinesAndHashtagsArePreserved() {
        let source = "#话题\n第二行\nAPI_key_value"
        let document = Document(parsing: source, options: [.disableSmartOpts])
        XCTAssertTrue(document.child(at: 0) is Paragraph)
        let rendered = MarkdownDraftPreview(source: source).inline(document)
        XCTAssertEqual(String(rendered.characters), source)
    }

    func testNestedInlineFormattingAndEscapes() {
        let source = "**粗体 *斜体*** 和 \\*文字\\* 与 `a_b`"
        let rendered = MarkdownDraftPreview(source: source).inline(Document(parsing: source))
        XCTAssertEqual(String(rendered.characters), "粗体 斜体 和 *文字* 与 a_b")
        XCTAssertTrue(rendered.runs.contains { run in
            run.inlinePresentationIntent?.contains([.stronglyEmphasized, .emphasized]) == true
        })
    }

    func testSingleAsteriskEmphasisHasVisibleItalicFont() {
        let source = "普通*斜体*文字"
        let rendered = MarkdownDraftPreview(source: source).nativeInline(Document(parsing: source))
        XCTAssertEqual(rendered.string, "普通斜体文字")
        XCTAssertNil(rendered.attribute(.obliqueness, at: 0, effectiveRange: nil))
        XCTAssertEqual(rendered.attribute(.obliqueness, at: 2, effectiveRange: nil) as? Double, 0.25)
        XCTAssertNil(rendered.attribute(.obliqueness, at: 4, effectiveRange: nil))
    }

    func testBlockStructureAndOrderedStart() {
        let document = Document(parsing: "# 标题\n\n3. 第一项\n4. 第二项\n\n> 引用\n\n```swift\nlet x = 1\n```\n\n---")
        let nodes = Array(document.children)
        XCTAssertTrue(nodes[0] is Heading)
        XCTAssertEqual((nodes[1] as? OrderedList)?.startIndex, 3)
        XCTAssertTrue(nodes[2] is BlockQuote)
        XCTAssertEqual((nodes[3] as? CodeBlock)?.code, "let x = 1\n")
        XCTAssertTrue(nodes[4] is ThematicBreak)
    }

    func testUnprefixedLineAfterQuoteStartsANewBlockWithoutExtraBlankLine() {
        let source = "> 引用\n[百度](www.baidu.com)"
        let document = MarkdownDraftPreview.document(for: source)
        let nodes = Array(document.children)
        let preview = MarkdownDraftPreview(source: source)

        XCTAssertEqual(nodes.count, 2)
        XCTAssertTrue(nodes[0] is BlockQuote)
        XCTAssertEqual(preview.nativeInline(nodes[0]).string, "引用")
        XCTAssertTrue(nodes[1] is Paragraph)
        XCTAssertEqual(preview.nativeInline(nodes[1]).string, "百度")
    }

    func testConsecutiveExplicitQuoteLinesStayInOneQuote() {
        let source = "> 第一行\n> 第二行\n普通段落"
        let document = MarkdownDraftPreview.document(for: source)
        let nodes = Array(document.children)
        let preview = MarkdownDraftPreview(source: source)

        XCTAssertEqual(nodes.count, 2)
        XCTAssertTrue(nodes[0] is BlockQuote)
        XCTAssertEqual(preview.nativeInline(nodes[0]).string, "第一行\n第二行")
        XCTAssertTrue(nodes[1] is Paragraph)
        XCTAssertEqual(preview.nativeInline(nodes[1]).string, "普通段落")
    }

    func testUnclosedEmphasisStaysLiteral() {
        let source = "普通 **未闭合文字"
        XCTAssertEqual(String(MarkdownDraftPreview(source: source).inline(Document(parsing: source)).characters), source)
    }
}
