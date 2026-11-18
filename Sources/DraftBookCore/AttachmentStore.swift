import Foundation

/// Draft images live beside `drafts.json` in an `Attachments/` folder and are
/// referenced from Markdown with a relative path. Copying the data folder (or
/// exporting a draft) therefore keeps the images with the text, and the editor
/// never depends on where the user's original file is.
public struct AttachmentStore {
    public enum SaveError: LocalizedError {
        case emptyImage
        case unwritable(String)

        public var errorDescription: String? {
            switch self {
            case .emptyImage:
                return "这张图片没有可保存的内容。"
            case let .unwritable(reason):
                return "无法把图片写入附件库：\(reason)"
            }
        }
    }

    public static let directoryName = "Attachments"
    public static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public init(dataDirectory: URL) {
        self.init(
            directoryURL: dataDirectory.appendingPathComponent(Self.directoryName, isDirectory: true)
        )
    }

    /// Markdown path stored in the draft text.
    public static func relativePath(forFileName name: String) -> String {
        "\(directoryName)/\(name)"
    }

    public func fileURL(forRelativePath path: String) -> URL {
        let name = (path as NSString).lastPathComponent
        return directoryURL.appendingPathComponent(name, isDirectory: false)
    }

    /// Saves `data` under a readable file name. Identical bytes reuse the file
    /// that is already on disk, so pasting the same screenshot twice costs one
    /// file. A *different* image that wants the same name gets `-2`, `-3`, …
    @discardableResult
    public func save(
        data: Data,
        preferredName: String?,
        fileExtension: String
    ) throws -> String {
        guard !data.isEmpty else { throw SaveError.emptyImage }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw SaveError.unwritable(error.localizedDescription)
        }

        let ext = Self.normalizedExtension(fileExtension)
        let base = Self.sanitizedBaseName(preferredName) ?? "图片"
        var candidate = "\(base).\(ext)"
        var index = 2

        while true {
            let url = directoryURL.appendingPathComponent(candidate, isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) {
                if let existing = try? Data(contentsOf: url), existing == data {
                    return Self.relativePath(forFileName: candidate)
                }
                candidate = "\(base)-\(index).\(ext)"
                index += 1
                continue
            }
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                throw SaveError.unwritable(error.localizedDescription)
            }
            return Self.relativePath(forFileName: candidate)
        }
    }

    /// Copies a user-selected file into the attachment library, keeping its
    /// name and (supported) format.
    @discardableResult
    public func save(contentsOf sourceURL: URL) throws -> String {
        let rawExtension = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(rawExtension) else {
            throw SaveError.unwritable("只支持 PNG、JPEG 和 HEIC 图片。")
        }
        let data = try Data(contentsOf: sourceURL)
        return try save(
            data: data,
            preferredName: sourceURL.deletingPathExtension().lastPathComponent,
            fileExtension: rawExtension
        )
    }

    public func fileName(forRelativePath path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Files that no draft references any more, oldest first. Only files older
    /// than `graceInterval` are reported so a restore or an undo can still find
    /// them; deletion itself is the caller's decision.
    public func unreferencedFiles(
        keeping referenced: Set<String>,
        now: Date = Date(),
        graceInterval: TimeInterval = 7 * 24 * 60 * 60
    ) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files.filter { url in
            guard !referenced.contains(url.lastPathComponent) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile != false else { return false }
            let modified = values?.contentModificationDate ?? .distantPast
            return now.timeIntervalSince(modified) >= graceInterval
        }
    }

    public static func normalizedExtension(_ raw: String) -> String {
        let lower = raw.lowercased()
        switch lower {
        case "jpeg", "jpg":
            return "jpg"
        case "heic":
            return "heic"
        case "png":
            return "png"
        default:
            return "png"
        }
    }

    /// Keeps user-visible names tidy: no path separators, no control
    /// characters, and short enough for every file system we support.
    public static func sanitizedBaseName(_ raw: String?) -> String? {
        guard var name = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }

        name = name.replacingOccurrences(of: "/", with: "-")
        name = name.replacingOccurrences(of: ":", with: "-")
        name = name.replacingOccurrences(of: "\u{0}", with: "")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ".").union(.whitespaces))
        if name.count > 60 {
            name = String(name.prefix(60))
        }
        return name.isEmpty ? nil : name
    }
}
