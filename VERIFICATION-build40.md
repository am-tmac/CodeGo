# CodexUsage 4.3 / build 40 — Antigravity 组件钥匙串组

## 交付物

- `CodexUsage-4.3-build40-bugfix-unsigned.ipa`（未签名，需自行重签）
- 1803986 bytes
- SHA-256: `afb75fcc5397eb71f858a80213f5d8081b5e98e2c81ca39207b624db1c501e82`

## 版本

- 纯 bug 修复：`MARKETING_VERSION` 4.2 → 4.3；`CURRENT_PROJECT_VERSION` 39 → 40，App 与 Widget 一致。

## 修复内容（M5）

- `AntigravityStore.query()` 在组件里把查询限定到允许的共享钥匙串组，写法和 DeepSeek/Claude 一致。
- 新增 `AntigravityStore.credentialGroup()` 探测：确认令牌确实在这个组里，才把组发布出去。之前 `DashboardStore.publish` 不做核实，直接填 `SharedStorage.permittedGroup`；组对不上时，组件会误报"刷新令牌无效请重登"，现在会退回到只显示缓存。

## 已执行的验证

| 检查 | 结果 |
|---|---|
| 新测试 `testAntigravityWidgetKeychainIsPinnedAndProbed` | 修复前失败（4 处断言），修复后通过 |
| `swift test` | 110 个测试，0 失败 |
| 模拟器 `xcodebuild test`（iPhone 17 Pro） | 89 个测试，0 失败，TEST SUCCEEDED |
| `Tests/*_contract.py`（6 个） | 全部 OK |
| Release 真机构建 + 打包脚本 | 通过；App/Widget 均为 4.3 (40) |

## 需手机验收

- 重签覆盖安装后，Antigravity 组件能刷新（组件刷新授权已开启时）。
- 若显示"仅缓存"，说明令牌不在共享组里：在 App 里重新保存一次 Antigravity 令牌即可。
