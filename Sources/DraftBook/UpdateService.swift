import CryptoKit
import Foundation

struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ value: String) {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              components.compactMap({ Int($0) }).count == 3 else { return nil }
        let parts = components.compactMap { Int($0) }
        self.parts = parts
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

struct UpdateRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let body: String?
    let draft: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, draft, assets
    }

    var version: AppVersion? {
        guard tagName.first == "v" else { return nil }
        return AppVersion(String(tagName.dropFirst()))
    }

    var releasePageURL: URL? {
        guard let version, tagName == "v\(version)" else { return nil }
        return URL(string: "https://github.com/hy198619/draftbook/releases/tag/\(tagName)")
    }

    var installerName: String? {
        guard let version else { return nil }
        return "DraftBook-v\(version)-macOS-unsigned.dmg"
    }

    func verifiedAsset(named name: String) -> Asset? {
        assets.first { asset in
            asset.name == name &&
                asset.browserDownloadURL.scheme == "https" &&
                asset.browserDownloadURL.host == "github.com" &&
                asset.browserDownloadURL.path ==
                    "/hy198619/draftbook/releases/download/\(tagName)/\(name)"
        }
    }
}

enum UpdateError: LocalizedError {
    case invalidResponse
    case invalidRelease
    case missingAsset
    case invalidChecksum
    case checksumMismatch
    case noDownloadsFolder

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "无法从 GitHub 读取更新信息，请稍后重试。"
        case .invalidRelease: "没有找到可用的公开版本。"
        case .missingAsset: "最新 Release 缺少安装包或 SHA256SUMS.txt，暂不能安全下载。"
        case .invalidChecksum: "发布的校验文件格式不正确，已停止下载。"
        case .checksumMismatch: "安装包 SHA-256 校验未通过，已停止安装。"
        case .noDownloadsFolder: "无法找到下载文件夹。"
        }
    }
}

enum UpdateService {
    private static let releasesURL = URL(string:
        "https://api.github.com/repos/hy198619/draftbook/releases?per_page=100"
    )!

    static func latestRelease() async throws -> UpdateRelease {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DraftBook/0.9.6", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else {
            throw UpdateError.invalidResponse
        }
        let releases = try JSONDecoder().decode([UpdateRelease].self, from: data)
        guard let release = newestPublishedRelease(in: releases) else {
            throw UpdateError.invalidRelease
        }
        return release
    }

    static func newestPublishedRelease(in releases: [UpdateRelease]) -> UpdateRelease? {
        releases.compactMap { release -> (UpdateRelease, AppVersion)? in
            guard !release.draft, let version = release.version,
                  release.tagName == "v\(version)" else { return nil }
            return (release, version)
        }.max { $0.1 < $1.1 }?.0
    }

    static func expectedChecksum(for filename: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, fields[1] == Substring(filename), fields[0].count == 64,
                  fields[0].allSatisfy(\.isHexDigit) else { continue }
            return fields[0].lowercased()
        }
        return nil
    }

    static func downloadVerifiedInstaller(for release: UpdateRelease) async throws -> URL {
        guard let filename = release.installerName,
              let installer = release.verifiedAsset(named: filename),
              let checksums = release.verifiedAsset(named: "SHA256SUMS.txt") else {
            throw UpdateError.missingAsset
        }

        let (sumData, sumResponse) = try await URLSession.shared.data(from: checksums.browserDownloadURL)
        guard (sumResponse as? HTTPURLResponse)?.statusCode == 200,
              sumData.count < 100_000,
              let sums = String(data: sumData, encoding: .utf8),
              let expected = expectedChecksum(for: filename, in: sums) else {
            throw UpdateError.invalidChecksum
        }

        let (temporaryURL, downloadResponse) = try await URLSession.shared.download(from: installer.browserDownloadURL)
        guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.invalidResponse
        }
        let digest = SHA256.hash(data: try Data(contentsOf: temporaryURL))
            .map { String(format: "%02x", $0) }.joined()
        guard digest == expected else { throw UpdateError.checksumMismatch }

        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw UpdateError.noDownloadsFolder
        }
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let destination = availableDestination(for: filename, in: downloads)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private static func availableDestination(for filename: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
        let first = folder.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: first.path) else { return first }
        let stem = String(filename.dropLast(4))
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent("\(stem)-\(number).dmg")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}
