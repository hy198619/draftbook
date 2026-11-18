import XCTest
@testable import DraftBookCore

@MainActor
final class DraftStoreAttachmentTests: XCTestCase {
    private var directory: URL!
    private let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftBookStoreAttachments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testStoreSavesAttachmentInsideDataDirectory() throws {
        let store = DraftStore(dataDirectory: directory)
        let path = try store.saveAttachment(data: pngData, preferredName: "图", fileExtension: "png")

        XCTAssertEqual(path, "Attachments/图.png")
        XCTAssertEqual(
            store.attachmentURL(forRelativePath: path).deletingLastPathComponent().standardizedFileURL,
            directory.appendingPathComponent("Attachments").standardizedFileURL
        )
    }

    func testImageSurvivesWhileAnotherDraftStillReferencesIt() throws {
        let store = DraftStore(dataDirectory: directory)
        let path = try store.saveAttachment(data: pngData, preferredName: "共用图", fileExtension: "png")
        try makeOld(store.attachmentURL(forRelativePath: path))

        let first = makeDraft(in: store, content: "![图片](\(path))", trash: true)
        _ = makeDraft(in: store, content: "另一条也在用\n![图片](\(path))")

        store.deletePermanently(id: first.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.attachmentURL(forRelativePath: path).path))
    }

    func testImageIsRemovedWhenLastReferenceIsDeleted() throws {
        let store = DraftStore(dataDirectory: directory)
        let path = try store.saveAttachment(data: pngData, preferredName: "独占图", fileExtension: "png")
        let url = store.attachmentURL(forRelativePath: path)
        try makeOld(url)

        let only = makeDraft(in: store, content: "![图片](\(path))", trash: true)

        store.deletePermanently(id: only.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecentOrphanIsKeptUntilGracePeriodPasses() throws {
        let store = DraftStore(dataDirectory: directory)
        let path = try store.saveAttachment(data: pngData, preferredName: "新图", fileExtension: "png")
        let url = store.attachmentURL(forRelativePath: path)

        store.collectUnusedAttachments()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testComposerReferenceProtectsImage() throws {
        let store = DraftStore(dataDirectory: directory)
        let path = try store.saveAttachment(data: pngData, preferredName: "编辑器里的图", fileExtension: "png")
        let url = store.attachmentURL(forRelativePath: path)
        try makeOld(url)

        store.composer = "正在写\n![图片](\(path))"
        store.collectUnusedAttachments()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    @discardableResult
    private func makeDraft(in store: DraftStore, content: String, trash: Bool = false) -> Draft {
        store.composer = content
        let draft = store.sealComposer()!
        if trash {
            store.moveToTrash(id: draft.id)
            store.dismissDeleteNotice()
        }
        return draft
    }

    private func makeOld(_ url: URL) throws {
        let old = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
    }
}
