import AppKit

enum ApplicationRuntime {
    static func isActive(application: NSApplication? = NSApp) -> Bool {
        application?.isActive ?? false
    }

    static func activateIfNeeded(application: NSApplication? = NSApp) {
        let application = application ?? NSApplication.shared
        guard !application.isActive else { return }
        application.activate()
    }

    static func endKeyWindowEditing(application: NSApplication? = NSApp) {
        application?.keyWindow?.makeFirstResponder(nil)
    }
}
