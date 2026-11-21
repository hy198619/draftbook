import Foundation

/// 悬停呼出工具栏的调度决策，抽成纯类型以便单测。
///
/// AppKit 在标题栏 44 像素带和顶部窄条之间会连续发几十次 enter/exit 事件，窗口
/// 收起、展开、激活时还会再来一轮。0.9.8 的实测日志里，有一次 33 秒内 22 次悬停
/// 全部失败：因为每个 enter 事件都 cancel 掉正在倒计时的任务再重新起一个 1 秒，
/// 计时器被无限归零，`headerVisible` 永远等不到 1 秒的连续静默。
///
/// 新规则改成两句话：倒计时只在“没有任何任务在跑”时启动；到点时再看鼠标此刻是否
/// 仍停在顶部区域。事件抖动因此不再影响计时，而真正离开的鼠标也不会呼出工具栏。
enum HeaderHoverPlan: Equatable {
    case none
    case startReveal
    case reveal
    case hide

    /// 鼠标进入（或又一个 enter 事件到达）。
    static func onEnter(visible: Bool, revealPending: Bool) -> HeaderHoverPlan {
        guard !visible else { return .none }
        return revealPending ? .none : .startReveal
    }

    /// 鼠标离开。不取消正在跑的倒计时——短暂抖动不该让已经累计的时间作废；
    /// 是否真要显示，交给到点时的 `onTick` 判断。
    static func onExit(visible: Bool, mustRemainVisible: Bool) -> HeaderHoverPlan {
        guard !mustRemainVisible, visible else { return .none }
        return .hide
    }

    /// 倒计时到点。
    static func onTick(stillHovering: Bool, visible: Bool) -> HeaderHoverPlan {
        guard stillHovering, !visible else { return .none }
        return .reveal
    }

    /// 隐藏任务到点。
    static func onHideTick(stillHovering: Bool, mustRemainVisible: Bool) -> HeaderHoverPlan {
        guard !stillHovering, !mustRemainVisible else { return .none }
        return .hide
    }
}
