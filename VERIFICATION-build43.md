# CodeGo 4.6 / build 43 — 组件重置积分、改名 CodeGo

## 交付物

- `CodeGo-4.6-build43-unsigned.ipa`（未签名，需自行重签）
- 2026599 bytes
- SHA-256: `56e8b7d2abe0117940e4584e706ad56876b79866480b151d779f0166a4d4c1b5`

## 改动

- Codex 组件（所有尺寸、所有槽位）底部由账号名改为「重置积分 N · 更新 时间」；N = 可用且未过期的重置积分，缺明细回退 `available_count`，无数据显示 —。删除原中/大号单独的重置额度行。
- 删除组件账号名功能：「在小组件中显示完整邮箱」设置、共享容器身份字段（`accountLabel`）、`widget-identity-display.json`（App 启动尽力删除旧文件）。旧缓存 JSON 含 `accountLabel` 仍可解码（`Tests/Build43Tests.swift`）。App 内账号列表照旧显示账号。
- 用词：「重置额度」→「重置积分」。
- 改名 CodeGo：App 与组件显示名、App 内标题、Xcode 工程 `CodeGo.xcodeproj`、target/scheme/产物 `CodeGo`、`App/CodeGoApp.swift`、`Widget/CodeGoWidget.swift`。
- 未改：Bundle ID、App Group、Keychain 服务名与访问组、UserDefaults 键、缓存路径、WidgetKit kind（`CodexUsageWidget` / `TokensCIWidget`），覆盖安装后登录与桌面组件保留。
- 版本：4.5 → 4.6，42 → 43。

## 验证

| 检查 | 结果 |
|---|---|
| `swift test` | 119 个测试，0 失败 |
| 模拟器 `xcodebuild test`（scheme CodeGo） | 93 个测试，0 失败，TEST SUCCEEDED |
| `Tests/*_contract.py`（7 个，含新 build43_contract）+ 签名检查 | 全部 OK；组件字节基线有意更新 |
| `grep accountLabel/showFullAccountInWidget/在小组件中显示完整邮箱` | 仅剩旧 JSON 兼容测试夹具 |
| Release 构建 + 打包 | 通过；Bundle ID 与 build 42 一致，显示名 CodeGo |
| 组件截图（小/中，亮/暗，4 张） | 底部「重置积分 2 · 更新 1:05 PM」，无邮箱/账号名，无截断 |

说明：Codex 在本次实现中途达到使用上限，代码由 Codex 完成，最终验证、打包与本文档由 Hermes 补完并复核。时间按系统 12/24 小时制显示。

## 命令

```sh
swift test
xcodebuild -project CodeGo.xcodeproj -scheme CodeGo \
  -destination 'platform=iOS Simulator,id=<build43 isolated simulator>' \
  -derivedDataPath Build43Sim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO test
for f in Tests/*_contract.py; do python3 "$f"; done
python3 Tests/signing_configuration_test.py
python3 Scripts/build43_release.py
python3 Scripts/package_widget_build43.py
python3 Scripts/verify_build43_visuals.py
shasum -a 256 Dist/CodeGo-4.6-build43-unsigned.ipa
```
