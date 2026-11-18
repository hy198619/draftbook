import XCTest
@testable import DraftBookCore

final class AttachmentStoreTests: XCTestCase {
    private var dataDirectory: URL!
    private var store: AttachmentStore!

    /// 1×1 transparent PNG — small enough to keep the fixture readable.
    private let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    override func setUpWithError() throws {
        dataDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DraftBookAttachments-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        store = AttachmentStore(dataDirectory: dataDirectory)
    }

    override func tearDownWithError() throws {
        if let dataDirectory {
            try? FileManager.default.removeItem(at: dataDirectory)
        }
    }

    func testSavingCreatesAttachmentsFolderAndRelativePath() throws {
        let path = try store.save(data: pngData, preferredName: "截图", fileExtension: "png")

        XCTAssertEqual(path, "Attachments/截图.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(forRelativePath: path).path))
    }

    func testPastingSameImageTwiceReusesOneFile() throws {
        let first = try store.save(data: pngData, preferredName: "截图", fileExtension: "png")
        let second = try store.save(data: pngData, preferredName: "截图", fileExtension: "png")

        XCTAssertEqual(first, second)
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directoryURL.path)
        XCTAssertEqual(files.count, 1)
    }

    func testDifferentImageWithSameNameGetsSuffix() throws {
        let first = try store.save(data: pngData, preferredName: "截图", fileExtension: "png")
        let different = pngData + Data([0x00])
        let second = try store.save(data: different, preferredName: "截图", fileExtension: "png")

        XCTAssertEqual(first, "Attachments/截图.png")
        XCTAssertEqual(second, "Attachments/截图-2.png")
        XCTAssertNotEqual(
            try Data(contentsOf: store.fileURL(forRelativePath: first)),
            try Data(contentsOf: store.fileURL(forRelativePath: second))
        )
    }

    func testNamesWithPathSeparatorsAreSanitized() throws {
        let path = try store.save(data: pngData, preferredName: "../evil/name", fileExtension: "png")

        XCTAssertEqual(path, "Attachments/-evil-name.png")
        XCTAssertEqual(
            store.fileURL(forRelativePath: path).deletingLastPathComponent().standardizedFileURL,
            store.directoryURL.standardizedFileURL
        )
    }

    func testExtensionNormalization() {
        XCTAssertEqual(AttachmentStore.normalizedExtension("JPEG"), "jpg")
        XCTAssertEqual(AttachmentStore.normalizedExtension("jpeg"), "jpg")
        XCTAssertEqual(AttachmentStore.normalizedExtension("HEIC"), "heic")
        XCTAssertEqual(AttachmentStore.normalizedExtension("png"), "png")
        XCTAssertEqual(AttachmentStore.normalizedExtension("gif"), "png")
    }

    func testEmptyDataIsRejected() {
        XCTAssertThrowsError(try store.save(data: Data(), preferredName: "x", fileExtension: "png"))
    }

    func testCopyingFileKeepsNameAndBytes() throws {
        let source = dataDirectory.appendingPathComponent("IMG_0001.heic")
        try pngData.write(to: source)

        let path = try store.save(contentsOf: source)

        XCTAssertEqual(path, "Attachments/IMG_0001.heic")
        XCTAssertEqual(try Data(contentsOf: store.fileURL(forRelativePath: path)), pngData)
    }

    func testUnsupportedFileTypeIsRejected() throws {
        let source = dataDirectory.appendingPathComponent("note.txt")
        try Data("hi".utf8).write(to: source)

        XCTAssertThrowsError(try store.save(contentsOf: source))
    }

    func testUnreferencedFilesSkipGracePeriod() throws {
        let path = try store.save(data: pngData, preferredName: "旧图", fileExtension: "png")
        let url = store.fileURL(forRelativePath: path)
        let old = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)

        let fresh = store.unreferencedFiles(keeping: [])
        XCTAssertEqual(fresh.map(\.lastPathComponent), ["旧图.png"])

        let withinGrace = store.unreferencedFiles(
            keeping: [],
            now: Date().addingTimeInterval(-3 * 24 * 60 * 60)
        )
        XCTAssertTrue(withinGrace.isEmpty)
    }

    func testReferencedFileIsNeverReported() throws {
        let path = try store.save(data: pngData, preferredName: "在用", fileExtension: "png")
        let url = store.fileURL(forRelativePath: path)
        let old = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)

        let files = store.unreferencedFiles(keeping: ["在用.png"])
        XCTAssertTrue(files.isEmpty)
    }
}
