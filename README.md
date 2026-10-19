# CodeGo · iPhone + WidgetKit

> 非 OpenAI、Anthropic、Google、DeepSeek、OpenCode 或 Command Code 官方产品。项目按 MIT License 开源；品牌名称仅用于描述兼容服务。

CodeGo（原名 CodexUsage）是独立 SwiftUI iOS 17+ 自用 App：iPhone 自行设备代码 OAuth 登录、直接读取 Codex 额度，在共享签名获授权时 WidgetKit 自行请求更新。没有 Mac 后端、CLIProxyAPI、CLI、Cookie 导入或第三方运行时依赖。没有读取/复制电脑已有的 OAuth 凭据。

## 版本

当前 **4.7 / build 44**。逐版变更与验证记录见 Git 提交历史；最近一次的实测结果见 `VERIFICATION.md`。

- 4.7 (44)：新图标 Gauge G（白色 G + 青柠仪表指针，墨黑底），浅色 / 深色 / 着色三种外观。
- 4.6 (43)：改名 CodeGo；Codex 组件底部显示「重置积分 N · 更新 时间」，不再显示账号名。
- 4.5 (42)：Codex 重置积分明细；新增 OpenCode Go、Command Code（API Key）。
- 4.4 (41) 及更早：tokens.ci 用量分析、Antigravity、Claude OAuth、DeepSeek 余额、多账号与组件刷新授权等。

版本约定：修复 +0.1，重大功能 +1；build 号单调递增。

## 打开与真机签名

1. 打开 `CodeGo.xcodeproj`，选择 `CodeGo` scheme。
2. App、Widget 两个 target 的 Signing & Capabilities 选择你自己的开发者 Team。没有预置任何个人证书或 Team ID；无需提供私钥或密码给助手。
3. 将 App Bundle Identifier 改成你拥有的唯一 ID（例如 `com.yourname.CodexUsage`），Widget 必须是 App ID 的子前缀（例如 `com.yourname.CodexUsage.Widget`）。测试 target 也可改成自己的 ID。
4. **两个 target** 的 Build Settings 中把 `APP_GROUP_IDENTIFIER` 改成同一个已在开发者账号注册的 App Group（例如 `group.com.yourname.CodexUsage`）；把 `KEYCHAIN_GROUP_IDENTIFIER` 改成同一个 `com.yourname.CodexUsage.shared`。现有 entitlements 与 Info.plist 使用这些变量。Signing & Capabilities 中确认两个 target 都具有相同的 App Groups 和 Keychain Sharing，实际 provisioning profile 也必须包含它们。
5. 连接 iPhone，开启开发者模式，选择设备，Run。Xcode 自动签名会按你的授权创建/下载开发配置；本次构建没有修改全局签名或 provisioning profiles。
6. iPhone App 点击「使用 ChatGPT 登录」，在官方 `https://auth.openai.com/codex/device` 输入本机生成的代码。必要时在 ChatGPT 安全设置启用设备代码授权。返回 App 等待完成。不要接受别人发来的代码。
7. 长按主屏幕添加 CodeGo 组件。开发签名有有效期，需按配置重新安装/续签；不需要 App Store 发布。

### 本机私有配置

公开仓库不包含个人 Bundle ID、App Group、Team 前缀或第三方 OAuth 凭据。复制
`Configuration/ProvidedProfile.xcconfig` 为 `Configuration/Private.xcconfig`，填入自己的签名标识；
该文件已被 `.gitignore` 排除。Antigravity 是可选功能：只有你拥有或获准使用对应 OAuth 客户端时，
才填写 `ANTIGRAVITY_CLIENT_ID` 与 `ANTIGRAVITY_CLIENT_SECRET`。留空时项目仍可编译，登录按钮会禁用。

## 许可证与商标

