# DraftBook 跨平台开发交接

> 核对基线：macOS `v0.9.8`、Windows `0.9.6-preview.5`，仓库 `main`。记录日期：2026-11-18。版本和 Release 状态会变化；新 Agent 开始前必须核对 Git、源代码和 GitHub 实际状态。

## 开始工作的方式

先读根目录 `AGENTS.md`，再运行：

```bash
git status --short --branch
git log -8 --oneline --decorate
```

遇到冲突时，以当前代码、测试、CI 和公开 Release 为准，并指出本文件过期之处。不要为一般小改动通读全部仓库；按任务看相关目录和测试。

## 架构地图

| 路径 | 内容 |
| --- | --- |
| `Sources/DraftBookCore/` | Swift 模型、草稿状态、生命周期、JSON 快照、备份与持久化 |
| `Sources/DraftBook/` | macOS SwiftUI/AppKit 窗口、编辑器、Markdown、链接、菜单、更新器和诊断 |
| `Tests/DraftBookCoreTests/`、`Tests/DraftBookEditorTests/` | macOS 核心和编辑器行为测试 |
| `windows/src/DraftBook.Core/` | Windows C# 模型、schema、存储、保存协调与生命周期 |
| `windows/src/DraftBook.Windows/` | WPF UI、IME-aware 输入、窗口、剪贴板、链接和自动更新 |
| `windows/tests/` | Windows 核心、UI 逻辑和更新 smoke tests |
| `windows/spec/` | Windows 实现状态、数据兼容、合成夹具、验收及内测指南 |
| `Resources/`、`distribution/` | macOS bundle 元数据、图标、第三方声明和版本说明 |
| `scripts/`、`windows/scripts/` | 各平台构建、打包和本地发布物生成脚本 |
| `.github/workflows/` | macOS CI、Windows CI 与 Windows Release workflows |

Swift `DraftBookCore` 使用 Combine；它表达了 macOS 业务规则，但不可假定能直接用于 WPF。跨平台兼容主要通过同一行为契约、schema v5 和合成 JSON fixture 保证。

## 不可变契约

- macOS bundle ID 与本地数据身份保持 `com.yangyuxuan.DraftBook`。更改会影响应用身份、用户数据定位和已安装实例。
- macOS 最低系统版本保持 macOS 14.0；同时核对 `Package.swift`、`Resources/Info.plist` 和 CI/build 配置。
- macOS 与 Windows 当前共用完整备份 schema v5。顶层为 `schemaVersion`、`composer`、`drafts`、`labelNames`；日期以 ISO 8601 表示。枚举原始值、字段、缺省值与迁移规则见 `windows/spec/DATA_COMPATIBILITY.md` 和两端模型实现。
- 遇到 schema 高于当前版本必须安全拒绝，保留原始用户数据；不能部分加载后覆盖。
- macOS 更新通道读取 `https://api.github.com/repos/hy198619/draftbook/releases?per_page=100`，Release/tag 为 `v<semver>`，安装资产名为 `DraftBook-v<semver>-macOS-unsigned.dmg`，并校验同一 Release 的 `SHA256SUMS.txt`。
- Windows 更新使用 Velopack 独立通道 `win-x64-beta` / `win-arm64-beta`，公开 tag 命名为 `windows-v<Windows版本>`。包身份、通道名、主程序名、feed/包资产组合不可私自调整。
- 任何 Swift public API、C# 公共程序集接口、JSON/CLI/更新协议的破坏性调整，必须先取得用户同意，提供迁移策略和测试；禁止顺手“清理”或重构。

## 命名与错误处理

