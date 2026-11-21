import XCTest
@testable import DraftBook

/// 悬停呼出调度的回归测试。
///
/// 用例里的抖动序列取自 0.9.8 真实诊断日志（11-05 13:24:37–13:25:11：33 秒内
/// 22 次悬停、0 次成功）：标题栏带与顶部窄条会交替上报 enter/exit，旧实现在每个
/// enter 上都 cancel 再重起 1 秒计时，倒计时被永久归零。
final class HeaderHoverPlanTests: XCTestCase {
    func testFirstEnterStartsCountdownAndFlapsDoNotRestartIt() {
        var visible = false
        var pending = false
        var started = 0
        var hovered = true

        // 同一秒内反复抖动的 hover 事件流（true = 在顶部区域内）
        let flap: [Bool] = [true, true, false, true, true, false, false, true, false, true, true, false]

        for hovering in flap {
            hovered = hovering
            if hovering {
                let plan = HeaderHoverPlan.onEnter(visible: visible, revealPending: pending)
                if plan == .startReveal {
                    started += 1
                    pending = true
                } else {
                    XCTAssertEqual(plan, .none, "已有倒计时在跑时不该再动作：\(plan)")
                }
            } else {
                _ = HeaderHoverPlan.onExit(visible: visible, mustRemainVisible: false)
            }
        }

        XCTAssertEqual(started, 1, "抖动把倒计时重起了 \(started) 次")
        XCTAssertTrue(pending, "倒计时必须还在跑，否则永远数不满 1 秒")

        // 到点时鼠标仍在顶部：工具栏呼出
        XCTAssertEqual(HeaderHoverPlan.onTick(stillHovering: true, visible: false), .reveal)
        visible = true
        pending = false
    }

    func testEnterAfterRevealDoesNotReschedule() {
        XCTAssertEqual(HeaderHoverPlan.onEnter(visible: true, revealPending: false), .none)
    }

    /// 真的走掉了就不该把工具栏弹出来。
    func testPointerThatLeftSkipsReveal() {
        XCTAssertEqual(HeaderHoverPlan.onTick(stillHovering: false, visible: false), .none)
    }

    func testRevealAlreadyVisibleIsNoop() {
        XCTAssertEqual(HeaderHoverPlan.onTick(stillHovering: true, visible: true), .none)
    }

    func testExitHidesOnlyWhenVisible() {
        XCTAssertEqual(HeaderHoverPlan.onExit(visible: false, mustRemainVisible: false), .none)
        XCTAssertEqual(HeaderHoverPlan.onExit(visible: true, mustRemainVisible: false), .hide)
        XCTAssertEqual(HeaderHoverPlan.onExit(visible: true, mustRemainVisible: true), .none)
    }

    /// 搜索框或分类菜单开着时，工具栏不能被收起。
    func testHideTickRespectsHoverAndPinnedUI() {
        XCTAssertEqual(HeaderHoverPlan.onHideTick(stillHovering: true, mustRemainVisible: false), .none)
        XCTAssertEqual(HeaderHoverPlan.onHideTick(stillHovering: false, mustRemainVisible: true), .none)
        XCTAssertEqual(HeaderHoverPlan.onHideTick(stillHovering: false, mustRemainVisible: false), .hide)
    }
}
