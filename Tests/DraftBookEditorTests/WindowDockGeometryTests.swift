import AppKit
import XCTest
@testable import DraftBook

final class WindowDockGeometryTests: XCTestCase {
    private let visibleFrame = NSRect(x: 0, y: 25, width: 1_440, height: 875)

    func testDetectsOnlyFramesNearLeftOrRightEdge() {
        XCTAssertEqual(
            WindowDockGeometry.dockSide(
                for: NSRect(x: 4, y: 100, width: 390, height: 720),
                in: visibleFrame
            ),
            .left
        )
        XCTAssertEqual(
            WindowDockGeometry.dockSide(
                for: NSRect(x: 1_047, y: 100, width: 390, height: 720),
                in: visibleFrame
            ),
            .right
        )
        XCTAssertNil(
            WindowDockGeometry.dockSide(
                for: NSRect(x: 500, y: 100, width: 390, height: 720),
                in: visibleFrame
            )
        )
    }

    func testExpandedFrameAlignsToSelectedEdge() {
        let frame = NSRect(x: 6, y: 100, width: 390, height: 720)

        XCTAssertEqual(
            WindowDockGeometry.expandedFrame(from: frame, side: .left, in: visibleFrame).minX,
            visibleFrame.minX
        )
        XCTAssertEqual(
            WindowDockGeometry.expandedFrame(from: frame, side: .right, in: visibleFrame).maxX,
            visibleFrame.maxX
        )
    }

    func testCollapsedFrameLeavesEightPointHandleVisible() {
        let leftFrame = NSRect(x: 0, y: 100, width: 390, height: 720)
        let rightFrame = NSRect(x: 1_050, y: 100, width: 390, height: 720)

        XCTAssertEqual(
            WindowDockGeometry.collapsedFrame(
                from: leftFrame,
                side: .left,
                in: visibleFrame
            ).maxX,
            visibleFrame.minX + WindowDockGeometry.exposedWidth
        )
        XCTAssertEqual(
            WindowDockGeometry.collapsedFrame(
                from: rightFrame,
                side: .right,
                in: visibleFrame
            ).minX,
            visibleFrame.maxX - WindowDockGeometry.exposedWidth
        )
    }

    func testConstrainedFrameReturnsOffscreenWindowToVisibleArea() {
        let offscreen = NSRect(x: -380, y: 980, width: 390, height: 720)
        let result = WindowDockGeometry.constrainedFrame(offscreen, in: visibleFrame)

        XCTAssertGreaterThanOrEqual(result.minX, visibleFrame.minX)
        XCTAssertLessThanOrEqual(result.maxX, visibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(result.minY, visibleFrame.minY)
        XCTAssertLessThanOrEqual(result.maxY, visibleFrame.maxY)
    }
}
