import XCTest
@testable import DraftBookCore

final class MarkdownImageTests: XCTestCase {
    private let reference = "![图片](Attachments/a.png)"

    func testReferenceEscapesSpaces() {
        XCTAssertEqual(
            MarkdownImage.reference(forRelativePath: "Attachments/截屏 2026.png"),
            "![图片](Attachments/截屏%202026.png)"
        )
    }

    func testInsertionIntoEmptyDraft() {
        let plan = MarkdownImage.insertion(
            forReference: reference,
            in: "",
            selection: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(plan.text, reference)
        XCTAssertEqual(plan.caretLocation, 24)
    }

    func testInsertionAtEndOfTextStartsNewParagraph() {
        let content = "第一段"
        let plan = MarkdownImage.insertion(
            forReference: reference,
            in: content,
            selection: NSRange(location: 3, length: 0)
        )

        XCTAssertEqual(plan.text, "\n\n\(reference)")
        let result = (content as NSString).replacingCharacters(in: plan.range, with: plan.text)
        XCTAssertEqual(result, "第一段\n\n\(reference)")
    }

    func testInsertionAfterSingleNewlineAddsBlankLine() {
        let content = "第一段\n"
        let plan = MarkdownImage.insertion(
            forReference: reference,
            in: content,
            selection: NSRange(location: 4, length: 0)
        )

        XCTAssertEqual(plan.text, "\n\(reference)")
        let result = (content as NSString).replacingCharacters(in: plan.range, with: plan.text)
        XCTAssertEqual(result, "第一段\n\n\(reference)")
    }

    func testInsertionMidLineSplitsBothParagraphs() {
        let content = "ab"
        let plan = MarkdownImage.insertion(
            forReference: reference,
            in: content,
            selection: NSRange(location: 1, length: 0)
        )

        XCTAssertEqual(plan.text, "\n\n\(reference)\n\n")
        let result = (content as NSString).replacingCharacters(in: plan.range, with: plan.text)
        XCTAssertEqual(result, "a\n\n\(reference)\n\nb")
    }

    func testInsertionBetweenParagraphsKeepsSingleBlankLine() {
        let content = "第一段\n\n第二段"
        let plan = MarkdownImage.insertion(
            forReference: reference,
            in: content,
            selection: NSRange(location: 5, length: 0)
        )

        XCTAssertEqual(plan.text, "\(reference)\n\n")
        let result = (content as NSString).replacingCharacters(in: plan.range, with: plan.text)
        XCTAssertEqual(result, "第一段\n\n\(reference)\n\n第二段")
    }

    func testInsertionReplacesSelection() {
        let content = "替换我"
        let plan = MarkdownImage.insertion(
            forReference: reference,
            in: content,
            selection: NSRange(location: 0, length: 3)
        )

        XCTAssertEqual(plan.range, NSRange(location: 0, length: 3))
        XCTAssertEqual(plan.text, reference)
    }

    func testReferencedFileNamesFindsAttachmentsOnly() {
        let content = """
        一段文字

        ![图片](Attachments/a.png)

        ![截图](Attachments/%E6%88%AA%E5%9B%BE%201.png "标题")

        [外链](https://example.com/x.png)
        ![网络图](https://example.com/b.png)
        """

        XCTAssertEqual(
            MarkdownImage.referencedFileNames(in: content),
            ["a.png", "截图 1.png"]
        )
    }

    func testReferencedFileNamesMatchesInsertedReference() {
        let inserted = MarkdownImage.reference(forRelativePath: "Attachments/截屏 2026-11-18.png")
        let content = "前\n\n\(inserted)\n\n后"

        XCTAssertEqual(MarkdownImage.referencedFileNames(in: content), ["截屏 2026-11-18.png"])
    }

    func testSelectionOutsideContentIsClamped() {
        let plan = MarkdownImage.insertion(
            forReference: reference,
            in: "abc",
            selection: NSRange(location: 99, length: 0)
        )

        XCTAssertEqual(plan.range, NSRange(location: 3, length: 0))
        XCTAssertEqual(plan.text, "\n\n\(reference)")
    }
}
