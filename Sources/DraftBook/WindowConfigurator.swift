import AppKit
import SwiftUI

enum WindowDockSide: Equatable {
    case left
    case right
}

enum WindowDockGeometry {
    static let snapThreshold: CGFloat = 10
    static let exposedWidth: CGFloat = 8

    static func dockSide(
        for windowFrame: NSRect,
        in visibleFrame: NSRect,
        threshold: CGFloat = snapThreshold
    ) -> WindowDockSide? {
        let leftDistance = abs(windowFrame.minX - visibleFrame.minX)
        let rightDistance = abs(windowFrame.maxX - visibleFrame.maxX)
        let nearestDistance = min(leftDistance, rightDistance)
        guard nearestDistance <= threshold else { return nil }
        return leftDistance <= rightDistance ? .left : .right
    }

    static func expandedFrame(
        from windowFrame: NSRect,
        side: WindowDockSide,
        in visibleFrame: NSRect
    ) -> NSRect {
        var result = windowFrame
        switch side {
        case .left:
            result.origin.x = visibleFrame.minX
        case .right:
            result.origin.x = visibleFrame.maxX - windowFrame.width
        }
        return result
    }

    static func collapsedFrame(
        from expandedFrame: NSRect,
        side: WindowDockSide,
        in visibleFrame: NSRect,
        exposedWidth: CGFloat = exposedWidth
    ) -> NSRect {
        var result = expandedFrame
        switch side {
        case .left:
            result.origin.x = visibleFrame.minX - expandedFrame.width + exposedWidth
        case .right:
            result.origin.x = visibleFrame.maxX - exposedWidth
        }
        return result
    }

    static func constrainedFrame(_ windowFrame: NSRect, in visibleFrame: NSRect) -> NSRect {
        var result = windowFrame
        result.size.width = min(result.width, visibleFrame.width)
        result.size.height = min(result.height, visibleFrame.height)
        result.origin.x = min(max(result.minX, visibleFrame.minX), visibleFrame.maxX - result.width)
        result.origin.y = min(max(result.minY, visibleFrame.minY), visibleFrame.maxY - result.height)
        return result
    }
}

