# CodexUsage 4.5 / build 42 — Codex 重置额度、OpenCode Go、Command Code

## 交付物

- `Dist/CodexUsage-4.5-build42-unsigned.ipa`（未签名，需自行重签）
- 2048618 bytes
- SHA-256: `04506aa6ad1459b36a4b63dc6daf34cda10ce5540cac3bdc34762d6a3b244d44`
- App / Widget：4.5 (42)，iOS 17.0，arm64。所有 target 均更新版本；Swift 5.0、Bundle ID、签名、entitlements、Keychain / App Group 标识未变。未提交。

## 三项功能与测试先行

测试先写入 `Tests/Build42ProviderTests.swift`，并加入 Xcode 测试 target，然后运行 SwiftPM 和 Xcode 定向测试。实现前的红灯是**缺少新类型/方法导致的编译失败**，不是运行期断言失败。失败清单写在测试文件开头；没有事后新增单元测试。后续只适配旧测试的版本/路由/组件规则及阻塞传输桩。

### 1. Codex 重置额度

- 文件：新增 `Shared/CodexResetCredits.swift`；修改 `Shared/AuthAPI.swift`、`Shared/Models.swift`、`Shared/Storage.swift`、`App/CodexUsageApp.swift`、`Shared/UsageViews.swift`、`Widget/CodexUsageWidget.swift`。
- 同一 transport / Bearer / ChatGPT-Account-Id 路由请求 `/wham/rate-limit-reset-credits`。主用量成功后才补充；补充失败或格式异常保留主用量及其原有 available_count。
- 状态字符串保留未知值；读取带/不带小数秒的日期。负 available_count 为格式错误。可用库存按 available 且未过期筛选，到期升序、无到期时间最后；明细存在时显示该库存张数。显示最早过期、倒计时、累计获得，不保存或显示 credit id。
- App 明细、现有中号 Codex 组件显示张数。原 Codex 组件只支持小/中号，本次没有新增大号布局。
- 测试：`testResetCreditsLenientStatusesExpiryAndOrdering`、`testResetCreditsSupplementaryRequestAndFallback`。
- SwiftPM / Xcode 红灯原文均包含：`error: cannot find 'CodexResetCredits' in scope`。

### 2. OpenCode Go

- 文件：新增 `Shared/OpenCodeGo.swift`、`App/OpenCodeGoPanel.swift`、`App/Assets.xcassets/LogoOpenCodeGo.imageset/`；共享接线文件见下。
- 仅 API Key，指定 GET 与请求头。窗口别名、内嵌 window、百分比优先、真实 used/limit、百分比限制、秒倒计时、ISO/epoch 秒/毫秒均由响应解析。Go 套餐金额仅显示说明，不参与计算；缺失数字显示 —。
- 测试：`testOpenCodeAliasesPrecedenceClampingAndMissingFields`、`testProviderTransportErrorsAndOptionalSubscription`、`testProviderCancellationAndNetworkMapping`、`testNewProviderSnapshotCacheIsolationAndCardOrder`；iOS 另有 `testAppNewProviderFailureKeepsSnapshotAndRefreshIsIsolated`。
- SwiftPM / Xcode 红灯原文均包含：`error: cannot find 'OpenCodeGoUsage' in scope`。

### 3. Command Code

- 文件：新增 `Shared/CommandCode.swift`、`App/CommandCodePanel.swift`、`App/Assets.xcassets/LogoCommandCode.imageset/`；共享接线文件见下。
- 仅 API Key，请求 `/alpha/billing/credits`；订阅接口失败不阻断。根级/credits 内 windowLimits、数字字符串、秒/毫秒时间戳均支持。monthlyCredits 始终作为剩余 USD。
- 分母优先使用 monthlyCreditsGranted；仅字段缺失时按明确 planId 表回退并显示「按套餐 X 计」。未知套餐无分母时只显示剩余金额，百分比 —。加购额度只在正值时显示。
- 测试：`testCommandRemainingGrantWindowsAndPlans`、`testProviderTransportErrorsAndOptionalSubscription`、`testProviderCancellationAndNetworkMapping`、`testNewProviderSnapshotCacheIsolationAndCardOrder`。
- SwiftPM / Xcode 红灯原文均包含：`error: cannot find 'CommandCodeUsage' in scope`。

### 共享接线

