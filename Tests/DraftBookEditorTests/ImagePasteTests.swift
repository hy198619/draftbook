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

    /// The 0.9.9 bug: a chat app (WeChat, Feishu) or a capture tool puts an
    /// image on the pasteboard *and* a blank string. A blank flavour is not
    /// text anybody wants, so it must not swallow the picture.
    func testBlankTextFlavourDoesNotBlockImagePaste() throws {
        for blank in ["", " ", "\n"] {
            let textView = makeTextView()
            pasteboard.clearContents()
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString(blank, forType: .string)

            XCTAssertTrue(textView.pasteImage(from: pasteboard), "空白文本 flavour 挡掉了图片：\(blank.debugDescription)")
            XCTAssertEqual(textView.string, "![图片](Attachments/截图.png)")
        }
    }

    /// Same bug, second shape: the clipboard carries the file name or the
    /// image URL beside the picture. That is still “I want this image”.
    func testImageNameOrURLTextFlavourDoesNotBlockImagePaste() throws {
        let candidates = [
            "截图.png",
            "/Users/me/Downloads/Screenshot 2026-11-19 at 14.36.15.png",
            "https://example.com/img/a.jpeg?size=large",
            "img.HEIC"
        ]
        for candidate in candidates {
            let textView = makeTextView()
            pasteboard.clearContents()
            pasteboard.setData(pngData, forType: .png)
            pasteboard.setString(candidate, forType: .string)

            XCTAssertTrue(textView.pasteImage(from: pasteboard), "图片名/URL 文本挡住了插图：\(candidate)")
        }
    }

    /// Real text stays real text: copying a table must never turn into a
    /// picture, whatever else is on the clipboard.
    func testMultiLineOrProseTextStillWins() throws {
        let textView = makeTextView()
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setString("标题\t数值\n甲\t1\n乙\t2", forType: .string)

        XCTAssertFalse(textView.pasteImage(from: pasteboard))
        XCTAssertEqual(textView.string, "")
    }

    /// ⌥⌘V is the escape hatch: with force the text flavour is ignored.
    func testForcedPasteInsertsImageBesideTextFlavour() throws {
        let textView = makeTextView()
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setString("正文一段", forType: .string)

        XCTAssertFalse(textView.pasteImage(from: pasteboard))
        XCTAssertTrue(textView.pasteImage(from: pasteboard, force: true))
        XCTAssertEqual(textView.string, "![图片](Attachments/截图.png)")
    }

    func testImageNameShapeProbe() {
        XCTAssertTrue(DraftTextView.looksLikeImageNameOrURL("a.png"))
        XCTAssertTrue(DraftTextView.looksLikeImageNameOrURL("/Users/me/图片/photo.heic"))
        XCTAssertFalse(DraftTextView.looksLikeImageNameOrURL("一段正文"))
        XCTAssertFalse(DraftTextView.looksLikeImageNameOrURL("两行\n文字"))
        XCTAssertFalse(DraftTextView.looksLikeImageNameOrURL(String(repeating: "a", count: 4000) + ".png"))
    }

    /// A diagnostic report must describe the clipboard, never copy it.
    func testPasteboardSummaryDoesNotLeakClipboardText() {
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
        pasteboard.setString("客户的私密电话号码 13800000000", forType: .string)

        let summary = DraftTextView.pasteboardSummary(pasteboard)
        XCTAssertFalse(summary.contains("13800000000"))
        XCTAssertFalse(summary.contains("私密"))
        XCTAssertTrue(summary.contains("textFlavour=text"))
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
