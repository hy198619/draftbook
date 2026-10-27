# DraftBook for Windows

该目录用于 Windows 版的独立实现与验证材料。

当前状态（2026-10-27）：

- 已完成 macOS `a728753` / `v0.9.6` 的行为与平台边界核查；
- 已完成独立的 .NET 10 核心模型、schema v5 兼容、原子保存、自动备份和 50 项核心自动测试；
- 已创建 WPF 界面，包括输入与划定、Markdown 预览、分类与搜索、清理台、存档、回收站、导出与备份恢复；
- 已在 macOS 上使用 WindowsDesktop targeting pack 交叉编译，0 警告、0 错误；
- 已配置 `win-x64` 与 `win-arm64` 的独立安装包、更新通道和 Windows CI；
- `0.9.6-preview.3` 已修复换行呈现、网址嵌套链接崩溃、分类名称入口和中文弹出菜单字体问题，并增加单条预览降级保护；
- `0.9.6-preview.3` 已在 macOS 使用 .NET 10 WindowsDesktop targeting pack 完成 Release 交叉编译，并成功生成 x64 与 ARM64 自包含程序；
- `0.9.6-preview.4` 将草稿列表改为按像素滚动，并让 Markdown 预览把滚轮事件交给外层列表；
- macOS 当前为 `0.9.7`，Windows 预览构建继续使用独立的 `0.9.6-preview.N` 后缀；本次不修改 macOS；
- **`0.9.6-preview.4` 的滚动修复尚未在 Windows 真机验证**，实际鼠标与触控板手感仍必须由 Windows 10/11 内测确认；
- 没有读取或复制任何真实草稿。

技术提案见 [`../docs/WINDOWS_TECHNICAL_PLAN.md`](../docs/WINDOWS_TECHNICAL_PLAN.md)。
内测步骤见 [`spec/BETA_TEST_GUIDE.md`](spec/BETA_TEST_GUIDE.md)。
已完成项与尚未真机验证的边界见 [`spec/IMPLEMENTATION_STATUS.md`](spec/IMPLEMENTATION_STATUS.md)。

## 本地构建

需要 .NET 10 SDK 和 Windows 10/11：

```powershell
dotnet test .\tests\DraftBook.Core.Tests\DraftBook.Core.Tests.csproj -c Release
dotnet test .\tests\DraftBook.Windows.Tests\DraftBook.Windows.Tests.csproj -c Release
dotnet build .\src\DraftBook.Windows\DraftBook.Windows.csproj -c Release
.\scripts\publish-windows.ps1 -Runtime win-x64
```

ARM64 发布：

```powershell
.\scripts\publish-windows.ps1 -Runtime win-arm64
```

生成物位于 `artifacts/releases/<runtime>/`，包含 Setup.exe、SHA-256、完整更新包和对应架构的版本 feed。x64 使用 `win-x64-beta`，ARM64 使用 `win-arm64-beta`，不可混用。当前内测安装包尚未签名，Windows 可能显示 SmartScreen 提示。
