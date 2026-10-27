# DraftBook Windows 0.9.6-preview.4

- 草稿列表改为按像素滚动，避免长短不一的草稿按整张卡片跳动。
- Markdown 预览区域不再截断外层滚轮事件，鼠标停在正文上也能连续滚动草稿列表。
- 增加主列表滚动模式和 Markdown 预览滚轮转发的 Windows UI 回归测试。
- 草稿仍仅保存在 `%LOCALAPPDATA%\DraftBook\`，安装、更新和卸载不会把草稿放进程序目录。

## 下载与安装

- 普通 Intel / AMD Windows 电脑下载 `Windows-x64-Setup.exe`；Snapdragon 等 Windows ARM 电脑下载 `Windows-arm64-Setup.exe`。
- 双击 Setup.exe 安装。安装完成后会自动启动，并在桌面和开始菜单创建“DraftBook 草稿本”快捷方式。
- 本内测包尚未代码签名。如 SmartScreen 拦截，请先核对同名 `.sha256` 文件，再选择“更多信息 → 仍要运行”。
- 用过上一个 ZIP 便携版的用户：先退出旧程序，再运行安装程序。原草稿目录不变，安装后会继续读取。

## 内测重点

1. 中文输入法组词、候选、快速输入和 `Ctrl+Enter` 划定是否稳定。
2. 首次窗口大小与位置，高 DPI、低分辨率、多显示器和窄窗口是否正常。
3. 桌面/开始菜单启动、单实例、自动保存、重启恢复、备份恢复和卸载是否正常。
4. 从 `0.9.6-preview.3` 检查并安装本版，确认自动更新后草稿、窗口设置和快捷方式保持不变。
5. 使用普通鼠标和触控板，在长短草稿及 Markdown 正文上滚动，确认位移稳定且正文区域不会停止响应。

反馈时请附 Windows 版本、x64/ARM64、输入法及复现步骤；不要为测试提供真实私密草稿。详细清单见 [Windows 内测指南](https://github.com/hy198619/draftbook/blob/main/windows/spec/BETA_TEST_GUIDE.md)。

> 已通过 Windows CI 的 x64/ARM64 构建与更新包校验；尚未完成 Windows 10/11 真机全流程验证。
