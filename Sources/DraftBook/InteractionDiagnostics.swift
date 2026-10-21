import AppKit
import OSLog

enum InteractionDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yangyuxuan.DraftBook",
        category: "WindowFocus"
    )

    static func record(
        _ event: String,
        window: NSWindow? = nil,
        details: String = ""
    ) {
        let responder = window?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let windowNumber = window?.windowNumber ?? -1
        let line = [
            event,
            "appActive=\(NSApp.isActive)",
            "window=\(windowNumber)",
            "visible=\(window?.isVisible ?? false)",
            "key=\(window?.isKeyWindow ?? false)",
            "main=\(window?.isMainWindow ?? false)",
            "firstResponder=\(responder)",
            details
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")

        logger.notice("\(line, privacy: .public)")
    }
}
