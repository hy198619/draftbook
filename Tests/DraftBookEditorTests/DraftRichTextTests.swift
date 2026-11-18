import AppKit
import DraftBookCore
import XCTest
@testable import DraftBook

@MainActor
final class DraftRichTextTests: XCTestCase {
    private var directory: URL!
    private var store: DraftStore!
    private let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftBookRichText-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = DraftStore(dataDirectory: directory)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testAttributedStringEmbedsImageAttachment() throws {
        let path = try store.saveAttachment(data: pngData, preferredName: "截图", fileExtension: "png")
        let source = "一段文字\n\n![图片](\(path))\n\n结尾"

        let attributed = DraftRichText.attributedString(
            for: source,
            attachmentDirectory: store.attachmentsDirectoryURL
        )

        XCTAssertTrue(attributed.string.contains("一段文字"))
        var attachmentCount = 0
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, _ in
            if value is NSTextAttachment { attachmentCount += 1 }
        }
        XCTAssertEqual(attachmentCount, 1)
    }

    func testRTFKeepsTextContent() throws {
        let path = try store.saveAttachment(data: pngData, preferredName: "截图", fileExtension: "png")
        let attributed = DraftRichText.attributedString(
            for: "文字\n\n![图片](\(path))",
            attachmentDirectory: store.attachmentsDirectoryURL
        )

        guard let rtf = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else {
            return XCTFail("RTF 编码失败")
        }

        // macOS 的 RTF 写出器不带 NSTextAttachment（只有 RTFD 支持），
        // 图片由 HTML 那份承载；RTF 只保证文字与排版。
        let text = String(decoding: rtf, as: UTF8.self)
        XCTAssertTrue(text.contains("\\rtf1"))
        XCTAssertGreaterThan(rtf.count, 100)
    }

    func testHTMLInlinesImageAsBase64() throws {
        let path = try store.saveAttachment(data: pngData, preferredName: "截图", fileExtension: "png")
        let html = try XCTUnwrap(
            DraftRichText.htmlString(
                for: "文字\n\n![图片](\(path))",
                attachmentDirectory: store.attachmentsDirectoryURL
            )
        )

        XCTAssertTrue(html.contains("<p"))
        XCTAssertTrue(html.contains("data:image/png;base64,"))
    }

    func testMissingImageFallsBackToPlaceholder() {
        let attributed = DraftRichText.attributedString(
            for: "文字\n\n![图片](Attachments/不存在.png)",
            attachmentDirectory: store.attachmentsDirectoryURL
        )

        XCTAssertTrue(attributed.string.contains("[图片缺失：不存在.png]"))
    }

    func testCopyPlacesRichAndPlainFlavoursOnPasteboard() throws {
        let path = try store.saveAttachment(data: pngData, preferredName: "截图", fileExtension: "png")
        let draft = Draft(content: "标题\n\n![图片](\(path))")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        DraftRichText.copy(draft, store: store)

        let types = try XCTUnwrap(pasteboard.types).map(\.rawValue)
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType.string.rawValue))
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType.rtf.rawValue))
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType.html.rawValue))
        XCTAssertEqual(pasteboard.string(forType: .string), draft.content)
        XCTAssertNotNil(pasteboard.data(forType: .rtf))
    }

    func testMarkdownFormattingSurvivesInRichText() {
        let attributed = DraftRichText.attributedString(
            for: "# 标题\n\n**重点** 和 *斜体*，还有 `代码`",
            attachmentDirectory: store.attachmentsDirectoryURL
        )

        XCTAssertTrue(attributed.string.contains("标题"))
        XCTAssertTrue(attributed.string.contains("重点"))
        XCTAssertFalse(attributed.string.contains("**"), "Markdown 标记不应出现在富文本里")
    }
}