- Swift 延续本文件周边风格：类型 `UpperCamelCase`，属性、函数和枚举 case 用 `lowerCamelCase`，4 空格缩进。优先使用 Swift 类型表达状态和错误；给用户的错误说明使用简洁、可操作的中文。
- C# 类型和公开成员用 `PascalCase`，私有字段和局部变量用 `camelCase`；保持 nullable annotations、确定性构建和 warnings-as-errors。
- 持久化、导入、更新、导出错误必须保留错误上下文并给用户清楚反馈。Swift 可使用专用 `Error`/`LocalizedError`；C# 不吞异常或仅写日志。只允许对无害清理采用明确的 best-effort 处理。
- 文本数据不得因格式化或控件重建而丢失空格、制表符、换行或 Markdown 原文。中文输入法组合期间保持控件和焦点稳定。
- 绝不把真实草稿或认证信息放入测试、fixture、日志、截图、提交和 Release。只用仓库内合成夹具。

## 验证命令

macOS，在仓库根目录：

```bash
swift test
./scripts/build-app.sh
```

Windows，在 PowerShell 的 `windows/` 目录：

```powershell
dotnet test .\tests\DraftBook.Core.Tests\DraftBook.Core.Tests.csproj -c Release
dotnet test .\tests\DraftBook.Windows.Tests\DraftBook.Windows.Tests.csproj -c Release
dotnet build .\src\DraftBook.Windows\DraftBook.Windows.csproj -c Release
```

Windows 打包需在受支持的 Windows/.NET 环境运行 `windows/scripts/publish-windows.ps1 -Runtime win-x64` 或 `-Runtime win-arm64`。这些命令生成本地产物；需要真实 Windows 设备才能验证安装、IME、DPI、窗口和更新体验。报告时分清本地测试、CI、交叉构建和真机验证。

## Swift 格式化决策

当前开发环境没有 `swift-format` 可执行程序，也没有仓库级格式工具配置。遵循现有 Swift 文件风格、不做全仓格式化；不要添加依赖来自动格式化。若将来确需 `swift-format`，应先确认 Swift 工具链已提供或用户批准工具依赖，再以小范围 lint 验证配置后引入，不能把启用格式化作为无关改动。

## 当前平台状态和专门材料

- macOS 最近记录版本为 0.9.8；版本改动和发布流程见 `CHANGELOG.md`、`RELEASE.md`，真实版本须查 GitHub。
- Windows 当前记录版本为 `0.9.6-preview.5`；技术事实、已完成/待真机验证事项、界面方向、更新渠道和内测限制见 `docs/WINDOWS_HANDOFF.md`。
- Windows schema 和合成夹具：`windows/spec/DATA_COMPATIBILITY.md`、`windows/spec/fixtures/`。
- Windows 验收与状态：`windows/spec/MVP_ACCEPTANCE.md`、`windows/spec/IMPLEMENTATION_STATUS.md`、`windows/spec/BETA_TEST_GUIDE.md`。
- 产品面向本地优先的临时文字记录。任何平台都不能把它描述成密码管理器；数据尚未加密。

## 禁止事项

1. 未经明确要求，不做架构迁移、范围外重构、公开 API/schema/包身份/更新协议变更、依赖新增或版本升级。
2. 不用真实草稿验证跨平台兼容、自动保存、日志或恢复流程。
3. 不把 CI 通过、交叉编译或代码检查表述成 Windows 真机验证。
4. 不擅自创建、上传、替换、删除或发布 tag、GitHub Release、安装包及其他公开资产。
5. 不以默认格式化工具重写大量既有代码；修改限制在需求相关范围并补充针对性测试。

## 新 Agent 的启动提示

```text
继续开发 DraftBook。请先读取仓库根目录 AGENTS.md 和 docs/AGENT_HANDOFF.md，核对 git status、HEAD、分支、平台版本和公开 Release 状态。随后按本次具体任务读取相关代码与测试，不要无目的遍历或重构。

严格遵守 AGENTS.md 中的包身份、schema v5、macOS 14 下限、Windows 更新通道、依赖、公开接口、测试数据和发布边界。任何超出本次任务的架构、依赖或接口改动先说明原因并等我批准。完成后报告改了什么、运行了哪些检查、哪些平台/设备尚未验证。未经我明确授权，不发布或改动任何 GitHub Release。
```
