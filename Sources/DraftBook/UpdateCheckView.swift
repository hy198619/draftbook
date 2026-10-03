import AppKit
import SwiftUI

struct UpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var release: UpdateRelease?
    @State private var isChecking = true
    @State private var isDownloading = false
    @State private var message: String?
    @State private var downloadedURL: URL?

    private var currentVersion: AppVersion {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            ?? AppVersion("0.0.0")!
    }

    private var newerRelease: UpdateRelease? {
        guard let release, let version = release.version, version > currentVersion else { return nil }
        return release
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("检查更新")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Text("当前版本：\(currentVersion)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if isChecking || isDownloading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(isDownloading ? "正在从 GitHub 下载并校验安装包…" : "正在查询 GitHub Release…")
                }
                .font(.system(size: 13))
            } else if let message {
                Text(message)
                    .font(.system(size: 13))
            }

            if let newerRelease, !isChecking {
                if let notes = newerRelease.body, !notes.isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 145)
                    .padding(10)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }

                Text("下载后会打开 DMG。请退出旧版，再将新草稿本拖入“应用程序”并选择替换；草稿数据不会随应用替换而删除。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                if let newerRelease, let releasePageURL = newerRelease.releasePageURL {
                    Button("查看发布页面") {
                        NSWorkspace.shared.open(releasePageURL)
                    }
                }
                Spacer()
                if let downloadedURL {
                    Button("打开已下载的安装包") {
                        NSWorkspace.shared.open(downloadedURL)
                    }
                    .buttonStyle(.borderedProminent)
                } else if let newerRelease {
                    Button("下载并打开安装包") {
                        Task { await download(newerRelease) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloading)
                } else if !isChecking {
                    Button("重新检查") {
                        Task { await check() }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 340)
        .task { await check() }
    }

    @MainActor
    private func check() async {
        isChecking = true
        message = nil
        do {
            release = try await UpdateService.latestRelease()
            if let newerRelease, let version = newerRelease.version {
                message = "发现新版本 \(version)。"
            } else {
                message = "没有比当前版本更新的公开版本。"
            }
        } catch {
            release = nil
            message = "检查失败：\(error.localizedDescription)"
        }
        isChecking = false
    }

    @MainActor
    private func download(_ release: UpdateRelease) async {
        isDownloading = true
        message = nil
        do {
            let url = try await UpdateService.downloadVerifiedInstaller(for: release)
            downloadedURL = url
            if NSWorkspace.shared.open(url) {
                message = "安装包已通过 SHA-256 校验，并保存在“下载”文件夹。"
            } else {
                message = "安装包已校验并保存到“下载”文件夹，但未能自动打开。"
            }
        } catch {
            message = "下载失败：\(error.localizedDescription)"
        }
        isDownloading = false
    }
}
