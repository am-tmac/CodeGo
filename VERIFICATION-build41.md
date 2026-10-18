# CodexUsage 4.4 / build 41 — 去掉月预估

## 交付物

- `CodexUsage-4.4-build41-unsigned.ipa`（未签名，需自行重签）
- 1804126 bytes
- SHA-256: `f7880850e78625ef5972c44bd4e0e122015a89652798ff06c1dc1cfac43fca22`

## 改动

- App 用量页（tokens.ci 分析）：删除「月度预估」卡片；剩下三张卡片排成 2+1。统计口径说明里删掉"月度预估不线性外推"。
- 组件（tokens.ci 大尺寸）：删除底部「月预估 — · 不外推」一行。
- 删除始终返回 nil 的 `monthlyEstimate` 属性（TokensCISnapshot / TokensCIAnalytics），以及对应断言；README 同步更新。
- 版本：4.3 → 4.4，40 → 41。

## 验证

| 检查 | 结果 |
|---|---|
| 新合约 `test_no_monthly_estimate`（App/Shared/Widget 中无"预估"/"不外推"/`monthlyEstimate`） | 删除前失败，删除后通过 |
| `swift test` | 110 个测试，0 失败 |
| 模拟器 `xcodebuild test` | 89 个测试，0 失败 |
| `Tests/*_contract.py`（6 个） | 全部 OK；组件字节基线已按本次改动更新 |
| Release 构建 + 打包脚本 | 通过；App 和组件二进制中均不含"月预估"/"月度预估"/"不外推" |
