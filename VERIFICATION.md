# CodeGo 6.0 / build 48 — Widget 钥匙串探针失败不再整进程缓存

## 交付物
- `Dist/CodeGo-6.0-build48-unsigned.ipa`，未签名，保留 `PlugIns/CodeGoWidget.appex`、原 Bundle ID / App Group / 钥匙串标识 / Widget kind。
- SHA-256: `3acd27b5ab41182b9ce853b1fac89723beb9e3203077394f14001cc39a8532fe`
- 5.9 / build 47 IPA 保留未删；本版包含 5.9 的存储诊断、缓存清理、Incoming IPA 清理改动。

## 问题与修复
- 真机：Widget 诊断永远停在 `10:03:57`，默认探针 OSStatus -25308（锁屏时扩展进程启动），选中组为无，因而 `仅缓存 · 组件无刷新授权`。根因：`SharedStorage.capabilities` 是 `static let`，探针失败结果在整个（被 iOS 复用的）扩展进程生命周期内被缓存；诊断 `observedAt` 也是进程启动时间。
- 新 `Shared/KeychainCapabilityResolver.swift`：NSLock 保护；一旦解析出非 nil 组即在本进程内固定（不在令牌轮换中切换域）；未解析（-25308、-34018 等）时下次访问重探，30 秒内最多一次。只允许 nil → 组。`routing` / `diagnostics` / `permittedGroup` / `DashboardStore.canRefresh*` 每次动态读取，时间线路径在组解析后自动恢复刷新。
- Widget 写入诊断时 `observedAt` = 写入时间，另记 `probedAt`；诊断文本新增「探针时间」行（旧诊断文件可解码）。
- 5.9 → 6.0 / 47 → 48（bug 修复），8 个配置全部更新。

## 验证
- TDD：`Tests/KeychainCapabilityResolverTests.swift` 6 项先红（类型不存在）后绿：-25308 后过窗口重探得组；窗口内不重探；-34018 同样限频重探；已解析组不再变化且不再探测；64 并发仅探一次；诊断写入时间更新。
- `swift test`：131 测试，0 失败，exit 0。`Logs/build48-swift.log`。
- 模拟器 `xcodebuild test`（46F6007A-…）：105 测试，13 项 Existing credentials 跳过，0 失败，exit 0；新增 6 项在 iOS 实际执行。`Logs/build48-simulator.log`；`BuildCacheTest/Logs/Test/Test-CodeGo-2026.10.21_11-20-51-+0800.xcresult`。
- 8 个 contract 脚本 + 签名配置检查通过（widget_refresh_contract 新增 build48 防回退断言）；`git diff --check` 通过。
- `Scripts/release.py`：Release App/Widget 编译成功，ZIP 完整，App 与 appex Info.plist 均为 6.0 / 48。

未验证（需真机）：覆盖安装后锁屏启动的 Widget 解锁后是否在下一次时间线/快照中解析到 `ABCDE12345.*` 并恢复独立刷新；iOS 何时再调用时间线由系统决定。未提交、未推送。
