import AppKit
import DraftBookCore
import SwiftUI
import UniformTypeIdentifiers

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    var font: NSFont
    var minHeight: CGFloat
    var lineSpacing: CGFloat = 3
    var onCommit: (() -> Void)?
    /// Saves the clipboard image and returns the Markdown relative path.
    var onPasteImage: ((NSPasteboard) -> String?)?
    /// Copies a chosen file into the attachment library, same return contract.
    var onPasteFile: ((URL) -> String?)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> DraftScrollView {
        let scrollView = DraftScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = DraftTextView()
        textView.delegate = context.coordinator
        textView.commitAction = onCommit
        textView.imagePasteHandler = onPasteImage
        textView.imageFileHandler = onPasteFile
        textView.focusChanged = { [weak coordinator = context.coordinator] _, _ in
            guard let coordinator else { return }
            DispatchQueue.main.async {
                guard let current = coordinator.textView else { return }
                // A queued focus callback must never publish an older snapshot
                // over text typed or committed since that callback was queued.
                coordinator.publishText(current.string)
                coordinator.parent.isFocused = current.window?.firstResponder === current
            }
        }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 7)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        textView.string = text
        context.coordinator.applyTextStyle(force: true)
        textView.frame = NSRect(
            x: 0,
            y: 0,
            width: max(scrollView.contentSize.width, 1),
            height: minHeight
        )

        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.updateHeight()
            if isFocused {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: DraftScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }

        textView.commitAction = onCommit
        textView.imagePasteHandler = onPasteImage
        textView.imageFileHandler = onPasteFile

        // Chinese input methods keep an uncommitted "marked text" range while
        // the user is choosing candidates. Assigning `string`, restoring a
        // selection, or rewriting text attributes in that window cancels the
        // composition. A SwiftUI refresh can arrive during that composition,
        // so all mutations of NSTextView must wait until it has committed.
        if !textView.hasMarkedText() {
            context.coordinator.applyTextStyle()

            if textView.string != text {
                // A focus/layout update can arrive before SwiftUI has propagated the
                // latest NSTextView change through the binding. Never replace that
                // newer local value with the stale binding value.
                if context.coordinator.lastPublishedText != textView.string {
                    context.coordinator.applyExternalText(text)
                }
            } else if context.coordinator.lastPublishedText == text {
                context.coordinator.lastPublishedText = nil
            }
        }

        context.coordinator.updateHeight()

        if isFocused, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView scrollView: DraftScrollView,
        context: Context
    ) -> CGSize? {
        let width = max(proposal.width ?? scrollView.bounds.width, 1)
        context.coordinator.updateHeight(availableWidth: width)
        return CGSize(width: width, height: scrollView.desiredHeight)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextEditor
        weak var textView: DraftTextView?
        weak var scrollView: DraftScrollView?
        var lastPublishedText: String?
        private var isApplyingExternalText = false
        private var appliedFontSize: CGFloat?
        private var appliedLineSpacing: CGFloat?

        init(parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingExternalText else { return }
            publishText(textView.string)
            updateHeight()
        }

        func publishText(_ value: String) {
            lastPublishedText = value
            if parent.text != value {
                parent.text = value
            }
        }

        func applyExternalText(_ value: String) {
            guard let textView, !textView.hasMarkedText() else { return }
            let selectedRanges = textView.selectedRanges
            isApplyingExternalText = true
            textView.string = value
            applyTextStyle(force: true)
            isApplyingExternalText = false

            if value.isEmpty {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                let validRanges = selectedRanges.filter { rangeValue in
                    rangeValue.rangeValue.upperBound <= value.utf16.count
                }
                if !validRanges.isEmpty {
                    textView.selectedRanges = validRanges
                }
            }
        }

        func applyTextStyle(force: Bool = false) {
            guard let textView else { return }
            let fontSize = parent.font.pointSize
            guard force || appliedFontSize != fontSize || appliedLineSpacing != parent.lineSpacing else {
                return
            }

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = parent.lineSpacing
            textView.font = parent.font
            textView.defaultParagraphStyle = paragraphStyle
            textView.typingAttributes = [
                .font: parent.font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle
            ]

            if let textStorage = textView.textStorage, textStorage.length > 0 {
                textStorage.addAttributes(
                    [
                        .font: parent.font,
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: paragraphStyle
                    ],
                    range: NSRange(location: 0, length: textStorage.length)
                )
            }

            appliedFontSize = fontSize
            appliedLineSpacing = parent.lineSpacing
        }

        func updateHeight(availableWidth proposedWidth: CGFloat? = nil) {
            guard let textView,
                  let scrollView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }

            let availableWidth = max(proposedWidth ?? scrollView.contentSize.width, 1)
            if abs(textView.frame.width - availableWidth) > 0.5 {
                textView.frame.size.width = availableWidth
                textContainer.containerSize.width = availableWidth
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let insetHeight = textView.textContainerInset.height * 2
            let height = max(parent.minHeight, ceil(usedHeight + insetHeight))

            if abs(textView.frame.height - height) > 0.5 {
                textView.frame.size.height = height
            }

            if abs(scrollView.desiredHeight - height) > 0.5 {
                scrollView.desiredHeight = height
                scrollView.invalidateIntrinsicContentSize()
            }
        }
    }
}