- 新增 `Shared/ProviderParsing.swift`、`Shared/ProviderCardData.swift`、`App/APIUsageAccountCard.swift`。
- 修改 `Shared/DashboardStore.swift`、`Shared/UsageViews.swift`、`App/ConnectViews.swift`、`App/CodexUsageApp.swift`、`Widget/CodexUsageWidget.swift`：沿用 DeepSeek 的 Keychain 命名空间、默认组查询、共享授权检查、缓存、租约、退避、账号目录、刷新错误、连接表单同意/清空、替换/移除和排序模式。不同 provider 的替换路由不会互传账号 id。
- `Shared/CardOrder.swift` 原逻辑已支持任意 provider:accountID，无需修改；新测试验证两个新 key 的持久排序语义。
- `Scripts/add_build42_sources.rb` 仅追加工程成员和更新版本，不运行会重写签名的工程生成器。Package.swift 已自动收集 Shared/*.swift 与 Tests/*.swift，因此不需要新增显式列表或依赖。
- 两个 logo 由本地 CodexBar MIT SVG 转换为 1x/2x/3x 透明模板 PNG，无 SF Symbol 占位。原 SVG 与来源说明在本机 `Research/build42-icons/`；转换工具 `Scripts/convert_build42_icons.swift` 使用系统 AppKit。
- `Tests/Fixtures/widget-bugfix-baseline.json` **有意更新** `Shared/UsageViews.swift` 和 `Widget/CodexUsageWidget.swift` 摘要：新刷新路由、新卡片、新倒计时、Codex 中号张数行；`Widget/Info.plist` 摘要未变。旧组件样式、单一刷新按钮、授权检查和 15 分钟请求策略保留。
- 回归发现既有 WidgetRefreshAttempt 重写相同 JSON 时键顺序不稳定，影响精确字节契约；`Shared/Storage.swift` 保存时使用 sortedKeys，字段和刷新预算语义不变。

## 验证

| 检查 | 实际结果 |
|---|---|
| 新测试红灯，SwiftPM / Xcode 定向 | 新类型未实现时均失败；日志 `Logs/build42-red-swift.log` / `Logs/build42-red-xcode.log` |
| 新测试绿灯，SwiftPM / Xcode 定向 | 7 / 8 项，0 失败 |
| `swift test` | 117 项，0 失败 |
| 模拟器 `xcodebuild test` | 97 项，0 失败，0 跳过，TEST SUCCEEDED |
| `Tests/*_contract.py` | 6 文件、34 项，全部 OK（3 + 4 + 4 + 2 + 2 + 19） |
| `Tests/signing_configuration_test.py` | 1 项，OK；另逐项比较工程签名/标识/Swift 版本无变动 |
| Release 构建 | `Release exit: 0` |
| 打包检查 | 通过 App/Widget 标识、版本、arm64、未签名、资源和新 API/Keychain 标记检查；ZIP 校验通过 |
| 原生 SwiftUI 离线渲染 | 亮/暗主题，Codex / OpenCode Go / Command Code / 组件视图，共 8 张不同 PNG；附 SHA-256 manifest |
| `git diff --check` | 通过 |

真实输出节选：

```text
Test Suite 'All tests' passed at 2026-10-19 12:51:11.633.
Executed 117 tests, with 0 failures (0 unexpected) in 4.856 (5.063) seconds

Executed 97 tests, with 0 failures (0 unexpected) in 6.216 (6.245) seconds
** TEST SUCCEEDED **

Release exit: 0
/Users/fangyang/Projects/CodexUsage/Dist/CodexUsage-4.5-build42-unsigned.ipa
sha256: 04506aa6ad1459b36a4b63dc6daf34cda10ce5540cac3bdc34762d6a3b244d44
bundle IDs preserved from private config; version: 4.5 (42)
```

日志：`Logs/build42-swift-test.log`、`Logs/build42-xcode-test.log`、`Logs/build42-contracts.log`、`Logs/build42-signing.log`、`Logs/build42-release.log`、`Logs/build42-package.log`。机器可读结果：`Logs/build42-xcode-summary.json`（passedTests 97 / failedTests 0 / skippedTests 0）。

Xcode 原始结果：`Build42Sim/Logs/Test/Test-CodexUsage-2026.10.19_12-51-06-+0800.xcresult`。截图：`Logs/build42-screenshots/`，含 `manifest.json`，可按下面脚本重新生成。

首次完整验证的失败也保留：旧版本/空态/组件倒计时契约已更新；精确 JSON 字节比较修复了键顺序；模拟器阻塞桩增加补充端点返回（主用量请求仍持有原屏障）。中断测试留下合成凭据，使后一次运行跳过 13 项；最终用同型号、同运行时、同命令的全新模拟器完成 97/97，原模拟器数据未清除。

## 复现

build 41 文档未列完整模拟器命令；沿用 build 39 文档、build 40/41 记录的 iPhone 17 Pro / ad-hoc 配置，仅将派生目录改为 Build42Sim。

```sh
swift test
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath Build42Sim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO test
for f in Tests/*_contract.py; do python3 "$f" -v; done
python3 Tests/signing_configuration_test.py
python3 Scripts/build42_release.py
python3 Scripts/package_widget_build42.py
python3 Scripts/verify_build42_visuals.py
shasum -a 256 Dist/CodexUsage-4.5-build42-unsigned.ipa
```

## 未验证 / 需手机验收

- 未使用真实 API Key 或真实 Codex 账号联网验证；请求与解析由离线合成响应验证，真实服务可用性、账号权限与付费套餐状态仍需账号验收。
- 截图为模拟器内真实 SwiftUI 视图的隔离渲染，包含组件布局；不声称已完成真机 WidgetKit 时间线调度、组件配置点击或跨签名 Keychain 握手测试。
- 真机重签、覆盖安装、首次解锁、组件实际后台预算和最大辅助字号仍需设备验收。
- 无 Cookie 导入、抓取、第三方依赖、凭据提交或 git commit。