struct WindowConfigurator: NSViewRepresentable {
    var floating: Bool
    var autoHideAtScreenEdge: Bool
    var onTopEdgeHoverChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.coordinator = context.coordinator
        view.onTopEdgeHoverChanged = onTopEdgeHoverChanged
        DispatchQueue.main.async {
            context.coordinator.configure(
                window: view.window,
                floating: floating,
                autoHideAtScreenEdge: autoHideAtScreenEdge
            )
        }
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        nsView.onTopEdgeHoverChanged = onTopEdgeHoverChanged
        DispatchQueue.main.async {
            context.coordinator.configure(
                window: nsView.window,
                floating: floating,
                autoHideAtScreenEdge: autoHideAtScreenEdge
            )
        }
    }

    static func dismantleNSView(_ nsView: WindowTrackingView, coordinator: Coordinator) {
        nsView.stopTopEdgeMonitoring()
        nsView.onTopEdgeHoverChanged = nil
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        private enum DockState: Equatable {
            case normal
            case expanded(WindowDockSide)
            case collapsed(WindowDockSide)
        }

        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var dockState: DockState = .normal
        private var expandedFrame: NSRect?
        private var dockVisibleFrame: NSRect?
        private var dockDetectionWorkItem: DispatchWorkItem?
        private var collapseWorkItem: DispatchWorkItem?
        private var interactionMonitor: Any?
        private var isAdjustingFrame = false
        private var autoHideAtScreenEdge = false
        private var pointerInsideWindow = false
        private var observedUserWindowDrag = false

        func configure(window: NSWindow?, floating: Bool, autoHideAtScreenEdge: Bool) {
            guard let window else { return }

            if self.window !== window {
                attach(to: window)
            }

            window.level = floating ? .floating : .normal
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.minSize = NSSize(width: 320, height: 420)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.acceptsMouseMovedEvents = true

            guard self.autoHideAtScreenEdge != autoHideAtScreenEdge else { return }
            self.autoHideAtScreenEdge = autoHideAtScreenEdge
            if !autoHideAtScreenEdge {
                restoreNormalWindowPosition()
            }
        }

        func pointerEntered() {
            pointerInsideWindow = true
            collapseWorkItem?.cancel()
            InteractionDiagnostics.record(
                "edge.pointerEntered",
                window: window,
                details: "dockState=\(dockStateDescription)"
            )
            if case .collapsed = dockState {
                // Make the revealed window immediately hit-testable. Animating the
                // frame here creates a brief interval where the visible editor and
                // the window's actual click target do not yet line up.
                revealWindow(animated: false)
            }
        }

        func pointerExited() {
            pointerInsideWindow = false
            InteractionDiagnostics.record(
                "edge.pointerExited",
                window: window,
                details: "dockState=\(dockStateDescription)"
            )
            scheduleCollapse(after: 2.5, allowKeyWindow: true)
        }

        func stop() {
            dockDetectionWorkItem?.cancel()
            collapseWorkItem?.cancel()
            restoreExpandedFrameBeforeClosing()
            if let interactionMonitor {
                NSEvent.removeMonitor(interactionMonitor)
                self.interactionMonitor = nil
            }
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            window = nil
        }

        private func attach(to window: NSWindow) {
            stop()
            self.window = window

            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                    self?.windowDidMove()
                },
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.windowDidResize()
                },
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.windowDidBecomeKey()
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.windowDidResignKey()
                },
                center.addObserver(
                    forName: NSApplication.didChangeScreenParametersNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.screenParametersDidChange()
                },
                center.addObserver(
                    forName: NSApplication.willTerminateNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.restoreExpandedFrameBeforeClosing()
                }
            ]

            interactionMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            ) { [weak self] event in
                if event.type == .leftMouseDown, let self {
                    let targetsWindow = event.window === self.window
                    let hitView = targetsWindow
                        ? self.window?.contentView?.hitTest(event.locationInWindow)
                            .map { String(describing: type(of: $0)) } ?? "nil"
                        : "otherWindow"
                    InteractionDiagnostics.record(
                        "event.leftMouseDown",
                        window: self.window,
                        details: "targetsWindow=\(targetsWindow) hitView=\(hitView) dockState=\(self.dockStateDescription)"
                    )
                }
                self?.prepareWindowForInteraction(with: event)
                self?.userDidInteract()
                return event
            }
        }

        private func prepareWindowForInteraction(with event: NSEvent) {
            guard event.type == .leftMouseDown,
                  let window,
                  event.window === window,
                  case .expanded = dockState else { return }

            collapseWorkItem?.cancel()
            InteractionDiagnostics.record(
                "window.prepareActivation.before",
                window: window,
                details: "dockState=\(dockStateDescription)"
            )
            ApplicationRuntime.activateIfNeeded()
            if !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
            }
            InteractionDiagnostics.record(
                "window.prepareActivation.after",
                window: window,
                details: "dockState=\(dockStateDescription)"
            )
            DispatchQueue.main.async { [weak self, weak window] in
                if let window, !window.isKeyWindow {
                    window.makeKeyAndOrderFront(nil)
                }
                InteractionDiagnostics.record(
                    "window.prepareActivation.nextRunLoop",
                    window: window,
                    details: "dockState=\(self?.dockStateDescription ?? "released")"
                )
            }
        }

        private func userDidInteract() {
            guard autoHideAtScreenEdge, case .expanded = dockState else { return }
            if pointerInsideWindow {
                collapseWorkItem?.cancel()
            } else {
                scheduleCollapse(after: 2.5, allowKeyWindow: true)
            }
        }

        private func windowDidMove() {
            guard autoHideAtScreenEdge, !isAdjustingFrame, let window else { return }
            guard !window.inLiveResize else { return }

            switch dockState {
            case .normal:
                observedUserWindowDrag = true
                scheduleDockDetection()
            case let .expanded(side):
                guard let visibleFrame = dockVisibleFrame else {
                    dockState = .normal
                    return
                }
                let expected = WindowDockGeometry.expandedFrame(
                    from: window.frame,
                    side: side,
                    in: visibleFrame
                )
                if abs(expected.minX - window.frame.minX) > 2 {
                    dockState = .normal
                    expandedFrame = nil
                    dockVisibleFrame = nil
                    observedUserWindowDrag = true
                    scheduleDockDetection()
                } else {
                    expandedFrame = window.frame
                }
            case .collapsed:
                break
            }
        }

        private func windowDidResize() {
            guard !isAdjustingFrame else { return }
            if case let .expanded(side) = dockState,
               let window,
               let visibleFrame = dockVisibleFrame {
                let alignedFrame = WindowDockGeometry.expandedFrame(
                    from: window.frame,
                    side: side,
                    in: visibleFrame
                )
                expandedFrame = alignedFrame
                if alignedFrame != window.frame {
                    setFrame(alignedFrame, animated: false)
                }
            }
        }

        private func windowDidBecomeKey() {
            collapseWorkItem?.cancel()
            InteractionDiagnostics.record(
                "window.didBecomeKey",
                window: window,
                details: "dockState=\(dockStateDescription)"
            )
            if case .collapsed = dockState {
                revealWindow()
            }
        }

        private func windowDidResignKey() {
            InteractionDiagnostics.record(
                "window.didResignKey",
                window: window,
                details: "dockState=\(dockStateDescription) pointerInside=\(pointerInsideWindow)"
            )
            guard !pointerInsideWindow else { return }
            scheduleCollapse(after: 2.5, allowKeyWindow: false)
        }

        private func scheduleDockDetection() {
            dockDetectionWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.detectDockingAfterMove()
            }
            dockDetectionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
        }

        private func detectDockingAfterMove() {
            guard autoHideAtScreenEdge,
                  dockState == .normal,
                  observedUserWindowDrag,
                  let window,
                  !window.styleMask.contains(.fullScreen),
                  !window.isZoomed else { return }

            if NSEvent.pressedMouseButtons & 1 != 0 {
                scheduleDockDetection()
                return
            }

            observedUserWindowDrag = false

            guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame,
                  let side = WindowDockGeometry.dockSide(for: window.frame, in: visibleFrame) else { return }

            let alignedFrame = WindowDockGeometry.expandedFrame(
                from: window.frame,
                side: side,
                in: visibleFrame
            )
            expandedFrame = alignedFrame
            dockVisibleFrame = visibleFrame
            dockState = .expanded(side)
            InteractionDiagnostics.record(
                "edge.dockDetected",
                window: window,
                details: "side=\(side) frame=\(NSStringFromRect(window.frame))"
            )
            setFrame(alignedFrame, animated: true)

            scheduleCollapse(after: 0.9, allowKeyWindow: true)
        }

        private func scheduleCollapse(after delay: TimeInterval, allowKeyWindow: Bool) {
            guard autoHideAtScreenEdge else { return }
            guard case .expanded = dockState else { return }
            collapseWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.collapseWindow(allowKeyWindow: allowKeyWindow)
            }
            collapseWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func collapseWindow(allowKeyWindow: Bool) {
            guard autoHideAtScreenEdge,
                  case let .expanded(side) = dockState,
                  let window,
                  let expandedFrame,
                  let visibleFrame = dockVisibleFrame,
                  window.attachedSheet == nil,
                  !window.styleMask.contains(.fullScreen),
                  allowKeyWindow || !window.isKeyWindow else { return }

            InteractionDiagnostics.record(
                "edge.collapse.begin",
                window: window,
                details: "side=\(side) allowKeyWindow=\(allowKeyWindow)"
            )

            if let textView = window.firstResponder as? NSTextView, textView.hasMarkedText() {
                scheduleCollapse(after: 1, allowKeyWindow: allowKeyWindow)
                return
            }

            if allowKeyWindow, window.isKeyWindow {
                window.makeFirstResponder(nil)
            }

            let hiddenFrame = WindowDockGeometry.collapsedFrame(
                from: expandedFrame,
                side: side,
                in: visibleFrame
            )
            dockState = .collapsed(side)
            setFrame(hiddenFrame, animated: true)
            InteractionDiagnostics.record(
                "edge.collapse.end",
                window: window,
                details: "side=\(side)"
            )
        }

        private func revealWindow(animated: Bool = true) {
            guard case let .collapsed(side) = dockState,
                  let expandedFrame else { return }
            InteractionDiagnostics.record(
                "edge.reveal.begin",
                window: window,
                details: "side=\(side) animated=\(animated)"
            )
            collapseWorkItem?.cancel()
            dockState = .expanded(side)
            window?.orderFrontRegardless()
            setFrame(expandedFrame, animated: animated)
            InteractionDiagnostics.record(
                "edge.reveal.end",
                window: window,
                details: "side=\(side) animated=\(animated)"
            )
        }

        private var dockStateDescription: String {
            switch dockState {
            case .normal:
                return "normal"
            case let .expanded(side):
                return "expanded.\(side)"
            case let .collapsed(side):
                return "collapsed.\(side)"
            }
        }

        private func restoreNormalWindowPosition() {
            dockDetectionWorkItem?.cancel()
            collapseWorkItem?.cancel()
            restoreExpandedFrameBeforeClosing()
            dockState = .normal
            expandedFrame = nil
            dockVisibleFrame = nil
            observedUserWindowDrag = false
        }

        private func restoreExpandedFrameBeforeClosing() {
            guard case .collapsed = dockState, let expandedFrame else { return }
            setFrame(expandedFrame, animated: false)
        }

        private func screenParametersDidChange() {
            guard let window else { return }
            restoreNormalWindowPosition()
            guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
            let safeFrame = WindowDockGeometry.constrainedFrame(window.frame, in: visibleFrame)
            setFrame(safeFrame, animated: false)
        }

        private func setFrame(_ frame: NSRect, animated: Bool) {
            guard let window else { return }
            isAdjustingFrame = true

            let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            guard shouldAnimate else {
                window.setFrame(frame, display: true)
                isAdjustingFrame = false
                return
            }

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                self?.isAdjustingFrame = false
            }
        }
    }
}

