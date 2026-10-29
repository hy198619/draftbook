import Foundation

final class DiagnosticLogStore: @unchecked Sendable {
    static let shared = DiagnosticLogStore()

    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let maximumLogSize: Int
    private let logDirectoryURL: URL
    private let currentLogURL: URL
    private let previousLogURL: URL

    private convenience init() {
        self.init(baseDirectoryURL: Self.defaultBaseDirectoryURL())
    }

    init(baseDirectoryURL: URL, maximumLogSize: Int = 512 * 1_024) {
        self.maximumLogSize = maximumLogSize
        logDirectoryURL = baseDirectoryURL.appendingPathComponent("Diagnostics", isDirectory: true)
        currentLogURL = logDirectoryURL.appendingPathComponent("DraftBook.log")
        previousLogURL = logDirectoryURL.appendingPathComponent("DraftBook.previous.log")
    }

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
            try rotateIfNeeded()

            let timestamp = ISO8601DateFormatter().string(from: .now)
            let data = Data("\(timestamp) \(line)\n".utf8)
            if !fileManager.fileExists(atPath: currentLogURL.path) {
                fileManager.createFile(atPath: currentLogURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: currentLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Diagnostics must never interfere with normal app startup or editing.
        }
    }

    func makeReport() -> String {
        lock.lock()
        defer { lock.unlock() }

        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unknown"
        #endif

        let header = [
            "DraftBook diagnostic report",
            "Exported: \(ISO8601DateFormatter().string(from: .now))",
            "App version: \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Architecture: \(architecture)",
            "App location: \(redactedPath(bundle.bundleURL.path))",
            "Privacy: This report excludes draft text, search queries, label names and clipboard contents.",
            ""
        ].joined(separator: "\n")

        let previous = (try? String(contentsOf: previousLogURL, encoding: .utf8)) ?? ""
        let current = (try? String(contentsOf: currentLogURL, encoding: .utf8)) ?? ""
        let events = [previous, current].filter { !$0.isEmpty }.joined()
        return header + (events.isEmpty ? "No diagnostic events recorded yet.\n" : events)
    }

    private func rotateIfNeeded() throws {
        guard fileManager.fileExists(atPath: currentLogURL.path) else { return }
        guard let size = try fileManager.attributesOfItem(atPath: currentLogURL.path)[.size] as? NSNumber,
              size.intValue >= maximumLogSize else { return }

        if fileManager.fileExists(atPath: previousLogURL.path) {
            try fileManager.removeItem(at: previousLogURL)
        }
        try fileManager.moveItem(at: currentLogURL, to: previousLogURL)
    }

    private static func defaultBaseDirectoryURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["DRAFTBOOK_DATA_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("com.yangyuxuan.DraftBook", isDirectory: true)
    }

    private func redactedPath(_ path: String) -> String {
        let home = fileManager.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
