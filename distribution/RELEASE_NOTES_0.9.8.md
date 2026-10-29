# DraftBook（草稿本）0.9.8 Public Beta

给一人公司主理人和内容创作者的草稿本，一个文字的临时中转站。

[下载 DraftBook 0.9.8（macOS 通用版）](https://github.com/hy198619/draftbook/releases/download/v0.9.8/DraftBook-v0.9.8-macOS-unsigned.dmg)

系统要求：macOS 14 或更高版本，支持 Apple Silicon 和 Intel Mac。

## 本次更新

- 修复部分 macOS 14.1 用户升级 0.9.7 后，草稿本可能在启动阶段直接退出的问题。原因是应用窗口尚未完全初始化时读取了系统应用状态；0.9.8 改为在界面出现后安全读取。
- 一并收拢窗口呼出、输入激活和设置保存时对系统应用状态的访问，并为少见的系统数据目录异常增加回退处理。
- 新增“帮助 → 导出诊断日志…”。遇到窗口、焦点或工具栏异常时，可导出最近的运行事件用于排查；报告不包含草稿正文、搜索词、标签名称或剪贴板内容。
- 增加启动安全和诊断日志的自动回归测试。最低系统要求仍为 macOS 14。

## 从旧版本升级

在旧版中选择“草稿本 → 检查更新…”，应能发现 0.9.8。点击“下载并打开安装包”后，应用会校验 SHA-256 并打开 DMG。请退出旧版，再将新版“草稿本”拖入“应用程序”并选择替换；安装不会删除保存在本机的草稿。

当前仍是未经过 Apple Developer ID 签名和公证的公开测试版。首次打开步骤见[安装说明](https://github.com/hy198619/draftbook/blob/main/docs/INSTALL.md)。Release 同时提供 `SHA256SUMS.txt`，可供手动核对。

草稿保存在本机；只有主动检查或下载更新时才连接 GitHub，不会上传草稿内容。遇到问题请通过 [GitHub Issues](https://github.com/hy198619/draftbook/issues) 反馈，截图前请遮挡私人内容。