final class WindowTrackingView: NSView {
    private static let topEdgeHoverHeight: CGFloat = 44
    private static let topEdgePollingInterval: TimeInterval = 0.05

    weak var coordinator: WindowConfigurator.Coordinator?
    var onTopEdgeHoverChanged: ((Bool) -> Void)?
    private var pointerTrackingArea: NSTrackingArea?
    private var topEdgeHoverTimer: Timer?
    private var pointerInsideTopEdge = false
    private var reportedTopEdgeHover = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.startTopEdgeMonitoring()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        pointerTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        coordinator?.pointerEntered()
    }

    override func mouseExited(with event: NSEvent) {
        coordinator?.pointerExited()
    }

    func stopTopEdgeMonitoring() {
        topEdgeHoverTimer?.invalidate()
        topEdgeHoverTimer = nil
        pointerInsideTopEdge = false
        reportedTopEdgeHover = false
    }

    private func startTopEdgeMonitoring() {
        guard topEdgeHoverTimer == nil else { return }
        updateTopEdgeHover()
        let timer = Timer(timeInterval: Self.topEdgePollingInterval, repeats: true) { [weak self] _ in
            self?.updateTopEdgeHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        topEdgeHoverTimer = timer
    }

    private func updateTopEdgeHover() {
        guard let window, window.isVisible else {
            setTopEdgeHovered(false)
            return
        }

        let frame = window.frame
        let hoverRect = NSRect(
            x: frame.minX,
            y: frame.maxY - min(Self.topEdgeHoverHeight, frame.height),
            width: frame.width,
            height: min(Self.topEdgeHoverHeight, frame.height)
        )
        setTopEdgeHovered(hoverRect.contains(NSEvent.mouseLocation))
    }

    private func setTopEdgeHovered(_ hovered: Bool) {
        guard pointerInsideTopEdge != hovered else { return }
        pointerInsideTopEdge = hovered
        InteractionDiagnostics.record(
            hovered ? "toolbar.topEdgeEntered" : "toolbar.topEdgeExited",
            window: window,
            details: "source=windowCoordinates height=\(Self.topEdgeHoverHeight)"
        )
        publishTopEdgeHoverIfNeeded()
    }

    private func publishTopEdgeHoverIfNeeded() {
        let hovered = pointerInsideTopEdge
        guard reportedTopEdgeHover != hovered else { return }
        reportedTopEdgeHover = hovered
        onTopEdgeHoverChanged?(hovered)
    }

    deinit {
        stopTopEdgeMonitoring()
    }
}
