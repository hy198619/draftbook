# DraftBook Windows 技术方案与实现记录

> 状态：2026-10-12 首个 Windows 内测实现。macOS 基线为 `a728753` / `v0.9.6`。
> 本文只定义 Windows 实现方向，不修改 macOS 0.9.6 的代码、数据或发布物。

## 结论

Windows 首版建议使用 **C# + .NET 10 LTS + WPF**，采用独立的 Windows 工程，按现有 macOS 行为重新实现，而不是尝试直接编译 SwiftUI/AppKit 代码。

选择依据按优先级排列：

1. DraftBook 的核心是持续输入，中文 IME 稳定性高于界面技术的新旧；
2. WPF `TextBox` 使用 Windows 桌面原生输入系统，能够观察文本合成开始、更新和完成事件；
3. WPF 原生支持可调整窄窗口、`Topmost` 和多行纯文本，首版不需要额外窗口运行时；
4. .NET 10 是 LTS，官方支持至 2028-11-14；WPF 在 .NET 9/10 已有 Windows 11 Fluent 主题；
5. 相比 Electron/WebView 方案，WPF 少一层浏览器运行时；相比 WinUI 3，首版部署、窗口与输入状态管理更直接。

“轻量”仍必须用 Windows 真机数据证明，不能由框架名称推断。第一阶段把冷启动、空闲内存和输入延迟列为验收项。

## 可以沿用的产品逻辑

以下是行为契约，可以从 Swift 测试等价移植为 C# 测试：

- `Draft` 字段、枚举值和 schema v5 JSON 格式；
- 顶部输入区、划定草稿、空白输入不生成草稿；
- 自动保存、退出前 flush、异常时从备份恢复；
- 活跃草稿“固定优先、同组按创建时间倒序”的排序；
- 编辑正文更新 `updatedAt`，并按最后编辑时间重算清理日期；
- 标签褪色只看 `createdAt`，不能因编辑而重置；
- 固定、延期、存档、回收站、恢复和撤销最近删除的状态转换；
- 搜索正文和显示标题，按标签组合筛选；
- TXT、Markdown、完整 JSON 的导出范围和顺序；
- 自定义分类名称的默认值、长度和去重规则；
- 对更高 schema 版本的备份拒绝恢复；
- 复制整条时复制 Markdown 原始文本，不复制渲染结果。

这里的“沿用”是**移植行为与测试**，不是共享 Swift 二进制。`DraftStore` 依赖 Combine、`ObservableObject`、Swift `Calendar` 和 Foundation 文件 API，强行跨平台编译会把平台差异藏在核心路径里。

## 必须重写的 macOS 实现

- SwiftUI/AppKit 视图、菜单、弹窗、焦点和窗口生命周期；
- `GrowingTextEditor` 的 `NSTextView`、marked text 和 `NSEvent` 处理；
- `NSPasteboard`、`NSWorkspace`、`NSOpenPanel`、`NSSavePanel`；
- AppKit/TextKit Markdown 渲染与链接命中测试；
- `WindowConfigurator` 的窗口置顶、最小尺寸和窗口状态保存；
- `UserDefaults` 偏好存储与 macOS Application Support 路径；
- DMG、GitHub Release 下载、校验和打开安装包流程；
- macOS 菜单快捷键和所有 `Command` 键文案；
- 应用图标资源、签名、安装、卸载和更新机制。

## 建议工程边界

Windows 代码放在仓库根目录的 `windows/`，不修改现有 `Package.swift`：

```text
windows/
  src/
    DraftBook.Core/        # 模型、状态转换、JSON、原子保存与备份
    DraftBook.Windows/     # WPF 窗口、编辑器、剪贴板、系统集成
  tests/
    DraftBook.Core.Tests/
  spec/                    # 数据契约、合成夹具、真机验收清单
```

`DraftBook.Core` 不引用 WPF 类型；UI 只调用核心状态与存储接口。数据层目前体量很小，与核心模型同项目可以减少发布边界；如果后续增加云同步，再拆独立 Persistence 项目。核心层可在非 Windows 环境审查和运行测试，但 WPF 行为仍必须在 Windows 上实机验证。

## 中文输入专项设计

1. 编辑中的 WPF `TextBox` 是唯一输入事实源；获得焦点后不因 ViewModel 通知重新设置 `Text`。
2. 使用 `TextCompositionManager` 的开始、更新、完成事件维护 `isComposing`。
3. `Ctrl+Enter` 只在 `isComposing == false` 时划定草稿；`Key.ImeProcessed` 不触发业务快捷键。
4. 不主动调用“完成输入法合成”，不在候选窗口期间换掉控件实例、移动焦点或重建列表项。
5. 自动保存从控件读取当前文本并防抖写入；保存成功不得反向覆盖控件文本。
6. 结束编辑时先让输入法自然提交，再读取最终文本并 flush。
7. 列表中的草稿默认是预览控件；同一时刻只把被编辑的一条切换成稳定的原生 `TextBox`。

