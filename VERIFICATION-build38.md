# CodexUsage 4.1 / build 38 — 移除用量页顶部说明行

## 交付物

- `/Users/fangyang/Downloads/CodexUsage-4.1-build38-tokensci-unsigned.ipa`
- 1,795,675 bytes
- SHA-256: `4c993589de7667cfebc360fce3b53fe334206710ba74bd2b5c093ae5efb32eba`

## 本次改动

- `App/TokensCIPanel.swift`：删除用量页顶部的「只读用量由电脑上的 tokens CLI 上报；本机不扫描日志。保存账号不代表授权或读取已成功。」整段说明。账号身份随之成为页面第一段内容。
- 未改动：`TokensCIAnalyticsView` 全部区块、统计口径与文案、状态页、设置页、小组件源码、`＋` 连接弹窗、per-profile 刷新/移除/错误显示。
- 版本：`MARKETING_VERSION = 4.1`、`CURRENT_PROJECT_VERSION = 38`，App 与 Widget 一致。

## 已执行的验证

| 检查 | 实际结果 | 证据 |
|---|---|---|
| Swift 语法检查 `swiftc -parse App/TokensCIPanel.swift` | exit 0 | 终端输出 |
| 真机 Release 构建（私有标识显式覆盖） | exit 0, BUILD SUCCEEDED | `Logs/build38-release.log` |
| 打包脚本（版本、标识、未签名、arm64、扩展存在、二进制标记） | exit 0 | `Scripts/package_widget_build38.py` 输出 |
| IPA 压缩包完整性 | `testzip()` 无损坏 | 重新打开 IPA 校验 |
| App / Widget 版本 | 均 4.1 (38)，MinimumOSVersion 17.0 | 从 IPA 内 Info.plist 读回 |
| 被删除文案是否仍在成品中 | 否 | 主二进制字节扫描 |

本次为纯文案删除，未重跑 SwiftPM 与模拟器套件；上一版 4.0/build37 的 98 项 SwiftPM、84 项签名模拟器测试结果仍然有效，相关代码路径未改动。

## 未验证（需手机验收）

- 重签覆盖安装、真实触摸与布局、私密 tokens.ci 账号的实时数值。
