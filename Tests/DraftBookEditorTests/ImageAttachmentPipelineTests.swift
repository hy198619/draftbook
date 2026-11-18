import DraftBookCore
import Markdown
import XCTest
@testable import DraftBook

/// End-to-end of the non-UI pipeline: save bytes the way a paste does, insert
/// the Markdown line, then let the preview resolve it back to a real file.
@MainActor
final class ImageAttachmentPipelineTests: XCTestCase {
    private var directory: URL!
    private let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftBookPipeline-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testSavedImageBecomesPreviewableReference() throws {
        let store = DraftStore(dataDirectory: directory)
        let path = try store.saveAttachment(data: pngData, preferredName: "截图", fileExtension: "png")

        let insertion = MarkdownImage.insertion(
            forReference: MarkdownImage.reference(forRelativePath: path),
            in: "先写一段\n",
            selection: NSRange(location: 5, length: 0)
        )
        let content = ("先写一段\n" as NSString)
            .replacingCharacters(in: insertion.range, with: insertion.text)

        XCTAssertEqual(content, "先写一段\n\n![图片](Attachments/截图.png)")

        let document = MarkdownDraftPreview.document(for: content)
        let paragraph = try XCTUnwrap(
            Array(document.children).compactMap { $0 as? Paragraph }.last
        )
        let image = try XCTUnwrap(MarkdownDraftPreview.imageOnlyParagraph(paragraph))
        let source = try XCTUnwrap(image.source)

        XCTAssertEqual(source, "Attachments/截图.png")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: store.attachmentURL(forRelativePath: source).path
            )
        )
        XCTAssertEqual(
            MarkdownImage.referencedFileNames(in: content),
            ["截图.png"]
        )
    }

    func testStoredDraftKeepsImageAfterRestart() throws {
        let store = DraftStore(dataDirectory: directory)
        let path = try store.saveAttachment(data: pngData, preferredName: "截图", fileExtension: "png")
        store.composer = "带图草稿\n![图片](\(path))"
        let draft = try XCTUnwrap(store.sealComposer())
        store.flush()

        let reloaded = DraftStore(dataDirectory: directory)
        let restored = try XCTUnwrap(reloaded.draft(withID: draft.id))

        XCTAssertEqual(restored.content, "带图草稿\n![图片](\(path))")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: reloaded.attachmentURL(forRelativePath: path).path
            )
        )
    }
}
