import AppKit
import DraftBookCore
import UniformTypeIdentifiers

/// Turns whatever the pasteboard or the open panel hands us into a file in the
/// attachment library. Kept out of the editor so the text view only has to know
/// how to insert a Markdown line.
@MainActor
enum ImagePasteService {
    static func save(pasteboard: NSPasteboard, store: DraftStore) -> String? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let imageURL = urls.first(where: isSupportedImage) {
            return save(fileURL: imageURL, store: store)
        }

        if let png = pasteboard.data(forType: .png), !png.isEmpty {
            return save(data: png, name: "截图", extension: "png", store: store)
        }

        // Screenshot tools disagree on the flavour they put on the pasteboard
        // (TIFF, PDF, HEIC, private types). Let AppKit decode whatever it can.
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let png = pngData(fromTIFF: tiff) {
            return save(data: png, name: "截图", extension: "png", store: store)
        }

        if let tiff = pasteboard.data(forType: .tiff),
           let png = pngData(fromTIFF: tiff) {
            return save(data: png, name: "截图", extension: "png", store: store)
        }

        InteractionDiagnostics.record(
            "image.paste.unhandled",
            details: (pasteboard.types ?? []).map(\.rawValue).joined(separator: ",")
        )
        return nil
    }

    static func save(fileURL: URL, store: DraftStore) -> String? {
        guard isSupportedImage(fileURL) else { return nil }
        do {
            return try store.saveAttachment(contentsOf: fileURL)
        } catch {
            report(error)
            return nil
        }
    }

    private static func save(
        data: Data,
        name: String,
        extension fileExtension: String,
        store: DraftStore
    ) -> String? {
        do {
            return try store.saveAttachment(
                data: data,
                preferredName: name,
                fileExtension: fileExtension
            )
        } catch {
            report(error)
            return nil
        }
    }

    static func isSupportedImage(_ url: URL) -> Bool {
        AttachmentStore.supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func pngData(fromTIFF tiff: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func report(_ error: Error) {
        InteractionDiagnostics.record("image.save.failed", details: error.localizedDescription)
        NSSound.beep()
    }
}
