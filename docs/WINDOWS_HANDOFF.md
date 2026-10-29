# DraftBook（草稿本）开发交接

> 最后核对：2026-10-27（Asia/Shanghai）
>
> 仓库：`https://github.com/hy198619/draftbook`
>
> 本文是新开发对话的入口。开始工作时仍须以 `git status`、当前源码、GitHub Actions 和 Release 实际状态为准，不能只依赖本文。

## 一、产品定位与不可牺牲的核心体验

DraftBook 是给内容创作者、知识工作者和一人公司主理人的轻量草稿本，是文字的临时中转站，不是需要持续整理的知识库。典型内容包括灵感、视频笔记、待发送的消息或邮件、临时待办、网址和账号名。

产品应保持以下原则：

- 本地优先，不要求账号，不上传草稿；现有本地数据未加密，不能宣传为密码管理器。
- 打开即可写，不要求先建文件、标题、标签页或笔记层级。
- 顶部始终是新草稿输入区；macOS 用 `⌘+Enter`、Windows 用 `Ctrl+Enter` 划定一条草稿。
- 草稿纵向排列，分隔结构不属于正文；每条草稿可独立编辑、复制、固定、分类、存档和删除。
- 正文以原始文本为数据源，必须完整保留空格、制表符、换行、空行和 Markdown 语法。
- 划定后自动呈现 Markdown；普通点击进入源码编辑，组合键点击链接打开目标；复制整条始终复制原始文本。
- 自动保存与重启恢复必须可靠。中文输入法组词、候选、翻页和回删时，不得重建编辑器、回写旧值或吞字。
- “未分类”为固定的无彩色标签，五种彩色标签默认叫“分类1”至“分类5”，名称可自定义。
- 标签颜色衰减按创建时间计算；清理周期按最后编辑时间计算，两者不能混淆。
- 到期草稿进入清理台，可延期、固定、存档或删除；删除先进入可恢复的回收站。
- 支持全文搜索、标签筛选、TXT/Markdown 导出、完整 JSON 备份与恢复、每日自动备份。

不要读取用户真实草稿做测试。所有数据兼容和故障测试只能使用合成数据或仓库内 fixture。

## 二、当前仓库状态

截至本文更新时：

- 分支：`main`
- Windows `0.9.6-preview.4` tag/commit：`39cb40c0644ed4cd9457eb070e945d055d9638ab`。
- 该提交标题：`Handle logical parent in scroll forwarding`。
- macOS 公测版：`v0.9.8`，修复旧系统启动崩溃并加入诊断日志导出。
- Windows 内测版：`0.9.6-preview.4`。
- Windows 滚动修复与 macOS 0.9.8 发布通道相互独立。

新对话开始后第一步必须重新运行：

```bash
cd /Users/yangxu/Documents/ChatGPT/script草稿本/DraftBook
git status --short --branch
git log -8 --oneline --decorate
```

如果状态与本文不一致，以真实仓库为准，并说明差异。

## 三、已发布的 Windows preview.4

GitHub Release：

`https://github.com/hy198619/draftbook/releases/tag/windows-v0.9.6-preview.4`

已确认的发布状态：

- 名称：`DraftBook Windows 0.9.6-preview.4`
- tag：`windows-v0.9.6-preview.4`
- `prerelease = true`
- `draft = false`
- 发布时间：2026-10-27 15:11（北京时间，GitHub 记录为 07:11 UTC）
- x64 安装包：`DraftBook-v0.9.6-preview.4-Windows-x64-Setup.exe`
  - 大小：79,065,418 bytes
  - SHA-256：`6e1cc4ef085319d5dae76290bf4fa37fa16ea490fafb9328073b2cfe99591492`
- ARM64 安装包：`DraftBook-v0.9.6-preview.4-Windows-arm64-Setup.exe`
  - 大小：72,510,679 bytes
  - SHA-256：`893feec1f5d83ca92f080315b768c28d5d399fca4ed4b2fa982426ce1e9f222c`
- Release 同时包含两个架构的完整 `.nupkg`、`.sha256` 和独立更新 feed。
- 面向内部流程的两个 Setup 别名已从 Release 删除，只保留用户能理解的安装包名称。

与 preview.4 tag 对应的 GitHub Actions 已全部通过：

