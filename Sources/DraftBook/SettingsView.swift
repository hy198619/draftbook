import AppKit
import DraftBookCore
import SwiftUI

enum AppPreferenceKeys {
    static let keepWindowOnTop = "keepWindowOnTop"
    static let settingsSelectedTab = "settingsSelectedTab"
    static let defaultReviewDays = "defaultReviewDays"
    static let automaticBackupsEnabled = "automaticBackupsEnabled"
    static let backupRetentionCount = "backupRetentionCount"
}

struct SettingsView: View {
    @EnvironmentObject private var store: DraftStore

    @AppStorage(AppPreferenceKeys.settingsSelectedTab) private var selectedTab = "general"
    @AppStorage(AppPreferenceKeys.keepWindowOnTop) private var keepWindowOnTop = true
    @AppStorage(AppPreferenceKeys.defaultReviewDays) private var defaultReviewDays = 7
    @AppStorage(AppPreferenceKeys.automaticBackupsEnabled) private var automaticBackupsEnabled = true
    @AppStorage(AppPreferenceKeys.backupRetentionCount) private var backupRetentionCount = 14

    var body: some View {
        TabView(selection: $selectedTab) {
            generalSettings
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }
                .tag("general")

            LabelSettingsView()
                .tabItem {
                    Label("标签", systemImage: "tag")
                }
                .tag("labels")

            dataSettings
                .tabItem {
                    Label("数据", systemImage: "externaldrive")
                }
                .tag("data")
        }
        .frame(width: 480, height: 380)
        .onAppear(perform: synchronizeStorePreferences)
        .onChange(of: defaultReviewDays) { _, _ in synchronizeStorePreferences() }
        .onChange(of: automaticBackupsEnabled) { _, _ in synchronizeStorePreferences() }
        .onChange(of: backupRetentionCount) { _, _ in synchronizeStorePreferences() }
    }

    private var generalSettings: some View {
        Form {
            Section("窗口") {
                Toggle("保持草稿本窗口在最上方", isOn: $keepWindowOnTop)
            }

            Section("草稿生命周期") {
                Picker("新草稿默认在多久后进入清理台", selection: $defaultReviewDays) {
                    Text("1 天").tag(1)
                    Text("3 天").tag(3)
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                }
                Text("仅影响之后创建或重新恢复的草稿；固定草稿不会进入清理台。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private var dataSettings: some View {
        Form {
            Section("自动备份") {
                Toggle("每天自动备份", isOn: $automaticBackupsEnabled)

                Picker("保留最近", selection: $backupRetentionCount) {
                    Text("7 份").tag(7)
                    Text("14 份").tag(14)
                    Text("30 份").tag(30)
                }
                .disabled(!automaticBackupsEnabled)

                HStack {
                    Button("打开数据文件夹") {
                        ExportController.openDataFolder(for: store)
                    }
                    Button("恢复完整备份…") {
                        ExportController.importFullBackup(into: store)
                    }
                }
            }

            Section("隐私") {
                Text("所有草稿均保存在本机，不会上传服务器。数据文件目前没有加密，不建议用来长期保存密码、私钥或其他高度敏感信息。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private func synchronizeStorePreferences() {
        store.configure(
            defaultReviewDays: defaultReviewDays,
            automaticBackupsEnabled: automaticBackupsEnabled,
            backupRetentionCount: backupRetentionCount
        )
    }
}

private struct LabelSettingsView: View {
    @EnvironmentObject private var store: DraftStore
    @State private var names: [DraftColor: String] = [:]
    @State private var feedback: String?
    @State private var hasError = false
    @State private var hasSaved = false
    @FocusState private var focusedColor: DraftColor?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("自定义分类名称") {
                    HStack(spacing: 10) {
                        colorMark(.gray)
                        Text("未分类")
                        Spacer()
                        Text("固定名称")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(DraftColor.allCases.filter { $0 != .gray }, id: \.self) { color in
                        HStack(spacing: 10) {
                            colorMark(color)
                            Text(color.displayName)
                                .frame(width: 36, alignment: .leading)
                            TextField("", text: binding(for: color))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                                .focused($focusedColor, equals: color)
                                .accessibilityLabel("\(color.displayName)标签名称")
                        }
                    }
                }

                Section {
                    Text("分类名同步用于所有区域；不影响清理时间。留空恢复默认名称。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if let feedback {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(hasError ? Color.red : Color.secondary)
                }
                Spacer()
                Button(hasSaved ? "已保存" : "保存名称") {
                    saveNames()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hasSaved)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .padding(.top, 4)
        .onAppear {
            names = Dictionary(uniqueKeysWithValues: DraftColor.allCases.map { color in
                (color, store.labelName(for: color))
            })
        }
    }

    private func colorMark(_ color: DraftColor) -> some View {
        Capsule()
            .fill(color.swiftUIColor)
            .frame(width: 24, height: 8)
    }

    private func binding(for color: DraftColor) -> Binding<String> {
        Binding(
            get: { names[color] ?? color.displayName },
            set: { value in
                guard names[color] != value else { return }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveName = trimmed.isEmpty ? color.defaultLabelName : trimmed
                if hasSaved && effectiveName == store.labelName(for: color) { return }
                names[color] = value
                feedback = nil
                hasSaved = false
            }
        )
    }

    private func saveNames() {
        focusedColor = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
        do {
            try store.setLabelNames(names)
            names = Dictionary(uniqueKeysWithValues: DraftColor.allCases.map { color in
                (color, store.labelName(for: color))
            })
            feedback = "✓ 已保存到本机"
            hasError = false
            hasSaved = true
        } catch {
            feedback = error.localizedDescription
            hasError = true
            hasSaved = false
        }
    }
}
