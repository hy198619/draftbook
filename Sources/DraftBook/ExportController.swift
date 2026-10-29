import AppKit
import DraftBookCore
import UniformTypeIdentifiers

@MainActor
enum ExportController {
    enum Kind {
        case plainText
        case markdown
        case fullBackup

        var filename: String {
            switch self {
            case .plainText: "草稿本导出.txt"
            case .markdown: "草稿本导出.md"
            case .fullBackup: "草稿本完整备份.json"
            }
        }

        var contentType: UTType {
            switch self {
            case .plainText: .plainText
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            case .fullBackup: .json
            }
        }
    }

    static func export(_ kind: Kind, from store: DraftStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = kind.filename
        panel.allowedContentTypes = [kind.contentType]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data: Data
                switch kind {
                case .plainText:
                    data = Data(store.exportPlainText().utf8)
                case .markdown:
                    data = Data(store.exportMarkdown().utf8)
                case .fullBackup:
                    data = try store.fullBackupData()
                }
                try data.write(to: url, options: [.atomic])
            } catch {
                showExportError(error)
            }
        }
    }

    static func openBackupFolder(for store: DraftStore) {
        do {
            try FileManager.default.createDirectory(
                at: store.backupDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(store.backupDirectoryURL)
        } catch {
            showExportError(error)
        }
    }

    static func openDataFolder(for store: DraftStore) {
        do {
            try FileManager.default.createDirectory(
                at: store.dataDirectoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(store.dataDirectoryURL)
        } catch {
            showExportError(error)
        }
    }

    static func exportDiagnostics() {
        InteractionDiagnostics.record("diagnostics.exportRequested")

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "草稿本诊断日志.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let report = DiagnosticLogStore.shared.makeReport()
                try Data(report.utf8).write(to: url, options: [.atomic])
                InteractionDiagnostics.record("diagnostics.exportSucceeded")
            } catch {
                InteractionDiagnostics.record(
                    "diagnostics.exportFailed",
                    details: "errorType=\(String(describing: type(of: error)))"
                )
                showExportError(error)
            }
        }
    }

    static func importFullBackup(into store: DraftStore) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "选择由草稿本导出的完整 JSON 备份"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let confirmation = NSAlert()
            confirmation.messageText = "恢复这份完整备份？"
            confirmation.informativeText = "当前内容会先自动保存为一份恢复前备份，然后替换为所选备份中的内容。"
            confirmation.alertStyle = .warning
            confirmation.addButton(withTitle: "恢复")
            confirmation.addButton(withTitle: "取消")
            guard confirmation.runModal() == .alertFirstButtonReturn else { return }

            do {
                let data = try Data(contentsOf: url)
                try store.restoreFullBackupData(data)

                let success = NSAlert()
                success.messageText = "恢复完成"
                success.informativeText = "草稿内容已经替换，恢复前的数据仍保存在自动备份文件夹中。"
                success.runModal()
            } catch {
                showImportError(error)
            }
        }
    }

    private static func showExportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "导出失败"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func showImportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法恢复备份"
        alert.informativeText = "请选择由草稿本导出的完整 JSON 备份。\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
