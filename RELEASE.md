# 发布流程

## 当前公开测试路线：未公证 DMG

运行：

```bash
./scripts/package-unsigned-beta.sh
```

脚本会完成：

1. 构建 Apple Silicon 与 Intel 通用 App；
2. 编译正式 App 图标；
3. 使用 ad-hoc 签名并开启 Hardened Runtime；
4. 将 App、Applications 快捷方式和首次打开说明打包为 DMG；
5. 验证 DMG 文件结构；
6. 生成 SHA-256 校验文件。

输出：

```text
dist/DraftBook-v0.9.5-macOS-unsigned.dmg
dist/SHA256SUMS.txt
```

GitHub Release 必须同时上传这两个文件，并在 Release Notes 中明确说明安装包未经 Apple 签名和公证。

## 未来路线：Developer ID 公证版

Developer ID 公证版可以直接通过 GitHub 或官网分发，不需要 TestFlight，也不需要邀请测试用户。它需要有效的 Apple Developer Program 会员资格。

一次性配置完成后运行：

```bash
./scripts/package-release.sh
```

完整流程包括 Developer ID 签名、Apple 公证、票据附加和 Gatekeeper 验证。

## 发布前检查

- 全部单元测试通过；
- App 为 `arm64 + x86_64` 通用构建；
- App 图标、版本号和版权信息正确；
- 使用干净数据目录启动并完成输入、保存和重启恢复；
- 搜索、标签筛选、清理台、存档、回收站正常；
- 完整备份导出和恢复正常；
- 设置在重启后保留；
- DMG 可以挂载并包含首次打开说明；
- SHA-256 与最终 DMG 一致；
- Release Notes 明示未签名、未公证及系统要求；
- 不上传任何用户草稿、`.build/` 或本机配置文件。
