import DraftBookCore
import SwiftUI

@main
struct DraftBookApp: App {
    @StateObject private var store: DraftStore

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            AppPreferenceKeys.keepWindowOnTop: true,
            AppPreferenceKeys.defaultReviewDays: 7,
            AppPreferenceKeys.automaticBackupsEnabled: true,
            AppPreferenceKeys.backupRetentionCount: 14
        ])

        _store = StateObject(wrappedValue: DraftStore(
            defaultReviewDays: defaults.integer(forKey: AppPreferenceKeys.defaultReviewDays),
            automaticBackupsEnabled: defaults.bool(forKey: AppPreferenceKeys.automaticBackupsEnabled),
            backupRetentionCount: defaults.integer(forKey: AppPreferenceKeys.backupRetentionCount)
        ))
    }

    var body: some Scene {
        WindowGroup("草稿本") {
            MainView()
                .environmentObject(store)
        }
        .defaultSize(width: 390, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    NotificationCenter.default.post(name: .draftBookCheckForUpdates, object: nil)
                }
            }

            CommandGroup(replacing: .newItem) {
                Button("划定当前草稿") {
                    store.sealComposer()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }

            CommandGroup(after: .saveItem) {
                Divider()

                Button("导出纯文本…") {
                    ExportController.export(.plainText, from: store)
                }

                Button("导出 Markdown…") {
                    ExportController.export(.markdown, from: store)
                }

                Button("导出完整备份…") {
                    ExportController.export(.fullBackup, from: store)
                }

                Button("恢复完整备份…") {
                    ExportController.importFullBackup(into: store)
                }
            }

            CommandMenu("草稿") {
                Button("搜索草稿") {
                    NotificationCenter.default.post(name: .draftBookShowSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])

                Divider()

                Button("草稿区") {
                    NotificationCenter.default.post(name: .draftBookShowDrafts, object: nil)
                }

                Button("清理台") {
                    NotificationCenter.default.post(name: .draftBookShowCleanup, object: nil)
                }

                Button("存档区") {
                    NotificationCenter.default.post(name: .draftBookShowArchive, object: nil)
                }

                Button("回收站") {
                    NotificationCenter.default.post(name: .draftBookShowTrash, object: nil)
                }

                Divider()

                Button("撤销最近删除") {
                    store.undoLastDelete()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!store.canUndoLastDelete)

                Divider()

                Button("立即保存") {
                    store.flush()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandGroup(replacing: .help) {
                Button("草稿本使用说明") {
                    NotificationCenter.default.post(name: .draftBookShowGuide, object: nil)
                }

                Button("打开数据文件夹") {
                    ExportController.openDataFolder(for: store)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