- 源代码使用 [MIT License](LICENSE)。
- OpenAI、ChatGPT、Codex、Claude、Anthropic、Google、Antigravity、DeepSeek 等名称和商标归各自权利人所有。
- OpenCode Go / Command Code 的 logo 来自用户提供的 CodexBar（MIT）SVG，使用系统工具转换为透明模板 PNG；来源项目：https://github.com/steipete/CodexBar 。
- 其余 App 内的服务商 logo（`App/Assets.xcassets/Logo*`）来自 [@lobehub/icons](https://github.com/lobehub/icons)（MIT），仅用于标识对应服务；MIT 许可不包含商标授权，本项目与上述公司无关联、未获其认可。如需商用或分发，请自行确认商标使用规范，或替换为自己的图标。
- 仓库不分发来源不明的设计参考图。
- 所有账号接口都有变更、限流或禁止第三方客户端的风险；使用者应自行确认服务条款和授权范围。

## 功能与安全边界

- 中文界面：Codex、Claude、Antigravity、OpenCode Go、Command Code 订阅额度，DeepSeek 余额，tokens.ci 用量；手动/下拉/返回前台刷新。
- 组件：Codex 5h / 7d 百分比与重置时间，底部重置积分与更新时间；其他服务各自的额度。无数据用 `—`，不把缺失窗口误报为 100%。
- 组件右上角仅在获得共享刷新授权时显示 AppIntent 按钮，扩展内联网刷新（`openAppWhenRun=false`，不打开 App）；仅缓存状态不显示圆形按钮，而显示授权状态，需打开 App 刷新。点击后持久化「已开始」，组件重绘时显示静态「刷新中…」，完成或失败都会清除该状态；扩展被系统终止时，下一次取得账号独占锁会按「已中断」回收并保留原有节流。文字为静态标签，不伪造动画；点击后 timeline 重绘由系统调度，**不代表即时刷新**。
- OAuth token 按账号分别放在 Keychain；共享签名获授权时使用共享组，否则使用不指定 access group 的 App 私有查询与独立 service，`AfterFirstUnlockThisDeviceOnly`；不写入 App Group 缓存，不进入日志，不云同步。App Group 仅保存额度快照及锁文件。
- App / Widget 用同一内核文件锁保护「读取 token → 续期 → 保存轮换 token → 请求 → 写快照」，跨进程并发刷新不重复使用同一 refresh token。锁忙立即返回并保留旧数据，进程退出自动释放锁。
- 过期前续期，401 仅尝试一次续期后重试；刷新错误保留旧快照并显示错误。超过 30 分钟或窗口已过重置点显示过期，不凭时间推测已恢复额度。
- 设备轮询处理 403/404 等待、15 分钟超时、取消；授权码交换使用服务返回的 PKCE verifier。JWT 只读路由/过期提示，不把未验签 claims 当作身份验证。
- Widget 请求约 30 分钟后的 timeline；**实际刷新时机受 iOS 电量/后台预算控制，不能保证实时**。首次开机未解锁、系统终止网络、网络拦截等情况保留快照。
- 支持两个及更多独立设备授权账号；分开显示、刷新、移除，不合并额度。相同 subject + workspace 的重新授权更新原账号；缺失 subject 时不猜测合并。保留旧 phone-owned Keychain 项与 usage.json。没有跨签名读取旧凭据的权限时需要重新登录。暂不支持附加模型限额、余额或历史统计。

## 非公开接口与来源

本 App 非 OpenAI 官方产品。设备代码客户端 ID 与协议依据 OpenAI 开源 Codex；`chatgpt.com/backend-api/wham/usage` 是非公开端点，**不是承诺稳定的公开 API**。服务可能限制第三方客户端、账号、地区、授权方式或返回格式。本工程编译与离线协议测试通过不等于已验证你的账号能成功登录。

实现为独立 Swift 代码，参考协议而非复制上游实现。参考资料：

- https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/server.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/token_data.rs
- https://github.com/steipete/CodexBar/blob/main/docs/codex.md
- https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift
- https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexTokenRefresher.swift
- https://github.com/steipete/CodexBar/issues/439 （作者声称 iOS 设备 OAuth + 用量实机已运行；不是本工程实测证据）

Claude 用量走的是 **Claude Code 自己的 OAuth 客户端**：`https://claude.ai/oauth/authorize`（PKCE S256，redirect `http://localhost:54545/callback`，scope `user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`）、`POST https://platform.claude.com/v1/oauth/token`、`GET https://api.anthropic.com/api/oauth/usage`（带 `anthropic-beta: oauth-2025-04-20`）。这与用户本机 CLIProxyAPI 使用的机制相同；该客户端 ID 属于公开客户端，只能为使用者自己的账号签发令牌，不是新增授权范围。

Anthropic 的政策不允许第三方 App 提供 Claude.ai 登录或收集、存储、转交 Claude.ai 会话令牌；个人非公开发布本身不构成授权。这些端点是非公开接口，随时可能改变或封禁，因此本 App 只读订阅用量、不代发模型请求，并在界面上如实说明。

依据（2026-09-24 复现，`curl` 无凭据直连 `api.anthropic.com`）：`/api/oauth/profile` 返回 401 `Missing Authorization header. Please provide an OAuth token as a Bearer token.`，`/api/oauth/usage` 返回 429 `rate_limit_error`，而同目录下不存在的路径返回 404 `not_found_error` —— 说明这两条 OAuth 路由真实存在且要求 Bearer。授权页与 token 端点由本机 CLIProxyAPI 的管理接口 `GET /v0/management/anthropic-auth-url` 交叉确认（authorize URL、固定回调端口 54545、scope 列表逐项一致）。以上是**端点存在性**证据，**不是**本工程在你的账号上完成登录或取到用量的证据。

## 构建与测试

发布未签名 IPA（版本号取自工程，私有标识取自 `Configuration/Private.xcconfig`）：

```sh
python3 Scripts/release.py   # → Dist/CodeGo-<版本>-build<号>-unsigned.ipa
```

其他：

```sh
# 无需 Ruby 或生成器，现有 Xcode 工程可直接使用
xcodebuild -project CodeGo.xcodeproj -scheme CodeGo \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath BuildDevice CODE_SIGNING_ALLOWED=NO build

# 核心模型与协议测试（macOS，不访问真实账号）
swift test

# 模拟器完整测试：使用本地 ad-hoc 签名，不用个人证书。
# 不能关闭签名运行安全存储测试：App Groups/Keychain 需要 entitlements。
xcodebuild -project CodeGo.xcodeproj -scheme CodeGo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath BuildSignedSim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

测试涵盖：used→remaining、缺失/越界窗口、过期、device interval、等待状态、PKCE/表单编码、refresh token 轮换兼容、撤销、授权/账号请求头、取消、429、错误响应；iOS 额外测试真实模拟器 Keychain + App Group 缓存读写/清除以及并发文件锁。测试中的 token 是明确标记的合成夹具，不是抓取的真实凭据。

`Logs/`（不入库）存放本机构建/测试日志。真机实际 OAuth、账号额度、跨进程刷新轮换、系统 Widget 调度尚须用户签名并登录后验证。

## 工程维护

- `App/` SwiftUI App；`Widget/` WidgetKit；`Shared/` 协议/存储/视图；`Tests/` XCTest 与静态契约（`Tests/*_contract.py`）；`Design/logo/` 图标源文件。
- `Scripts/generate_project.rb` 使用项目内 `.tools/gems` 的 xcodeproj 可重建工程（**会覆盖你在 Xcode 手改的签名设置，修改脚本再生成**）。
- `Scripts/configure.py` 生成 plist/entitlements/asset metadata；App 图标源文件在 `Design/logo/final/`（SVG：浅色 / 深色 / 着色三种外观），1024px PNG 由其渲染。
- 没有全局 gem 安装；运行 App 不依赖这些生成工具。
