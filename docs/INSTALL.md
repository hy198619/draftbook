# 下载、安装与首次打开

## 系统要求

- macOS 14 Sonoma 或更高版本；
- 支持 Apple Silicon 和 Intel Mac；
- 不需要注册账号，也不需要联网使用。

## 安装

1. 只从本项目的 GitHub Releases 页面下载最新版 DMG；
2. 打开 DMG；
3. 将“草稿本”拖入“应用程序”文件夹；
4. 在“应用程序”中双击“草稿本”。

## 为什么第一次打开会被 macOS 阻止

当前公开测试版没有使用 Apple Developer ID 签名，也没有经过 Apple 公证。macOS 因此无法确认开发者身份，也无法确认 Apple 是否扫描过这个安装包。这不代表系统检测到了恶意软件，但意味着你需要自行确认下载来源。

请只从本项目的官方 GitHub Releases 页面下载，并可使用 Release 同时提供的 SHA-256 校验值核对文件完整性。

## 第一次打开

1. 先像平常一样双击“草稿本”；
2. 看到“无法验证开发者”或“Apple 无法检查其是否包含恶意软件”时，关闭提示；
3. 打开 `系统设置 → 隐私与安全性`；
4. 向下滚动到“安全性”，找到刚刚被阻止的“草稿本”；
5. 点击“仍要打开”；
6. 再次确认“打开”。

完成一次后，系统会将它保存为例外，今后可以正常双击打开。

Apple 对这一流程的官方说明：<https://support.apple.com/102445>

## 校验下载文件

在终端执行：

```bash
shasum -a 256 ~/Downloads/DraftBook-v0.9.3-macOS-unsigned.dmg
```

输出值应与同一 Release 中 `SHA256SUMS.txt` 的内容完全一致。

## 数据存放位置

```text
~/Library/Application Support/com.yangyuxuan.DraftBook/
```

卸载 App 不会自动删除这里的草稿和备份。
