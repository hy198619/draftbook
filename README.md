<p align="center">
  <img src="Resources/AppIcon-final-1024.png" width="128" alt="草稿本图标">
</p>

<h1 align="center">DraftBook · 草稿本</h1>

<p align="center">电脑深度工作时，随手记录和处理“中间状态”文字的轻量桌面草稿工具。</p>

DraftBook（草稿本）是一款为一人公司主理人和内容创作者设计的轻量桌面草稿工具，专门接住电脑深度工作中那些临时、碎片、过程性的“中间状态”文字。

用电脑工作时，我们经常会产生很多“中间状态”的文字：有的还没整理好，不适合放进知识库；有的只在最近几天反复使用；有的本身就是需要一遍遍修改的草稿。不记下来容易忘，放进笔记软件又显得太杂，专门新建一个文档还要考虑文件名和保存位置。

草稿本为这些内容提供一个随手可写、用完可清理的地方。窗口可以收窄后常驻屏幕一侧，打开就能输入；写完按 `⌘ + Enter`（macOS）或 `Ctrl + Enter`（Windows），内容就会成为一条可以单独复制、分类、置顶、存档或删除的草稿。

它是文字的临时中转站，不是另一个等着你认真整理和长期维护的知识库。

> 当前为 `0.9.6 Public Beta`。macOS 应用尚未经过 Developer ID 签名和公证；Windows 可执行文件尚未进行代码签名，首个小范围内测预览版在发布时尚未经过 Windows 真机验证。下载前请阅读对应说明。

## 适合记录什么

- 准备继续推敲的产品构思、内容标题、朋友圈文案；
- 文章、课程、线上沟通或咨询辅导的思路大纲；
- 看视频、听播客、开会或接电话时随手记下的要点；
- 需要反复修改的长微信、邮件、社群公告或群发文案；
- 灵感、突然冒出的句子、临时待办和采购清单；
- 最近要多次使用的网址、邮箱、电话、代码片段或提示词。

有些草稿过两天就没用了，可以直接删除；有些逐渐成形，可以复制到正式文档或知识库；确实需要长期保存的内容，也可以起个标题存档。

## 它与笔记软件有什么不同

草稿本的原型来自作者从 2013 年保持至今的一项工作微习惯：在桌面常驻一个纯文本文件，专门接住工作过程中来不及归类、没必要单独建文件的文字。

它更像办公桌上那本薄薄的小本子：不是精美的手账，也不是需要长期保存的正式笔记本，但一直放在手边，随时可以写两笔，应个急。草稿本在工作流里也是一个配角——当你正做着一件事、突然需要记点什么或起草一段文字时，它就是手边最方便的工具。

