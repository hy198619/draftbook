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

    /// 收起状态下退出，屏外的收起位置会被存进窗口 frame；下次启动时贴边识别
    /// （`dockSide`）认不出来——它要求窗口紧贴屏幕边，而收起的窗口在边外 382 像素。
    /// 真实日志：恢复 frame `x=-382 width=390`，随后 6 次划窄边全部无响应。
    func testOldEdgeDetectionMissesRestoredCollapsedFrame() {
        XCTAssertNil(
            WindowDockGeometry.dockSide(
                for: NSRect(x: -382, y: 68, width: 390, height: 720),
                in: visibleFrame
            )
        )
    }

    /// 同一个 frame 必须被认成“左边收起”，窄边才呼得出。
    func testCollapsedSideRecognisesRestoredLeftCollapsedFrame() {
        XCTAssertEqual(
            WindowDockGeometry.collapsedSide(
                for: NSRect(x: -382, y: 68, width: 390, height: 720),
                in: visibleFrame
            ),
            .left
        )
    }

    func testCollapsedSideRecognisesRestoredRightCollapsedFrame() {
        let collapsed = WindowDockGeometry.collapsedFrame(
            from: NSRect(x: 1_050, y: 68, width: 390, height: 720),
            side: .right,
            in: visibleFrame
        )

        XCTAssertEqual(WindowDockGeometry.collapsedSide(for: collapsed, in: visibleFrame), .right)
    }

    func testCollapsedSideIgnoresOrdinaryOnscreenFrames() {
        XCTAssertNil(
            WindowDockGeometry.collapsedSide(
                for: NSRect(x: 4, y: 100, width: 390, height: 720),
                in: visibleFrame
            )
        )
        XCTAssertNil(
            WindowDockGeometry.collapsedSide(
                for: NSRect(x: 500, y: 100, width: 390, height: 720),
                in: visibleFrame
            )
        )
    }

    func testVisibleRatioSeparatesUnreachableFromNormalWindows() {
        let unreachable = WindowDockGeometry.visibleRatio(
            NSRect(x: -382, y: 68, width: 390, height: 720),
            in: visibleFrame
        )
        XCTAssertLessThan(unreachable, 0.25, "只剩 8 像素在屏内，属于叫不醒的窗口")

        XCTAssertEqual(
            WindowDockGeometry.visibleRatio(
                NSRect(x: 100, y: 100, width: 390, height: 720),
                in: visibleFrame
            ),
            1
        )
        XCTAssertEqual(
            WindowDockGeometry.visibleRatio(
                NSRect(x: 5_000, y: 5_000, width: 390, height: 720),
                in: visibleFrame
            ),
            0
        )
    }
}
