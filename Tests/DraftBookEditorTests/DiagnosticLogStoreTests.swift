import Foundation
import XCTest
@testable import DraftBook

final class DiagnosticLogStoreTests: XCTestCase {
    func testFirstEventIsWrittenWhenLogFileDoesNotExist() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DiagnosticLogStore(baseDirectoryURL: directory)
        store.append("test.firstEvent appActive=false")

        let report = store.makeReport()
        XCTAssertTrue(report.contains("test.firstEvent appActive=false"))
        XCTAssertTrue(report.contains("excludes draft text"))
    }

    func testLogRotationKeepsRecentEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DiagnosticLogStore(baseDirectoryURL: directory, maximumLogSize: 1)
        store.append("test.beforeRotation")
        store.append("test.afterRotation")

        let report = store.makeReport()
        XCTAssertTrue(report.contains("test.beforeRotation"))
        XCTAssertTrue(report.contains("test.afterRotation"))
    }
}