- `CI`：run `40465345830`
- `Windows CI`：run `40465345881`
- `Windows Release`：run `40465357601`

发布属于对外操作。后续不能因为代码完成就自动上传或改 Release；必须再次取得用户明确授权。

## 四、Windows 技术架构

Windows 版与 macOS UI 分开实现，但行为和 schema 对齐：

- UI：.NET 10 + WPF，目标 Windows 10 1809 API 基线；产品目标尽可能支持 Windows 10 22H2、Windows 11、x64 和 ARM64。
- 核心模型：`windows/src/DraftBook.Core/`
- Windows UI：`windows/src/DraftBook.Windows/`
- 核心测试：`windows/tests/DraftBook.Core.Tests/`
- Windows UI 逻辑测试：`windows/tests/DraftBook.Windows.Tests/`
- 更新包冒烟测试：`windows/tests/DraftBook.UpdateSmoke/`
- 安装与更新：Velopack 1.2.161。
- x64 更新通道：`win-x64-beta`
- ARM64 更新通道：`win-arm64-beta`
- 包身份：`com.yangyuxuan.DraftBook`，不能随意修改，否则会破坏安装和更新身份。
- 主程序：`DraftBook.exe`。
- 构建脚本：`windows/scripts/publish-windows.ps1`。
- CI：`.github/workflows/ci.yml`、`windows-ci.yml`、`windows-release.yml`。

Windows 数据默认位于：

```text
%LOCALAPPDATA%\DraftBook\
```

草稿不保存在 ZIP 解压目录或安装目录。安装、更新、卸载应用程序不应主动删除该数据目录。

macOS 数据位于当前用户的 Application Support 中：

```text
~/Library/Application Support/com.yangyuxuan.DraftBook/
```

其中 `~` 表示当前用户主目录，`com.yangyuxuan.DraftBook` 是应用标识，不是开发者电脑的私人目录名。

## 五、preview.4 已完成的主要修复

Windows preview.4 包含 preview.3 的修复，并新增滚动修复：

- 草稿主列表改为按像素滚动，避免高度不同的草稿按整张卡片跳动。
- Markdown 预览把滚轮事件交给外层主列表，鼠标位于正文上方时不再截断滚动。
- 增加主列表滚动模式和 Markdown 滚轮转发的回归测试；Windows UI 测试共 10 项通过。
- 默认窗口改为 420 × 680 DIP，并按当前显示器工作区、DPI 和任务栏位置限制初始位置；不再默认顶天顶地。
- 记忆并校验窗口位置、大小和最大化状态，提供“恢复默认窗口大小和位置”。
- 首次启动默认不始终置顶；图钉旁显示一次性说明卡片。
- 移除可见“划定”按钮，以 `Ctrl+Enter` 为主要操作，顶部保留弱提示。
- 增加正式 Windows 图标、窄栏工具区、按需搜索和系统明暗主题。
- 修复中文菜单、菜单项和工具提示显示方框乱码的问题；当前字体栈使用 Windows 自带的 `Segoe UI` 和 `Microsoft YaHei UI`，没有捆绑第三方商用字体。
- 修复普通回车在划定后被 Markdown 合并为空格的问题，保留原始空格、制表符、LF/CRLF 和空行。
- 修复直接网址与 Markdown 链接生成嵌套 `Hyperlink`、导致预览崩溃和下次启动继续崩溃的问题。
- 为单条草稿增加预览降级保护：预览异常时显示安全的纯文本原文，不拖垮整个应用。
- 标签菜单增加“自定义分类名称…”入口并直接定位到分类设置。
- 修正删除线、任务列表、表格和复杂列表的呈现。
- 加强自动保存快照一致性、串行写入、退出 flush、备份恢复、清理台刷新、IME 快捷键和导出错误处理。
- 增加单实例和重复启动唤醒已有窗口，避免双击快捷方式后看起来没有打开。
- 提供 x64/ARM64 自包含安装程序、桌面和开始菜单快捷方式、自动检查更新、下载、校验和重启安装。

详细功能状态继续参考：

- `windows/spec/IMPLEMENTATION_STATUS.md`
- `windows/spec/BETA_TEST_GUIDE.md`
- `windows/spec/MVP_ACCEPTANCE.md`
- `CHANGELOG.md`

## 六、自动更新与差分包的当前事实

