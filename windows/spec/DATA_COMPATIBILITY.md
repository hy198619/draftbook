# DraftBook schema v5 兼容契约

## 顶层快照

```json
{
  "schemaVersion": 5,
  "composer": "未划定输入",
  "drafts": [],
  "labelNames": {}
}
```

- `schemaVersion` 缺省时按 1 读取；高于 5 必须拒绝导入，且不得覆盖当前数据。
- `composer` 缺省为空字符串。
- `drafts` 缺省为空数组。
- `labelNames` 是颜色枚举字符串到自定义名称的映射；灰色名称固定为“未分类”。

## Draft 字段

| 字段 | 类型 | 缺省行为 |
| --- | --- | --- |
| `id` | UUID 字符串 | 缺省时生成 UUID |
| `content` | 字符串 | 必填 |
| `createdAt` | ISO 8601 日期 | 必填 |
| `updatedAt` | ISO 8601 日期 | 必填 |
| `color` | `gray/yellow/blue/purple/green/red` | `gray` |
| `markdownEnabled` | 布尔 | `false`；为历史兼容字段，当前预览行为不依赖开关 |
| `pinned` | 布尔 | `false` |
| `lastCopiedAt` | 日期或 null | null |
| `state` | `active/archived/trash` | `active` |
| `archivedAt` | 日期或 null | null |
| `deletedAt` | 日期或 null | null |
| `title` | 字符串或 null | null |
| `reviewIntervalDays` | 整数或 null | 缺省/null 均为 null；schema 1/2 的活跃草稿由迁移逻辑补齐 |
| `reviewAt` | 日期或 null | 缺省/null 均为 null；schema 1/2 的活跃草稿由迁移逻辑补齐 |
| `isSample` | 布尔 | `false` |

## 兼容行为

- 新草稿默认 `gray`、`active`、未固定，清理周期使用当前默认值；
- 活跃草稿排序：固定优先，各组内 `createdAt` 新者在前；
- 存档按 `archivedAt ?? updatedAt` 倒序；回收站按 `deletedAt` 倒序；
- 编辑活跃且未固定的草稿时，清理日期根据 `updatedAt` 和周期重算；
- 标签褪色按创建后实际经过的秒数分 5、7、30 天四档；
- 清理周期按本地日历日计算，须覆盖夏令时切换测试；
- 导出排除回收站和示例草稿；完整备份保留所有状态和顶部输入；
- 恢复完整备份前，先保存当前主数据的安全副本；
- Windows 活数据与 macOS 活数据不共享路径，只通过用户选择的备份文件迁移。

## 日期输出

跨平台写出统一使用 UTC、ISO 8601、秒精度，例如：

```text
2026-10-12T01:02:03Z
```

这避免不同 JSON 序列化器输出不同长度的小数秒。读取器可兼容带合法时区偏移的 ISO 8601 输入，但重新写出时应规范化。

## 测试数据边界

兼容测试只能使用 `fixtures/` 中的合成数据。不得把用户的 `drafts.json`、备份、截图或真实文本复制进测试、日志、Issue 或公开仓库。
