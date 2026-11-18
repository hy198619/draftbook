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

    func testReferenceSurvivesBlockQuoteRewrite() {
        let source = "> ![图片](Attachments/a.png)\n下一行"
        let rewritten = MarkdownDraftPreview.sourceWithExplicitBlockQuoteBoundaries(source)

        XCTAssertTrue(rewritten.contains("![图片](Attachments/a.png)"))
    }
}