自动更新功能存在并可用，但当前只发布完整更新包，差分更新被明确关闭：

```powershell
--delta none
```

原因是 preview.3 首次发布时，Velopack/zstd 尝试从 preview.2 生成差分包，在处理以下内部执行桩文件时失败：

```text
DraftBook 草稿本_ExecutionStub.exe
```

日志中的中文路径变成乱码，随后报文件不存在。为保证发布与完整更新可靠，提交 `7801bc7` 暂时禁用了差分包。没有差分包时，客户端仍会下载完整 `.nupkg` 完成升级。

当前打包参数仍然是：

```powershell
--packId com.yangyuxuan.DraftBook
--packTitle "DraftBook 草稿本"
--mainExe DraftBook.exe
```

下一版可以尝试的正确方向：

1. 只把 Velopack `packTitle` 改为纯 ASCII 的 `DraftBook`。
2. 不修改 `packId`、`mainExe` 和应用内“草稿本”中文品牌。
3. 接受快捷方式、开始菜单和“已安装的应用”可能显示为 `DraftBook`。
4. 在不发布的 CI 构建中重新启用差分，真实验证从 preview.4 到新版本能否生成并应用 delta。
5. 验证成功后再决定是否正式恢复差分；不能只凭推断宣称已解决。

建议使用品牌写法 `DraftBook`，不要使用全小写 `draftbook`。

## 七、安装包为什么有 70–80 MB

目前 Windows 安装包较大主要因为：

- x64 和 ARM64 分别是 .NET 10 自包含发布；
- 每个安装包都带有运行应用所需的 .NET 桌面运行时，用户无需预装；
- WPF、Markdig、Velopack 和应用程序集被打进单文件发布结果；
- Setup.exe 外层还包含安装与更新所需结构。

这不是草稿数据或图片资源导致，也不等于空闲内存会达到同样大小。

未来可以调查 framework-dependent、裁剪、压缩和分发运行时等方案，但 WPF 反射、Markdown、更新器、Win10/Win11 和 ARM64 兼容性必须优先。没有 Windows 真机回归之前，不要为追求体积贸然启用激进 trimming。对当前小范围内测，自包含包更稳妥。

## 八、已完成验证与尚未验证的边界

已完成：

- Windows 核心测试 50/50 通过。
- 核心行覆盖率 91.56%，分支覆盖率 74.28%。
- Windows UI 逻辑测试已纳入 Windows CI。
- preview.4 Windows Release workflow 成功，核心测试和 10 项 Windows UI 测试全部通过。
- x64 与 ARM64 自包含产物生成成功，文件头架构正确。
- 两个 Setup.exe、完整更新包和更新 feed 实际生成。
- Velopack 更新 smoke locator 能读取本地 feed、发现旧版到新版并校验对应架构的完整包。
- preview.4 tag 对应的 CI、Windows CI 和 Windows Release workflow 均成功。
- 应用和测试项目未发现 NuGet 已知漏洞。

尚未由开发者在 Windows 环境完整验证：

- Windows 10 22H2 与 Windows 11 的真实安装、启动、卸载、升级和回滚。
- x64 与 ARM64 真机全过程。
- 微软拼音、搜狗、微信输入法的候选、翻页、回删、快速输入和 `Ctrl+Enter`。
- 高 DPI、多显示器、任务栏放在不同方向、休眠和显示器热插拔。
- 真实默认浏览器、本地文件打开、剪贴板争用和 SmartScreen。
- 断电、强制杀进程、磁盘满和无权限目录。
- 长时间运行的空闲内存、冷启动时间和稳定性。
- preview.4 的鼠标滚轮与触控板手感仍需用户真机确认；preview.3 的菜单字体、Markdown、链接崩溃和分类入口也继续接受回归。

任何后续交付都必须明确区分：

- “代码已实现/CI 已通过”；
- “已在 Windows 真机验证”；
- “只根据代码推断，尚未验证”。

用户当前没有 Windows 开发环境，计划继续依靠 Windows 10/11 内测用户验证。不能把交叉编译或 GitHub Actions 构建写成“Windows 使用体验已经验证”。

## 九、刚完成的界面与窗口能力评估

当前判断：Windows 版的粗糙感主要来自 UI 完成度，而不是 Windows 或 WPF 的审美上限。

