import AppKit
import DraftBookCore
import XCTest
@testable import DraftBook

@MainActor
final class ImagePasteTests: XCTestCase {
    private var directory: URL!
    private var store: DraftStore!
    private var pasteboard: NSPasteboard!

    private let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftBookPaste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = DraftStore(dataDirectory: directory)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("DraftBookTests-\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testPastingScreenshotInsertsReferenceOnItsOwnParagraph() throws {
        let textView = makeTextView()
        textView.string = "前面一段"
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)

        XCTAssertTrue(textView.pasteImage(from: pasteboard))
        XCTAssertEqual(textView.string, "前面一段\n\n![图片](Attachments/截图.png)")

        let fileURL = store.attachmentURL(forRelativePath: "Attachments/截图.png")
        XCTAssertEqual(try Data(contentsOf: fileURL), pngData)
    }

    func testTextOnPasteboardWinsOverImage() {
        let textView = makeTextView()
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setString("表格文本", forType: .string)

        XCTAssertFalse(textView.pasteImage(from: pasteboard))
        XCTAssertEqual(textView.string, "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.attachmentsDirectoryURL.path))
    }

    func testPastingImageFileCopiesItWithOriginalName() throws {
        let source = directory.appendingPathComponent("IMG_0001.png")
        try pngData.write(to: source)

        let textView = makeTextView()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([source as NSURL]))

        XCTAssertTrue(textView.pasteImage(from: pasteboard))
        XCTAssertEqual(textView.string, "![图片](Attachments/IMG_0001.png)")
    }

    func testNonImageFileIsIgnored() throws {
        let source = directory.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: source)

        let textView = makeTextView()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([source as NSURL]))

        XCTAssertFalse(textView.pasteImage(from: pasteboard))
    }

    func testInsertionIsUndoableAsOneStep() throws {
        let textView = makeTextView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        textView.string = "原始文字"

        textView.insertImageReference("Attachments/截图.png")
        XCTAssertEqual(textView.string, "原始文字\n\n![图片](Attachments/截图.png)")

        guard let undoManager = textView.undoManager, undoManager.canUndo else {
            throw XCTSkip("当前环境没有可用的撤销管理器")
        }
        undoManager.undo()
        XCTAssertEqual(textView.string, "原始文字")
    }

    func testPasteOverrideUsesGeneralPasteboard() throws {
        let general = NSPasteboard.general
        general.clearContents()
        general.setData(pngData, forType: .png)
        defer { general.clearContents() }

        let textView = makeTextView()
        textView.paste(nil)

        XCTAssertTrue(
            textView.string.hasPrefix("![图片](Attachments/"),
            "菜单/快捷键走的是 paste(_:)，这里必须命中图片分支，实际内容：\(textView.string)"
        )
    }

    func testCopiedFileWinsOverItsPathText() throws {
        let source = directory.appendingPathComponent("logo.png")
        try pngData.write(to: source)

        let textView = makeTextView()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([source as NSURL]))
        pasteboard.setString(source.path, forType: .string)

        XCTAssertTrue(textView.pasteImage(from: pasteboard))
        XCTAssertEqual(textView.string, "![图片](Attachments/logo.png)")
    }

    private func makeTextView() -> DraftTextView {
        let textView = DraftTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.imagePasteHandler = { [weak self] pasteboard in
            guard let self else { return nil }
            return ImagePasteService.save(pasteboard: pasteboard, store: self.store)
        }
        textView.imageFileHandler = { [weak self] url in
            guard let self else { return nil }
            return ImagePasteService.save(fileURL: url, store: self.store)
        }
        return textView
    }
}
