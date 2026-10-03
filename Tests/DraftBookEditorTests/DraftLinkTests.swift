import AppKit
import Markdown
import XCTest
@testable import DraftBook

final class DraftLinkTests: XCTestCase {
    func testMarkdownLinkKeepsVisibleLabelAndWebDestination() {
        let source = "看[说明](https://example.com/article)"
        let result = MarkdownDraftPreview(source: source).nativeInline(Document(parsing: source))
        XCTAssertEqual(result.string, "看说明")
        XCTAssertNil(result.attribute(.link, at: 0, effectiveRange: nil))
        XCTAssertEqual((result.attribute(.link, at: 1, effectiveRange: nil) as? URL)?.absoluteString,
                       "https://example.com/article")
    }

    func testBareWebLinksAreDetectedButEmailAndCodeAreNot() {
        let source = "看 https://example.com/a ，还有 www.example.org。邮箱 me@example.org；`https://hidden.example`"
        let result = MarkdownDraftPreview(source: source).nativeInline(Document(parsing: source))
        let urls = linkedURLs(in: result)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://example.com/a", "https://www.example.org"])
    }

    func testExistingLocalFileCanBeLinkedByFileURLAndAbsolutePath() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftBookLinkTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("note.txt")
        try Data("test".utf8).write(to: file)
        let spacedFile = folder.appendingPathComponent("meeting draft.txt")
        try Data("test".utf8).write(to: spacedFile)

        XCTAssertEqual(DraftLink.markdownDestination(file.absoluteString), file)
        XCTAssertEqual(DraftLink.markdownDestination(file.path), file)
        XCTAssertEqual(DraftLink.detect(in: "文件 \(file.path)。").first?.url, file)
        XCTAssertEqual(DraftLink.detect(in: "文件 \(file.absoluteString)。").first?.url, file)
        XCTAssertEqual(DraftLink.detect(in: "文件 \(spacedFile.path) 稍后再看").first?.url, spacedFile)
        XCTAssertEqual(DraftLink.detect(in: "文件 \(spacedFile.path)，稍后再看").first?.url, spacedFile)
        XCTAssertNil(DraftLink.markdownDestination(folder.appendingPathComponent("missing.txt").path))
        XCTAssertNil(DraftLink.markdownDestination("relative/note.txt"))
        XCTAssertTrue(DraftLink.detect(in: "不存在 \(folder.path)/missing.txt").isEmpty)
    }

    func testUnsafeSchemesAndExecutableFilesAreNotOpenedSilently() throws {
        XCTAssertNil(DraftLink.markdownDestination("javascript:alert(1)"))
        XCTAssertNil(DraftLink.markdownDestination("ssh://example.com"))
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftBookLinkTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script = folder.appendingPathComponent("run.command")
        try Data("echo test".utf8).write(to: script)
        XCTAssertTrue(DraftLink.needsOpenConfirmation(script))
        XCTAssertFalse(DraftLink.needsOpenConfirmation(URL(string: "https://example.com")!))
    }

    func testCommandClickHitTestFindsOnlyLinkedGlyphs() {
        let source = "普通 [链接](https://example.com) 文字"
        let content = MarkdownDraftPreview(source: source).nativeInline(Document(parsing: source))
        let field = DraftLinkTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 32))
        field.attributedStringValue = content
        field.isBordered = false
        field.lineBreakMode = .byWordWrapping
        XCTAssertNil(field.link(at: NSPoint(x: 5, y: 14)))
        XCTAssertEqual(field.link(at: NSPoint(x: 47, y: 14))?.absoluteString, "https://example.com")
        XCTAssertNil(field.link(at: NSPoint(x: 300, y: 14)))
    }

    func testCommandClickOpensLinkWhilePlainClickEdits() {
        let source = "普通 [链接](https://example.com) 文字"
        let content = MarkdownDraftPreview(source: source).nativeInline(Document(parsing: source))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let field = DraftLinkTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 32))
        field.attributedStringValue = content
        field.isBordered = false
        window.contentView?.addSubview(field)

        var edits = 0
        var opened: [URL] = []
        field.onEdit = { edits += 1 }
        field.onOpen = { opened.append($0) }
        func click(at point: NSPoint, modifiers: NSEvent.ModifierFlags) {
            let location = field.convert(point, to: nil)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: location,
                                           modifierFlags: modifiers, timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil,
                                           eventNumber: 1, clickCount: 1, pressure: 1)!
            field.mouseDown(with: event)
        }

        click(at: NSPoint(x: 47, y: 14), modifiers: [])
        XCTAssertEqual(edits, 1)
        XCTAssertTrue(opened.isEmpty)
        click(at: NSPoint(x: 47, y: 14), modifiers: .command)
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(opened.first?.absoluteString, "https://example.com")
        click(at: NSPoint(x: 5, y: 14), modifiers: .command)
        XCTAssertEqual(edits, 2)
    }

    private func linkedURLs(in text: NSAttributedString) -> [URL] {
        var urls: [URL] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let url = value as? URL { urls.append(url) }
        }
        return urls
    }
}
