import DraftBookCore
import SwiftUI

struct FeatureGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DraftStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DraftBook · 草稿本使用说明")
                        .font(.system(size: 18, weight: .semibold))
                    Text("给一人公司主理人和内容创作者的草稿本，一个文字的临时中转站")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    Text("灵感、视频笔记、微信或邮件草稿、临时待办、稍后要用的网址……先记在这里。过几天没用了可以清理；值得留下的，再存档或转入你的笔记软件。")
                        .font(.system(size: 12))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

                    guideSection(
                        title: "写下来，划成一条",
                        body: "在最上方直接输入，按 ⌘↩︎ 划定为一条草稿。新输入区仍在顶部，接着写另一件事即可；内容会自动保存。"
                    )

                    guideSection(
                        title: "修改和复制",
                        body: "点击已划定草稿的正文即可继续编辑。可以直接写 Markdown，例如 # 标题、*斜体*、**重点** 和列表；离开编辑时显示排版。按住 ⌘ 再点击链接可打开网页或本地文件；不按 ⌘ 则进入编辑。直接写出的网址、现有本地文件的绝对路径也能识别。悬停在草稿分隔线上，点复制按钮可复制整条原文，保留 Markdown 符号和换行。"
                    )

                    guideSection(
                        title: "分类和查找",
                        body: "点击分隔线左侧的标签可为草稿分类；五种彩色标签默认叫“分类1”至“分类5”，可在“设置 → 标签”中自定义名称，黑色固定为“未分类”。标签按创建时间分为默认、满 5 天、满 7 天和满 30 天四档逐渐减淡；悬停可查看分类与时间信息。按 ⌘F 搜索并按标签筛选。"
                    )

                    guideSection(
                        title: "决定去留",
                        body: "默认在最后编辑 7 天后标记为“待处理”，进入清理台集中整理，但仍保留原标签，也不会自动删除。你可以再放几天、固定、存档或移入回收站；存档后仍能编辑名称、正文和标签，但不会再进入清理台。回收站里的内容仍可恢复，固定后不再到期。"
                    )

                    guideSection(
                        title: "数据与设置",
                        body: "草稿只保存在本机。右上角 … 可导出文本或完整备份；在“设置”中可调整清理周期、自动备份和窗口置顶。“草稿本 → 检查更新…”仅在你点击时访问 GitHub。当前数据未加密，请勿保存密码、私钥或长期有效的密钥。"
                    )
                }
                .padding(20)
            }

            Divider()

            HStack {
                if store.hasSampleDrafts {
                    Button("移除示例草稿", role: .destructive) {
                        store.removeSampleDrafts()
                    }
                }

                Spacer()

                Button(store.hasSampleDrafts ? "重新生成示例" : "添加示例草稿") {
                    store.installSampleDrafts()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520, height: 610)
    }

    private func guideSection(
        title: String,
        body: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(body)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