现状依据：

- macOS 使用 SwiftUI、隐藏标题栏、SF Symbols、语义颜色、悬停出现操作和轻微动画。
- Windows 仍保留标准标题栏和大量默认 WPF 控件模板。
- `App.xaml` 只有基础字体、尺寸和少量按钮样式。
- `DraftCard.cs` 主要在 C# 中动态构建视觉树，难以形成统一样式、预览和视觉状态。
- Windows 仍使用部分 Segoe MDL2 字形，整体更像传统工具软件。

推荐方向不是照搬“假 Mac”，而是建立统一的 DraftBook 视觉语言：安静、克制、内容优先、适合窄窗口长期停靠。两个平台气质一致，但保留各自窗口行为和平台习惯。

近期建议继续保留 WPF，不为美观立即迁移 WinUI 3。WPF 的 Style、ControlTemplate、DataTemplate、动画和自定义 WindowChrome 足以完成显著改善；迁移 WinUI 3 会重写 UI 层并增加输入、窗口、打包和回归风险。

建议的 Windows 视觉重构顺序：

1. 建立统一 Design Tokens：背景、文字层级、分隔线、强调色、圆角、间距、hover、pressed、focus、明暗模式。
2. 将草稿卡片逐步改成 XAML `UserControl`/`DataTemplate`，减少在 C# 中拼控件。
3. 对齐 macOS 的信息层级：草稿操作默认收起，在 hover 或键盘焦点时出现。
4. 使用自带矢量 Path/Data 资源保证 Win10/Win11 图标一致，避免继续依赖老式图标字体。
5. 重做标签弹层、菜单、空状态、状态反馈和 Markdown 排版。
6. 最后再评估自定义标题栏；必须保留拖动、双击最大化、窗口缩放、Windows Snap、高 DPI 和无障碍。
7. 建立不同窗口宽度、100%/125%/150%/200% DPI、浅色/深色和中英文内容的视觉回归截图。

上述是已讨论并认可的方向，不代表代码已经实现。

## 十、贴边隐藏/呼出功能评估

macOS 和 Windows 都可以实现“窗口缩进左侧或右侧，只露细边，鼠标经过或按快捷键呼出”。它很符合草稿本“需要时出现、不需要时退出视野”的定位，但目前尚未实现。

建议交互：

- 设置中提供“贴边自动收起”，默认关闭。
- 支持左侧和右侧，用户拖到边缘或明确选择停靠侧。
- 视觉只露约 3–4 像素，实际鼠标命中区域约 8–12 DIP。
- 鼠标进入后用约 150–220 ms 动画滑出。
- 鼠标离开且窗口失焦一段时间后收回；正在编辑、输入法组合或弹出菜单时绝不能自动收回。
- 提供全局快捷键呼出/收回；呼出后正确激活窗口并聚焦草稿输入框。
- 普通窗口模式必须一直保留。

Windows 可在 WPF 窗口上结合 Win32 的窗口位置、显示器工作区和 `RegisterHotKey` 实现；现有 `WindowPlacementService.cs` 可作为基础。macOS 可通过 `NSWindow.setFrame`、屏幕 `visibleFrame` 和全局热键实现。

必须专项处理：

- 多显示器内部相邻边缘与最外侧边缘；
- 左/右/顶部任务栏、Dock、菜单栏和刘海；
- 最大化、全屏应用、虚拟桌面/Space；
- DPI 与显示器热插拔；
- 中文输入法组合态、窗口焦点和弹出菜单；
- 全局快捷键冲突；
- 休眠或拔掉显示器后窗口不能永久留在屏幕外。

实现本身为中等复杂度，可靠完成属于中等偏高复杂度。建议先完成 Windows 视觉重构和状态机设计，再在独立分支实现；没有真机多屏和 IME 测试前不能发布为稳定功能。

## 十一、仍然有效的边界和用户决策

已明确，不必重复询问：

- Windows 的行为基线来自 macOS 0.9.6；macOS 下一版为 0.9.8。
- Windows 尽可能支持 Windows 10/11、x64/ARM64。
- Windows 使用独立 `0.9.6-preview.N` 版本号；不要把 macOS 0.9.8 的改动或版本号混入 Windows 发布。
- 使用安装程序并支持应用内自动更新。
- 用户没有 Windows 开发机，将招募 Windows 用户小范围内测。
- 手机版和手机投递入口暂缓，不纳入当前开发。
- 不读取真实草稿做测试。