产品缘起与完整使用场景，见公众号文章：[《为 OPC 一人公司主理人和内容创作者做了一个小工具，招募种子用户》](https://mp.weixin.qq.com/s/NYQi-yuFVRnb8n0BvojsgQ)。

## 下载

前往 [DraftBook 0.9.6 Release](https://github.com/hy198619/draftbook/releases/tag/v0.9.6) 下载对应版本：

| 系统 | 下载 | 适用设备 | 状态与说明 |
| --- | --- | --- | --- |
| macOS | [`DraftBook-v0.9.6-macOS-unsigned.dmg`](https://github.com/hy198619/draftbook/releases/download/v0.9.6/DraftBook-v0.9.6-macOS-unsigned.dmg) | macOS 14 或更高；Apple Silicon 与 Intel Mac | 公开测试版；[首次打开说明](docs/INSTALL.md) |
| Windows x64 | [`DraftBook-v0.9.6-Windows-x64-preview.zip`](https://github.com/hy198619/draftbook/releases/download/v0.9.6/DraftBook-v0.9.6-Windows-x64-preview.zip) | Windows 11 x64；Windows 10 22H2 x64 尽力兼容 | 便携内测版；[安装与测试说明](windows/spec/BETA_TEST_GUIDE.md) |
| Windows ARM64 | [`DraftBook-v0.9.6-Windows-arm64-preview.zip`](https://github.com/hy198619/draftbook/releases/download/v0.9.6/DraftBook-v0.9.6-Windows-arm64-preview.zip) | Windows 11 ARM64；Snapdragon 等设备 | 便携内测版；[安装与测试说明](windows/spec/BETA_TEST_GUIDE.md) |

macOS 首次打开需要在“系统设置 → 隐私与安全性”中选择“仍要打开”。Windows 下载后请先解压，再运行 `DraftBook.exe`；如果 SmartScreen 拦截，请先核对 SHA-256，再选择“更多信息 → 仍要运行”。

Release 同时提供 macOS 与 Windows 的 SHA-256 校验文件。Windows 版已通过核心自动测试、x64/ARM64 CI 构建和交叉编译，但发布时尚未在 Windows 真机完整验证，当前招募内测用户重点验证中文输入、窗口交互和数据恢复。

## 核心特点

- 按轻量常驻的方式设计，可以把窗口收窄，长期放在屏幕一侧；
- 打开窗口即可输入，不需要先创建文件、标签页或标题；
- `⌘ + Enter`（macOS）或 `Ctrl + Enter`（Windows）将当前内容划定为一条独立草稿，新输入区始终留在最上方；
- 不相关的内容可以留在同一页，由分隔线区分，并能分别编辑和管理；
- 自动保存，重启后恢复未划定和已划定内容；
- 划定后自动呈现 Markdown，点击正文编辑源码，复制整条保留原始语法；
- 按住 `⌘`（macOS）或 `Ctrl`（Windows）点击链接，调用默认应用打开网页或本地文件；普通点击仍用于编辑，也能识别未写成 Markdown 的网址和现有文件路径；
- 五种彩色标签默认叫“分类1”至“分类5”，可自定义名称；黑色固定为“未分类”；标签按创建时间在默认、满 5 天、满 7 天、满 30 天四档降低饱和度，悬停可查看分类、创建、更新及清理时间；
- 全文搜索，并可按标签筛选草稿和存档；存档后仍可编辑名称、正文和标签；
- 到期草稿进入清理台，可延期、固定、存档或删除；
- 回收站支持恢复和永久删除；
- TXT、Markdown、完整 JSON 导出；
- 每日自动备份，支持从完整备份恢复；
- macOS 版可手动检查 GitHub 新版本，下载并校验安装包后打开 DMG；
- 可调默认清理周期、备份策略和窗口置顶；
- 草稿完全保存在本机，不需要账号；Windows 应用不会主动联网，macOS 版只有在用户主动检查或下载更新时才访问 GitHub。

## 基本使用

1. 在窗口最上方直接输入；
2. 写完一条后按 `⌘ + Enter`（macOS）或 `Ctrl + Enter`（Windows），把它单独划定为一条草稿；
3. 继续在最上方输入另一个内容——它可以与上一条毫不相干；
4. 点击草稿签选择标签，在“设置 → 标签”中自定义分类名称；
5. 点击草稿正文编辑；按住 `⌘`（macOS）或 `Ctrl`（Windows）点击链接可打开目标。鼠标悬停在草稿上方，可复制、固定、存档或删除；
6. 到期内容会显示“待处理”，在清理台决定它的去留；
7. macOS 可按 `⌘,` 打开设置；Windows 可点击顶部菜单中的“设置”。
8. macOS 可在“草稿本 → 检查更新…”手动查询新版本；安装仍需将新版 App 拖入“应用程序”并替换旧版。

软件内置“功能示例与说明”，可以一键添加七种状态的示例草稿，实际体验清理、存档和回收流程。

## 数据与隐私

所有草稿都保存在本机：

```text
macOS:   ~/Library/Application Support/com.yangyuxuan.DraftBook/
Windows: %LOCALAPPDATA%\DraftBook\
```

当前版本不包含账号、云同步、分析统计、广告 SDK 或草稿上传。Windows 应用不会主动联网；macOS 版只有在用户主动检查或下载更新时才访问 GitHub。草稿文件目前没有加密，因此不要把它当作密码管理器，也不要保存密码、长期有效的 API Key、私钥或恢复码。macOS 版详见[隐私说明](docs/PRIVACY.md)，Windows 版详见[内测指南](windows/spec/BETA_TEST_GUIDE.md)。

## 反馈

请通过 [GitHub Issues](https://github.com/hy198619/draftbook/issues) 报告问题或提出建议。建议先阅读[反馈指南](docs/FEEDBACK.md)，不要在 Issue 或截图中泄露真实草稿和账号信息。

## 从源码构建 macOS 版

需要 Xcode 16.2 或兼容的更新版本。

```bash
swift test
./scripts/build-app.sh
```

生成的应用位于：

```text
dist/草稿本.app
```

生成未公证的公开测试 DMG：

```bash
./scripts/package-unsigned-beta.sh
```

Windows 版需要 .NET 10 SDK 和 Windows 10/11，构建与测试命令见 [Windows 开发说明](windows/README.md)。

## 项目状态

当前版本已经覆盖核心使用闭环，但仍属于公开测试：

- macOS 应用尚未经过 Developer ID 签名和 Apple 公证；Windows 可执行文件尚未进行代码签名，当前以便携 ZIP 提供；
- Windows 版尚需通过 Windows 10/11、x64/ARM64 真机内测验证；
- 暂无云同步、全局呼出快捷键和自动安装更新；
- 数据尚未加密；
- macOS 版最低支持 macOS 14；Windows 版主要支持 Windows 11，并尽力兼容 Windows 10 22H2 x64。

更新记录见 [CHANGELOG.md](CHANGELOG.md)，参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可

本项目采用 [PolyForm Perimeter License 1.0.1](LICENSE.md)，属于 **Source Available（源码可见）**，不是 OSI 定义下的开源协议。

你可以使用、查看、修改和分发代码，但不得利用本软件向他人提供与草稿本竞争的产品。作者保留未来商业化、闭源版本、收费功能和另行授权的权利。正式条款以 `LICENSE.md` 为准。

Required Notice: Copyright © 2026 杨昱轩.
