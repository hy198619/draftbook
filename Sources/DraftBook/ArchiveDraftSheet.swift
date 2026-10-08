import DraftBookCore
import SwiftUI

struct ArchiveDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DraftStore
    @FocusState private var titleFocused: Bool
    @State private var title: String
    @State private var color: DraftColor

    let draft: Draft
    let onArchive: (String, DraftColor) -> Void

    init(draft: Draft, onArchive: @escaping (String, DraftColor) -> Void) {
        self.draft = draft
        self.onArchive = onArchive
        _title = State(initialValue: draft.displayTitle)
        _color = State(initialValue: draft.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("存档草稿")
                .font(.system(size: 16, weight: .semibold))

            Text("名称只用于以后查找，不会写入正文。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("草稿名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)

            Picker("内容标签", selection: $color) {
                ForEach(DraftColor.allCases, id: \.self) { option in
                    Text(store.labelName(for: option)).tag(option)
                }
            }
            .help("默认沿用原标签，也可以在存档时更换")

            Text(draft.content)
                .font(.system(size: 12))
                .lineLimit(3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("存档") {
                    onArchive(title, color)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            titleFocused = true
        }
    }
}
