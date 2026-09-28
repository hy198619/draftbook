# DraftBook（草稿本）0.9.4 Public Beta

给一人公司主理人和内容创作者的草稿本，一个文字的临时中转站。

[下载 DraftBook 0.9.4（macOS 通用版）](https://github.com/hy198619/draftbook/releases/download/v0.9.4/DraftBook-v0.9.4-macOS-unsigned.dmg)

系统要求：macOS 14 或更高版本，支持 Apple Silicon 和 Intel Mac。

## 本次更新

- 无需 MD 开关，划定草稿后自动呈现 Markdown。
- 单击正文编辑原始文字，点击编辑区外恢复排版；修改后加入的语法同样生效。
- 标题、粗斜体、列表、引用、代码块、表格和任务列表分别排版。
- 普通换行保留，复制整条保留 Markdown 源码。
- 改善编辑焦点同步，避免延迟回调覆盖最新内容。

语法以 CommonMark 为基础，通过 Swift Markdown 解析，并支持其常用 GFM 扩展。图片和 HTML 以文字呈现；链接呈现样式，单击仍进入编辑，不直接打开网址。原始草稿始终以纯文本保存。

## 安装说明

当前为未经过 Apple Developer ID 签名和公证的公开测试版。首次打开步骤见[安装说明](https://github.com/hy198619/draftbook/blob/main/docs/INSTALL.md)。

提供 SHA256SUMS.txt 用于核对安装包完整性。所有草稿保存在本机，数据尚未加密。
