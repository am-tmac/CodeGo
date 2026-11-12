# build 50 / 6.2 刷新逻辑验证

分支：feat/widget-logic-refresh；基于 5c1a34d。没有改 App/ 界面、provider 解析、xcconfig 标识或生产视图的样式/布局。

## 实际执行结果（2026-11-12）

在仓库根目录执行：

```sh
swift test
xcodebuild -project CodeGo.xcodeproj -scheme CodeGo -destination 'platform=iOS Simulator,id=46F6007A-777A-46F8-BDAD-A069F5906532' -derivedDataPath /tmp/codego-dd test
(cd Tests && python3 -m unittest discover -p '*_contract.py')
```

三条命令最终退出码均为 0。SwiftPM 和 Xcode 的测试成员不同，所以数量不同。

swift test：`Executed 170 tests, with 0 failures (0 unexpected) in 2.497 (2.516) seconds`

xcodebuild test：`Executed 145 tests, with 0 failures (0 unexpected) in 6.637 (6.670) seconds`

Python 契约真实输出：

```text
.......................................
----------------------------------------------------------------------
Ran 39 tests in 0.016s

OK
```

Xcode 结果包：`/tmp/codego-dd/Logs/Test/Test-CodeGo-2026.11.12_16-47-05-+0800.xcresult`。截图作为 keepAlways 附件同时保存在此结果包中。完整终端日志：`/tmp/codego-swift-test.log`、`/tmp/codego-xcode-test.log`、`/tmp/codego-contract.log`。

## Keychain 逐 provider 审计

“可用”表示代码路径在已获得共享授权、账号 credentialGroup 等于 permittedGroup 且 Keychain 可访问时可用；未使用真实账号验证真机扩展读取。WIP 已包含全部显式 widget: true，本次逐项确认，无需重复修改 Service 或解析器。

| Provider | 结论 | 凭据读取路径 |
|---|---|---|
| Codex | 可用 | UsageService → SharedStorage / StorageRouting，精确 authorizedGroup，共享路由与授权校验 |
| DeepSeek | 可用 | DeepSeekService → DeepSeekStore.key，组件查询限定 permittedGroup |
| Claude | 可用（有效 access token） | ClaudeService → ClaudeStore.credential(widget: true)，限定 permittedGroup；续授权只能由 App 完成 |
| Antigravity | 可用 | AntigravityService → AntigravityStore.token，组件查询限定 permittedGroup |
| tokens.ci | WIP 已修：原本仅缓存 | DashboardStore 发布实际 credentialGroup；TokensCIService → TokensCIStore.token，限定 permittedGroup，退避键 tokensci:username |
| OpenCode Go | 可用 | OpenCodeGoService → OpenCodeGoStore.key，组件查询限定 permittedGroup |
| Command Code | 可用 | CommandCodeService → CommandCodeStore.key，组件查询限定 permittedGroup |
| OpenRouter | 可用 | OpenRouterService → OpenRouterStore.key，组件查询限定 permittedGroup |
| Ollama Cloud | 可用 | OllamaCloudService → OllamaCloudStore.key，组件查询限定 permittedGroup |
| Qoder | 可用 | QoderService → QoderStore.key，组件查询限定 permittedGroup |

以上 Service 均检查 widget 授权，Store 均拒绝组件未授权读取；不会通过组件绕过授权或复制凭据。

## 行为与回归证据

- 按钮先重新解析配置中的账号，再检查授权、退避、正在刷新和 Claude 续授权状态；每个允许的账号最多调用一次，同一账号两栏去重。
- 不满足条件时不调用 Service，仍 reloadTimelines 读取缓存。中号两栏独立判断，小号仅处理显示的一栏。
- 手动刷新不受缓存新鲜度门槛限制；成功后 20 秒冷却，失败从 5 分钟指数退避，最长 1 小时。
- 时间线策略仍是 .after(Date() + 900 秒)，另检查 5 分钟缓存新鲜度；系统最终调度时间由 WidgetKit 决定。
- 本次修复失败尝试不返回账号 ID 的问题，使时间线立即重读失败状态并保留缓存。单账号错误被隔离，不向时间线抛出。
- 新增覆盖在实现修改前列出失败场景：无授权/退避无 HTTP、成功一次并写回、失败保留快照字节并持久化退避；intent 不满足条件不调 Service；直接对 RefreshWidgetIntent 编解码（含空参数）。
- 初始 Python 为 39 项、1 失败：旧字节哈希未同步。保留所有原断言并重钉审阅后的哈希，注释说明原先保护组件视觉不漂移的意图。

## 截图重现

WidgetRenderTests 在 iOS 模拟器测试进程中渲染实际 DashboardWidgetView，固定合成数据、深色、小号 170×170 pt 与中号 364×170 pt，3× PNG；使用同一个生产 RefreshAffordance / AppIntent 按钮。DEBUG 测试条件只用于注入 WidgetKit 的只读 family 环境值；Release 不包含渲染辅助代码。

重新运行上述 xcodebuild test 即导出 render-small.png 与 render-medium.png，并保留 xcresult 附件。已人工检查两张图：右上角按钮可见，未遮挡标题、数值或双栏内容。此处为组件视图渲染截图，不代表桌面 WidgetKit 的真实交互或系统调度验证。

PNG SHA-256：

- `render-medium.png`：`d2eb2fa8e336f3cf2d8480aca662e8b382c2df28d4aca0535f4474557565ddd7`
- `render-small.png`：`feddce2be633d0317d2b9fdb1f15ccb5c943095da8f5a32ff72e8606c310fbf1`

## 未验证范围

真机 Keychain/桌面点击与后台刷新、系统真实限流和锁定状态下的进程恢复、锁屏组件均未验证。本轮未连接真机、未出 IPA、未 push、未合并或修改其他分支。
