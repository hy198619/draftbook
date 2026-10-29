import AppKit
import XCTest
@testable import DraftBook

final class ApplicationRuntimeTests: XCTestCase {
    func testInactiveStateIsSafeBeforeApplicationInitialization() {
        XCTAssertFalse(ApplicationRuntime.isActive(application: nil))
    }
}
