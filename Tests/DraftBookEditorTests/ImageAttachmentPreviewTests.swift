import Markdown
import XCTest
@testable import DraftBook

@MainActor
final class ImageAttachmentPreviewTests: XCTestCase {
    func testImageAloneInParagraphIsPromoted() throws {
        let document = MarkdownDraftPreview.document(for: "![图片](Attachments/a.png)")
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)
        let image = try XCTUnwrap(MarkdownDraftPreview.imageOnlyParagraph(paragraph))

        XCTAssertEqual(image.source, "Attachments/a.png")
    }

    func testImageWithSurroundingTextKeepsLiteralFallback() throws {
        let document = MarkdownDraftPreview.document(
            for: "前面 ![图片](Attachments/a.png) 后面"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)

        XCTAssertNil(MarkdownDraftPreview.imageOnlyParagraph(paragraph))
    }

    func testImageWithCaptionTextIsStillPromoted() throws {
        let document = MarkdownDraftPreview.document(for: "![换个说法](Attachments/a.png)")
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)

        XCTAssertEqual(
            MarkdownDraftPreview.imageOnlyParagraph(paragraph)?.plainText,
            "换个说法"
        )
    }

    func testTwoImagesInOneParagraphAreNotPromoted() throws {
        let document = MarkdownDraftPreview.document(
            for: "![一](Attachments/a.png) ![二](Attachments/b.png)"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)

        XCTAssertNil(MarkdownDraftPreview.imageOnlyParagraph(paragraph))
    }

    /// 0.9.9 的第二个坑：粘完图直接敲回车写配文，图片和文字之间只有一个换行，
    /// CommonMark 仍算同一段，预览就退化成 `[图片：…](…)` 字面文本。
    func testImageAloneOnItsLineInsideParagraphIsPromoted() throws {
        let document = MarkdownDraftPreview.document(
            for: "![图片](Attachments/a.png)\n配文一行"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)
        let lines = try XCTUnwrap(MarkdownDraftPreview.previewLines(of: paragraph))

        XCTAssertEqual(lines.count, 2)
        switch (lines[0], lines[1]) {
        case let (.image(source), .text(nodes)):
            XCTAssertEqual(source, "Attachments/a.png")
            XCTAssertEqual(nodes.count, 1)
        default:
            XCTFail("应该先是图片行、再是文字行：\(lines)")
        }
    }

    func testTextAboveImageLineIsAlsoPromoted() throws {
        let document = MarkdownDraftPreview.document(
            for: "上面一行\n![图片](Attachments/a.png)"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)
        let lines = try XCTUnwrap(MarkdownDraftPreview.previewLines(of: paragraph))

        XCTAssertEqual(lines.count, 2)
        if case .image = lines[1] {} else { XCTFail("第二行应识别为图片") }
    }

    func testTwoImageLinesAreBothPromoted() throws {
        let document = MarkdownDraftPreview.document(
            for: "![一](Attachments/a.png)\n![二](Attachments/b.png)"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)
        let lines = try XCTUnwrap(MarkdownDraftPreview.previewLines(of: paragraph))

        XCTAssertEqual(lines.count, 2)
        for line in lines {
            if case .image = line { continue }
            XCTFail("两行都应是图片")
        }
    }

    func testReferenceSurvivesBlockQuoteRewrite() {
        let source = "> ![图片](Attachments/a.png)\n下一行"
        let rewritten = MarkdownDraftPreview.sourceWithExplicitBlockQuoteBoundaries(source)

        XCTAssertTrue(rewritten.contains("![图片](Attachments/a.png)"))
    }

    /// 粘完图不回车、直接在图片那一行接着写字：`![图片](…)配文`。
    func testImageFollowedByTextOnSameLineIsSplit() throws {
        let document = MarkdownDraftPreview.document(
            for: "![图片](Attachments/a.png)配文没有回车"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)
        let lines = try XCTUnwrap(MarkdownDraftPreview.previewLines(of: paragraph))

        XCTAssertEqual(lines.count, 2)
        switch lines[0] {
        case .image(let source): XCTAssertEqual(source, "Attachments/a.png")
        default: XCTFail("第一行应是图片：\(lines[0])")
        }
        switch lines[1] {
        case .text(let nodes):
            XCTAssertEqual(nodes.count, 1)
        default: XCTFail("第二行应是配文：\(lines[1])")
        }
    }

    /// 图前面有字才是真行内嵌图，保持源码字面，不抢戏。
    func testTextBeforeImageOnSameLineIsNotSplit() throws {
        let document = MarkdownDraftPreview.document(
            for: "配文 ![图片](Attachments/a.png)"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)

        XCTAssertNil(MarkdownDraftPreview.previewLines(of: paragraph))
    }

    /// 真正的行内嵌图（同一行里有字有图）不在这次范围内，保持原样。
    func testGenuineInlineImageHasNoLinePromotion() throws {
        let document = MarkdownDraftPreview.document(
            for: "前面 ![图片](Attachments/a.png) 后面"
        )
        let paragraph = try XCTUnwrap(Array(document.children).first as? Paragraph)

        XCTAssertNil(MarkdownDraftPreview.previewLines(of: paragraph))
    }
}
