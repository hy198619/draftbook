# DraftBook for Windows

该目录用于 Windows 版的独立实现与验证材料。

当前状态（2026-10-12）：

- 已完成 macOS `a728753` / `v0.9.6` 的行为与平台边界核查；
- 已完成独立的 .NET 10 核心模型、schema v5 兼容、原子保存、自动备份和 49 项自动测试；
- 已创建 WPF 界面，包括输入与划定、Markdown 预览、分类与搜索、清理台、存档、回收站、导出与备份恢复；
- 已在 macOS 上使用 WindowsDesktop targeting pack 交叉编译，0 警告、0 错误；
- 已配置 `win-x64` 与 `win-arm64` 的独立发布和 Windows CI；
- **尚未在 Windows 真机运行**，中文 IME、窗口交互、链接打开和进程退出仍必须由 Windows 10/11 内测验证；
- 没有读取或复制任何真实草稿。

技术提案见 [`../docs/WINDOWS_TECHNICAL_PLAN.md`](../docs/WINDOWS_TECHNICAL_PLAN.md)。
内测步骤见 [`spec/BETA_TEST_GUIDE.md`](spec/BETA_TEST_GUIDE.md)。
已完成项与尚未真机验证的边界见 [`spec/IMPLEMENTATION_STATUS.md`](spec/IMPLEMENTATION_STATUS.md)。

## 本地构建

需要 .NET 10 SDK 和 Windows 10/11：

```powershell
dotnet test .\tests\DraftBook.Core.Tests\DraftBook.Core.Tests.csproj -c Release
dotnet build .\src\DraftBook.Windows\DraftBook.Windows.csproj -c Release
.\scripts\publish-windows.ps1 -Runtime win-x64
```

ARM64 发布：

```powershell
.\scripts\publish-windows.ps1 -Runtime win-arm64
```

生成的 ZIP 为自包含便携版，不要把 x64 与 ARM64 包混用。当前内测包尚未签名，Windows 可能显示 SmartScreen 提示。