以后需要用户明确决定或授权：

- 下一版具体优先级：差分更新恢复、Windows 视觉重构、贴边隐藏功能分别何时进入。
- Windows 后续视觉重构或功能完成后，是否发布为 `0.9.6-preview.5` 或新版本。
- 任何 GitHub Release 上传、替换、删除资产或修改公开说明。
- 是否接受安装后快捷方式和系统应用名称只显示 `DraftBook`。

## 十二、新对话建议先读的文件

按任务需要定向读取，不要一次性遍历所有源码：

1. 本文：`docs/WINDOWS_HANDOFF.md`
2. 产品说明：`README.md`
3. 版本记录：`CHANGELOG.md`
4. Windows 状态：`windows/spec/IMPLEMENTATION_STATUS.md`
5. 内测清单：`windows/spec/BETA_TEST_GUIDE.md`
6. Windows 打包：`windows/scripts/publish-windows.ps1`
7. Windows UI：`windows/src/DraftBook.Windows/App.xaml`、`MainWindow.xaml`、`MainWindow.xaml.cs`、`DraftCard.cs`
8. 窗口逻辑：`WindowPlacementService.cs`、`AppSettings.cs`
9. 数据与保存：`windows/src/DraftBook.Core/`
10. macOS 参考：`Sources/DraftBook/MainView.swift`、`DraftBlockView.swift`、`GrowingTextEditor.swift`、`WindowConfigurator.swift`

若改 UI，必须同时检查输入法、键盘焦点、Markdown 链接和自动保存有没有被视觉重构破坏。草稿保存与正确呈现永远优先于动画和外观。

## 十三、可直接复制到新对话的提示词

```text
继续开发 DraftBook（草稿本）。项目位于：
/Users/yangxu/Documents/ChatGPT/script草稿本/DraftBook

请先完整阅读 docs/WINDOWS_HANDOFF.md，再核对 git status、当前 HEAD、origin/main、最近提交，以及 GitHub Actions/Release 的实际状态。然后按当前任务定向阅读 README、CHANGELOG、Windows 实现状态、核心模型、相关 UI 和测试，不要无目的遍历。

重要边界：
1. 不要读取真实草稿做测试，只能使用合成数据。
2. macOS 0.9.8 已获授权发布；后续任何新版本、Release 资产替换或重新发布仍需我明确授权。
3. 任何 GitHub Release 上传、替换、删除资产或公开发布，都要先向我确认。
4. 我本机没有 Windows 开发环境。必须明确区分“代码已实现/CI 已通过”和“已在 Windows 真机验证”，不能把交叉编译当成真机验证。
5. 首要质量标准是草稿内容保存、空格换行、Markdown、链接、中文输入法和自动保存可靠；视觉优化不能破坏这些能力。

当前 Windows 版本是 0.9.6-preview.4，x64/ARM64 安装包和完整自动更新已发布。本版把主列表改为像素滚动，并修复 Markdown 正文区域截断滚轮的问题；代码和 CI 已通过，但滚动手感尚待 Windows 真机回归。差分包因中文 ExecutionStub 文件名导致 zstd 失败而暂时用 --delta none 关闭。可研究只把 Velopack packTitle 改为 ASCII 的 DraftBook，并在不发布的 CI 中验证从 preview.4 生成和应用差分包；不要修改 packId。

下一阶段的主要方向是 Windows WPF 视觉重构：建立 DraftBook 自己的安静、克制、内容优先的设计系统，不做假 Mac，也不为美观贸然迁移 WinUI 3。优先把 DraftCard 从 C# 动态控件逐步改为 XAML 组件，统一颜色、字体层级、间距、按钮、菜单、hover/focus、明暗模式和视觉回归。

macOS 已实现单显示器优先的贴边自动收起与鼠标呼出；Windows 仍只是候选功能，尚未实现。若在 Windows 开始实现，默认关闭，并认真处理多屏、DPI、任务栏、全屏、焦点、中文输入法组合态和显示器热插拔。

请先报告核查结果、当前真实状态、准备执行的最小步骤和风险边界；不依赖我选择且不涉及公开发布的准备工作可以直接进行。
```
