# CodexUsage 4.2 / build 39 — 2026-10-18 bug 修复版

## 交付物

- `CodexUsage-4.2-build39-bugfix-unsigned.ipa`（未签名，需自行重签）
- 1,802,387 bytes
- SHA-256: `b9b005c155875eacad09bdfa3f6528b8fdb7c7495fda817a228b7da7d021b910`

## 版本

- 纯 bug 修复：`MARKETING_VERSION` 4.1 → 4.2；`CURRENT_PROJECT_VERSION` 38 → 39，App 与 Widget 一致。

## 修复内容

- 退出登录会删掉组件的退避文件；Codex 重新登录时重置退避（不再残留"刷新失败"或最长 1 小时的节流）。
- token 没有 `sub` 时，账号身份按确定性规则生成（账户 ID + 邮箱，或 token 本身），重新登录不再新建重复的钥匙串账号。
- tokens.ci 的添加/移除会先拿账号锁；Codex 重新登录时，若刷新正占着锁，最多等 3 秒。
- Claude 登录没有返回 refresh token 时，显示专门的错误提示（不再显示"用量格式已变化"）。
- App 端 Codex 刷新也会写入退避文件（成功会清掉组件留下的失败状态）。
- 组件只在按钮触发时请求进度重载，时间线刷新不再请求（节省每日刷新配额）。
- Antigravity：额度用完、`remainingFraction` 缺失的模型按 0% 显示，不再被丢弃；组件里剩余百分比和重置时间取自同一个额度池。
- DeepSeek：去掉币种白名单；卡片菜单里"更新 Key"会替换所选账号，不再新增账号。
- Codex 格式解析错误显示"用量格式异常"，不再显示"网络连接失败"。
- 在 Claude/Antigravity 面板关闭后才完成的登录，也会刷新账号列表和组件；在 Antigravity 面板里移除令牌后会刷新组件；tokens.ci 保存后的提示在弹窗关闭后仍然可见。

## 已执行的验证

| 检查 | 结果 |
|---|---|
| `swift test` | 109 个测试，0 失败 |
| 模拟器 `xcodebuild test`（iPhone 17 Pro） | 89 个测试，0 失败，TEST SUCCEEDED |
| `Tests/*_contract.py`（6 个） | 全部 OK（`tokensci_contract` 的版本号检查已同步到 4.2/39） |
| Release 真机构建 | BUILD SUCCEEDED |
| 打包脚本（标识、版本、未签名、arm64、二进制标记） | 通过 |
| IPA `testzip()` 与 Info.plist 读回 | 无损坏；App/Widget 均为 4.2 (39)，最低系统 17.0 |

## 复现

```sh
swift test
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath Build39Sim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO test
for f in Tests/*_contract.py; do python3 "$f"; done
python3 Scripts/build39_release.py && python3 Scripts/package_widget_build39.py
```

## 需手机验收

- 重签后覆盖安装，现有账号仍可用。
- Codex：退出再登录，组件不显示"刷新失败"，并且能刷新。
- DeepSeek 卡片菜单 → 更新 Key：替换原账号，不新增卡片。
- 真实 Antigravity 额度用完的池显示 0%。
