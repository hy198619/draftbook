import DraftBookCore
import SwiftUI

struct FeatureGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DraftStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("欢迎使用草稿本")
                        .font(.system(size: 18, weight: .semibold))
                    Text("给一人公司主理人和内容创作者的文字临时中转站")
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
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("先写在这里，稍后再决定它去哪里")
                            .font(.system(size: 14, weight: .semibold))
                        Text("灵感、视频笔记、微信或邮件草稿、临时待办，以及稍后会用到的网址或账号名，都可以先放进草稿本。有些内容过两天就没用了，有些会在打磨后正式发出，还有一些会转入笔记软件或知识库。")
                            .font(.system(size: 12))
                        Text("示例草稿会明确标注“示例”，可以随时一键移除。数据目前没有加密，请勿保存密码、长期有效的 API Key、私钥或恢复码。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

                    guideSection(
                        title: "1. 输入与划定",
                        example: "在最上方输入一段文字，按 ⌘↩︎。下一条内容可以与它毫不相干。",
                        result: "这段文字成为一条可以单独管理的草稿；新的空白输入区仍留在最上方，不需要新建文件或标签页。"
                    )

                    guideSection(
                        title: "2. 彩色标签与筛选",
                        example: "点击分隔线左侧的彩色标签换色；将鼠标停在标签上查看时间信息。",
                        result: "颜色用于分类，标签会在创建后的 7 天内连续褪色；悬停时显示创建时间、最后更新时间、未编辑天数和进入清理台的时间。搜索栏还可以只看某一种颜色。"
                    )

                    guideSection(
                        title: "3. Markdown",
                        example: "直接写 # 标题、**重点** 或列表，按 ⌘↩︎ 划定草稿。",
                        result: "自动呈现 Markdown；点击正文编辑原文，离开编辑后恢复预览。复制整条保留语法和换行。普通换行保留，图片和 HTML 以文字呈现。"
                    )

                    guideSection(
                        title: "4. 七天生命周期",
                        example: "新草稿最后修改时间为 9 月 20 日 14:00。",
                        result: "它将在 9 月 27 日 14:00 进入清理台。再次编辑正文，会从新的修改时间重新计算 7 天，但标签不会重新变鲜艳，因为褪色只看创建时间。"
                    )

                    guideSection(
                        title: "5. 待处理与延期",
                        example: "草稿到期后标记为“待处理”。在清理台点击“再放 7 天”。",
                        result: "它立即离开清理台；从点击时刻起再过 7 天，才会重新进入清理台。系统不会自动删除。"
                    )

                    guideSection(
                        title: "6. 固定与存档",
                        example: "固定适合仍需经常使用的内容；存档适合已经完成但值得长期保留的内容。",
                        result: "固定草稿留在主页且不再到期；存档草稿进入存档区，并可单独命名和搜索。"
                    )

                    guideSection(
                        title: "7. 回收站",
                        example: "点击草稿的删除按钮。",
                        result: "草稿先进入回收站，可以撤销或恢复；只有再次确认永久删除才真正移除。"
                    )

                    guideSection(
                        title: "8. 搜索、导出与备份",
                        example: "按 ⌘F 搜索；点击右上角 … 导出或打开备份文件夹。",
                        result: "支持当前区域的正文/存档名称搜索，以及 TXT、Markdown、完整 JSON 导出。"
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
        .frame(width: 520, height: 640)
    }

    private func guideSection(
        title: String,
        example: String,
        result: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(example)
                .font(.system(size: 12))
            Text("实际效果：\(result)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