final class DraftScrollView: NSScrollView {
    var desiredHeight: CGFloat = 44

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: desiredHeight)
    }

    override func layout() {
        super.layout()

        guard let textView = documentView as? NSTextView else { return }
        let availableWidth = max(contentSize.width, 1)
        let targetHeight = max(desiredHeight, textView.frame.height)

        if abs(textView.frame.width - availableWidth) > 0.5 ||
            abs(textView.frame.height - targetHeight) > 0.5 {
            textView.frame = NSRect(
                x: 0,
                y: 0,
                width: availableWidth,
                height: targetHeight
            )
            textView.textContainer?.containerSize.width = availableWidth
            textView.invalidateIntrinsicContentSize()
        }
    }
}

final class DraftTextView: NSTextView {
    private var outsideClickMonitor: Any?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        InteractionDiagnostics.record(
            "editor.acceptsFirstMouse",
            window: window,
            details: "eventWindow=\(event?.windowNumber ?? -1)"
        )
        return true
    }

    override func mouseDown(with event: NSEvent) {
        InteractionDiagnostics.record("editor.mouseDown.before", window: window)
        ApplicationRuntime.activateIfNeeded()
        window?.makeKeyAndOrderFront(nil)
        super.mouseDown(with: event)
        InteractionDiagnostics.record("editor.mouseDown.afterSuper", window: window)
        if window?.firstResponder !== self {
            let accepted = window?.makeFirstResponder(self) ?? false
            InteractionDiagnostics.record(
                "editor.mouseDown.forceFirstResponder",
                window: window,
                details: "accepted=\(accepted)"
            )
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            if !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
            }
            if window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
            InteractionDiagnostics.record("editor.mouseDown.nextRunLoop", window: window)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        guard window != nil else { return }
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let window = self.window,
                  event.window === window, window.firstResponder === self else { return event }
            if !self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) {
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    var commitAction: (() -> Void)?
    var focusChanged: ((Bool, String) -> Void)?
    var imagePasteHandler: ((NSPasteboard) -> String?)?
    var imageFileHandler: ((URL) -> String?)?

    // MARK: - Images

    /// Text always wins: copying from a web page, Excel or Word puts both an
    /// image and a text representation on the pasteboard, and hijacking those
    /// pastes would be far more annoying than helpful.
    override func paste(_ sender: Any?) {
        if !hasMarkedText(), pasteImageIfAvailable() { return }
        super.paste(sender)
    }

    private func pasteImageIfAvailable() -> Bool {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) != nil { return false }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let imageURL = urls.first(where: { AttachmentStore.supportedExtensions.contains($0.pathExtension.lowercased()) }),
           let path = imageFileHandler?(imageURL) {
            return insertImageReference(path)
        }

        if pasteboard.data(forType: .png) != nil || pasteboard.data(forType: .tiff) != nil,
           let path = imagePasteHandler?(pasteboard) {
            return insertImageReference(path)
        }

        return false
    }

    @discardableResult
    func insertImageReference(_ relativePath: String) -> Bool {
        let plan = MarkdownImage.insertion(
            forReference: MarkdownImage.reference(forRelativePath: relativePath),
            in: string,
            selection: selectedRange()
        )
        insertText(plan.text, replacementRange: plan.range)
        let length = (string as NSString).length
        setSelectedRange(NSRange(location: min(plan.caretLocation, length), length: 0))
        scrollRangeToVisible(selectedRange())
        return true
    }

    func presentImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "选择要插入草稿的图片"
        panel.prompt = "插入"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let path = imageFileHandler?(url) else { continue }
            insertImageReference(path)
        }
    }

    /// Routes the Edit ▸ 插入图片… menu item to whichever editor has focus.
    static func insertImageIntoFocusedEditor() {
        guard let editor = NSApp.keyWindow?.firstResponder as? DraftTextView else {
            NSSound.beep()
            return
        }
        editor.presentImagePicker()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        InteractionDiagnostics.record(
            "editor.becomeFirstResponder",
            window: window,
            details: "accepted=\(didBecomeFirstResponder)"
        )
        if didBecomeFirstResponder {
            focusChanged?(true, string)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        InteractionDiagnostics.record(
            "editor.resignFirstResponder",
            window: window,
            details: "accepted=\(didResignFirstResponder)"
        )
        if didResignFirstResponder {
            focusChanged?(false, string)
        }
        return didResignFirstResponder
    }

    override var intrinsicContentSize: NSSize {
        guard let textContainer, let layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 44)
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: ceil(usedHeight + textContainerInset.height * 2)
        )
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isCommandReturn = event.keyCode == 36 && modifiers.contains(.command)

        if isCommandReturn, !hasMarkedText() {
            commitAction?()
            return
        }

        super.keyDown(with: event)
    }
}