这套约束来自 macOS 0.9.3 的真实缺陷经验，但只能通过微软拼音、搜狗拼音等 Windows 真机输入法验证。

## 数据与持久化

- Windows 活数据建议放在 `%LOCALAPPDATA%\DraftBook\drafts.json`，绝不直接使用 macOS 数据目录；
- 跨平台迁移通过用户明确选择的“完整备份导入”，不让两个平台并发写同一文件；
- 首次保存写同目录临时文件，再做原子替换；替换前保留上一份可恢复副本；
- 输入变更约 300 ms 防抖保存，划定、状态转换、窗口关闭时立即 flush；
- 使用单实例互斥，避免两个进程同时写主数据；
- JSON 日期统一写 UTC、ISO 8601、秒精度，读取时接受当前 schema v5 的 ISO 8601 表达；
- schema 高于 5 时只读失败并给出明确错误，不能“尽量加载”后覆盖；
- 所有兼容测试只使用 `windows/spec/fixtures/` 的合成数据。

## Markdown 与链接

用户确认尽可能复现 0.9.6 后，Markdown 预览已纳入首个内测实现：

- 使用 CommonMark/GFM 兼容解析器生成 WPF 原生展示树，避免为预览引入 WebView2；
- HTML 与图片仍以安全的文字形式处理，不执行脚本、不自动加载远程资源；
- 普通点击进入编辑，`Ctrl+点击` 打开链接；右键菜单也提供“打开链接”；
- 只允许 `http`、`https`、已存在的本地普通文件；可执行文件和危险目标必须确认；
- 复制始终读取模型中的原始正文。

## 第一阶段可试用闭环

必须有：

- 单一可缩窄窗口，最小宽度 320 px，支持用户开关“保持最前”；
- 顶部多行输入区，`Ctrl+Enter` 划定，普通 Enter 换行；
- 输入区和已划定草稿自动保存，重启后恢复；
- 草稿按现有顺序纵向完整展开，无单条内部滚动框；
- 点击一条草稿进入源码编辑，失焦后结束编辑；
- 复制整条原始文本；
- schema v5 基础模型、独立 Windows 数据目录、保存失败可见提示；
- 合成数据单元测试和 Windows 中文 IME 手工测试。

已额外完成：标签 UI 与自定义、Markdown 预览、搜索、清理台、固定、存档、回收站、TXT/Markdown/JSON 导出、完整备份恢复和每日自动备份。

已完成代码与交叉打包：Velopack x64 / ARM64 按用户 Setup.exe、桌面与开始菜单快捷方式、GitHub Release 独立通道、应用内检查/下载/校验/重启安装。尚未完成：代码签名、Windows 原生 UI 自动化测试，以及 Windows 10/11 真机上的安装、卸载和跨版本更新验证。

## 推荐开发顺序

1. 建立 Windows 工程和 schema v5 模型，移植核心状态测试；
2. 完成 JSON 原子存储、恢复和合成兼容夹具；
3. 做单窗口输入—划定—重启恢复纵向切片；
4. 先在 Windows 真机完成 IME 压力测试，再增加 Markdown 或其他功能；
5. 加编辑、复制、置顶、窄窗口和资源指标；
6. 根据试用反馈决定第二阶段是优先标签/搜索，还是优先 Markdown/备份导入；
7. 安装与更新链路进入内测验收；扩大公开测试前补齐代码签名。

## 已确认的产品决定

1. 首个内测版尽可能覆盖 macOS 0.9.6，不只做最小输入闭环；
2. Windows 11 为主支持平台，Windows 10 22H2 提供尽力兼容；
3. 支持 schema v5 完整备份导入，但不让 macOS 与 Windows 并发写同一个文件；
4. 当前内测使用未签名的自包含 Setup.exe，代码签名在扩大公开测试前引入；
5. 使用 `Ctrl+Enter` 划定、`Ctrl+点击` 打开链接；
6. x64 与 ARM64 同时构建、分包和测试。

## 官方依据

- .NET 支持策略：https://dotnet.microsoft.com/platform/support/policy
- WPF 输入体系：https://learn.microsoft.com/dotnet/desktop/wpf/advanced/input-overview
- WPF 文本合成事件：https://learn.microsoft.com/dotnet/api/system.windows.input.textcompositionmanager
- WPF 窗口置顶：https://learn.microsoft.com/dotnet/api/system.windows.window.topmost
- WPF .NET 10 更新：https://learn.microsoft.com/dotnet/desktop/wpf/whats-new/net100
- Windows 应用打包概览：https://learn.microsoft.com/windows/apps/package-and-deploy/
