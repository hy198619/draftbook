import AppKit

/// The preview stays read-only. A normal click edits the draft; Command-clicking
/// a linked glyph opens its destination without changing editing state.
final class DraftLinkTextField: NSTextField {
    var onEdit: () -> Void = {}
    var onOpen: ((URL) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), let url = link(at: point) {
            if let onOpen { onOpen(url) } else { openLink(url) }
        } else {
            onEdit()
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let url = link(at: point) else { return super.menu(for: event) }
        let menu = NSMenu()
        let item = NSMenuItem(title: "打开链接", action: #selector(openMenuLink(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        menu.addItem(item)
        return menu
    }

    @objc private func openMenuLink(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        openLink(url)
    }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let url = link(at: point) {
            toolTip = "⌘ 单击打开：\(url.isFileURL ? url.path : url.absoluteString)"
            (event.modifierFlags.contains(.command) ? NSCursor.pointingHand : NSCursor.arrow).set()
        } else {
            toolTip = nil
            NSCursor.arrow.set()
        }
        super.mouseMoved(with: event)
    }

    /// Use a TextKit 1 layout solely for hit-testing. NSTextField remains the
    /// renderer, preserving its visible CJK obliqueness and current wrapping.
    func link(at point: NSPoint) -> URL? {
        let content = attributedStringValue
        guard content.length > 0 else { return nil }
        let textRect = cell?.drawingRect(forBounds: bounds) ?? bounds
        let local = NSPoint(x: point.x - textRect.minX, y: point.y - textRect.minY)
        guard local.x >= 0, local.y >= 0,
              local.x < textRect.width, local.y < textRect.height else { return nil }

        let container = NSTextContainer(size: NSSize(width: textRect.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        let layout = NSLayoutManager()
        let storage = NSTextStorage(attributedString: content)
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        guard layout.numberOfGlyphs > 0 else { return nil }

        let glyph = layout.glyphIndex(for: local, in: container)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1),
                                  in: container).contains(local) else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        return content.attribute(.link, at: character, effectiveRange: nil) as? URL
    }

    private func openLink(_ url: URL) {
        if DraftLink.needsOpenConfirmation(url) {
            let alert = NSAlert()
            alert.messageText = "打开本地可执行项目？"
            alert.informativeText = "此链接可能会启动程序或脚本：\n\(url.path)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "打开")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        guard !NSWorkspace.shared.open(url) else { return }
        let alert = NSAlert()
        alert.messageText = "无法打开链接"
        alert.informativeText = url.isFileURL ? url.path : url.absoluteString
        alert.runModal()
    }
}
