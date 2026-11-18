import AppKit
import Foundation
import ImageIO
import SwiftUI

/// Renders `![alt](Attachments/x.png)` as a real image inside a draft preview.
/// Decoding goes through ImageIO with a pixel cap so a 48-megapixel photo does
/// not freeze the list, and the result is cached per file version.
struct DraftImageView: View {
    let relativePath: String
    let directoryURL: URL?

    @State private var image: NSImage?
    @State private var isMissing = false

    private var fileName: String {
        let decoded = relativePath.removingPercentEncoding ?? relativePath
        return (decoded as NSString).lastPathComponent
    }

    private var fileURL: URL? {
        guard let directoryURL, !fileName.isEmpty else { return nil }
        return directoryURL.appendingPathComponent(fileName, isDirectory: false)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 380, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            } else if isMissing {
                missingPlaceholder
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.06))
                    .frame(height: 60)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: relativePath) { load() }
    }

    private var missingPlaceholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("图片缺失")
                    .font(.system(size: 12, weight: .medium))
                Text(fileName.isEmpty ? "没有可用的附件路径" : fileName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            image = nil
            isMissing = true
            return
        }
        image = AttachmentImageCache.shared.image(for: fileURL)
        isMissing = (image == nil)
    }
}

/// Small in-memory cache keyed by path + modification date, so scrolling a long
/// draft does not re-decode the same screenshots.
final class AttachmentImageCache {
    static let shared = AttachmentImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 60
    }

    func image(for url: URL, maxPixelSize: Int = 1600) -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(Int(modified))" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        cache.setObject(image, forKey: key)
        return image
    }
}
