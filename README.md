# CodexUsage · iPhone + WidgetKit

> 非 OpenAI、Google 或 DeepSeek 官方产品。项目按 MIT License 开源；品牌名称仅用于描述兼容服务。

独立 SwiftUI iOS 17+ 自用 App：iPhone 自行设备代码 OAuth 登录、直接读取 Codex 额度，在共享签名获授权时 WidgetKit 自行请求更新。没有 Mac 后端、CLIProxyAPI、CLI、Cookie 导入或第三方运行时依赖。没有读取/复制电脑已有的 OAuth 凭据。

## 4.5 / build 42：重置额度、OpenCode Go、Command Code

- Codex 增加独立重置额度明细请求：按可用状态和到期时间筛选，显示张数、最早过期时间和累计获得；请求失败仍显示原用量接口的张数，不影响主额度刷新。中号组件增加紧凑张数行。
- OpenCode Go：仅 API Key，读取 5 小时 / 每周 / 每月百分比与重置时间。套餐金额只作说明，不用于计算；Key 从 https://opencode.ai/auth 获取。
- Command Code：仅 API Key，读取窗口用量、本月剩余额度和加购额度。月度分母优先使用接口 grant；缺失时仅使用已知 planId 表并标注「按套餐 X 计」，未知套餐不推算百分比。Key 从 https://commandcode.ai/settings/keys 获取。
- 两项服务沿用 DeepSeek 的本机钥匙串、替换/清除、快照缓存、卡片排序、独立刷新/移除和组件授权/退避。接口缺失字段显示「—」。新图标由用户提供的 CodexBar MIT SVG 转为模板 PNG。
- 构建：`python3 Scripts/build42_release.py` → `python3 Scripts/package_widget_build42.py`，产物写入 `Dist/`。实测、红灯日志与边界见 `VERIFICATION-build42.md`；组件字节基线因新增显示和刷新路由刻意更新。

## 4.1 / build 38：移除用量页顶部说明行

- 用量页顶部「只读用量由电脑上的 tokens CLI 上报…」整段说明已移除，账号信息直接作为页面开头；其余区块、统计口径、状态页、设置页与小组件均未改动。
- 构建：`python3 Scripts/build38_release.py` → `python3 Scripts/package_widget_build38.py`。实测与边界见 `VERIFICATION-build38.md`。

## 4.0 / build 37：完整 tokens.ci 用量分析（历史）

- 已实现账号身份、累计与时段总量、可选日期热图、同日客户端、四项分析、原生 Charts 日堆叠 Token/费用切换、7/30/90 天、Provider/模型展开、Token 组成及一年星期习惯/峰值日。
- 真实 `contributions` 计算；最近上报日明确标注，不冒充今日。消息口径冲突显示 —，缓存读取占比不是请求命中率。
- 历史保存在 App 私有 Application Support，共享快照不含历史；旧缓存缺少历史时提示刷新。小组件源文件与 build36 字节相同，Charts 仅链接主 App。
- 构建：`python3 Scripts/build37_release.py` → `python3 Scripts/package_widget_build37.py`。实测与边界见 `VERIFICATION-build37.md`；未提交/推送。

## 3.2 / build 36：同日用量对齐（历史）

- 今日以设备本地日历日期匹配接口 `contributions[].date`；总量、客户端和模型来自同一组日记录，不再混入历史客户端累计。模型旁显示该模型费用；条形分母为同日总 Token。
- 这不是 UTC 日换算：当前 CLI 按固定分桶时区生成日期，接口只返回整日桶、不带可靠分桶时区。界面明确标「上报日」；电脑时区须与设备一致。旧数据或异区桶无法精确拆分，不用 `timestampMs` 的首条消息时间移动整桶。
- 历史缓存保留；跨日旧值标「缓存日 YYYY-MM-DD」而非今日；升级前混期缓存的日数据须刷新，累计保留。无今日记录时显示 0、无客户端。
- 累计 Token / 累计缓存读取占比明确标累计。不显示月预估（4.4 起移除）。
- 构建：`python3 Scripts/build36_release.py` → `python3 Scripts/package_widget_build36.py`；交付与来源见 `VERIFICATION-build36.md`。SwiftPM 94、签名模拟器 Debug 84、静态契约 19+4+2+2+3 及签名检查通过。

### 3.1 / build 35：用量连接入口（历史）

- 用量页不再内嵌用户名/read token 表单；标题栏刷新左侧的 `+` 和空状态的「连接 tokens.ci」直接打开专用 sheet，不进入订阅额度服务选择器。
- 复用唯一的 `.sheet(item:)`，关闭/进入后台清空未提交字段与同意状态。原数据卡、指标、每账号刷新/移除/错误保持不变。
- tokens.ci 小组件仍只读缓存；约 15 分钟 timeline 请求只重读缓存，不联网，更新数据需要打开 App。
- 当前构建：`python3 Scripts/build35_release.py` → `python3 Scripts/package_widget_build35.py`。产物与实测记录见 `VERIFICATION-build35.md`；签名标识来自本机私有配置。
- 回归：`python3 Tests/tokensci_navigation_contract.py -v`、既有静态契约、`swift test`、ad-hoc 签名模拟器测试和 iphoneos Release。真机重签/覆盖安装/触摸与布局仍需设备确认。

## 打开与真机签名

1. 打开 `CodexUsage.xcodeproj`，选择 `CodexUsage` scheme。
2. App、Widget 两个 target 的 Signing & Capabilities 选择你自己的开发者 Team。没有预置任何个人证书或 Team ID；无需提供私钥或密码给助手。
3. 将 App Bundle Identifier 改成你拥有的唯一 ID（例如 `com.yourname.CodexUsage`），Widget 必须是 App ID 的子前缀（例如 `com.yourname.CodexUsage.Widget`）。测试 target 也可改成自己的 ID。
4. **两个 target** 的 Build Settings 中把 `APP_GROUP_IDENTIFIER` 改成同一个已在开发者账号注册的 App Group（例如 `group.com.yourname.CodexUsage`）；把 `KEYCHAIN_GROUP_IDENTIFIER` 改成同一个 `com.yourname.CodexUsage.shared`。现有 entitlements 与 Info.plist 使用这些变量。Signing & Capabilities 中确认两个 target 都具有相同的 App Groups 和 Keychain Sharing，实际 provisioning profile 也必须包含它们。
5. 连接 iPhone，开启开发者模式，选择设备，Run。Xcode 自动签名会按你的授权创建/下载开发配置；本次构建没有修改全局签名或 provisioning profiles。
6. iPhone App 点击「使用 ChatGPT 登录」，在官方 `https://auth.openai.com/codex/device` 输入本机生成的代码。必要时在 ChatGPT 安全设置启用设备代码授权。返回 App 等待完成。不要接受别人发来的代码。
7. 长按主屏幕添加「Codex 额度」小号组件。开发签名有有效期，需按配置重新安装/续签；不需要 App Store 发布。

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

- 白底中文主界面，5 小时 / 1 周剩余额度、胶囊进度条、本地重置时间、手动/下拉/返回前台刷新。
- 小号白色 Widget：Codex、5h / 7d、REMAINING 百分比、灰色重置倒计时；低额度红色，高额度绿色。无数据用 `—`，不把缺失窗口误报为 100%。
- 组件右上角仅在获得共享刷新授权时显示 AppIntent 按钮，扩展内联网刷新（`openAppWhenRun=false`，不打开 App）；仅缓存状态不显示圆形按钮，而显示授权状态，需打开 App 刷新。点击后持久化「已开始」，组件重绘时显示静态「刷新中…」，完成或失败都会清除该状态；扩展被系统终止时，下一次取得账号独占锁会按「已中断」回收并保留原有节流。文字为静态标签，不伪造动画；点击后 timeline 重绘由系统调度，**不代表即时刷新**。
- OAuth token 按账号分别放在 Keychain；共享签名获授权时使用共享组，否则使用不指定 access group 的 App 私有查询与独立 service，`AfterFirstUnlockThisDeviceOnly`；不写入 App Group 缓存，不进入日志，不云同步。App Group 仅保存额度快照及锁文件。
- App / Widget 用同一内核文件锁保护「读取 token → 续期 → 保存轮换 token → 请求 → 写快照」，跨进程并发刷新不重复使用同一 refresh token。锁忙立即返回并保留旧数据，进程退出自动释放锁。
- 过期前续期，401 仅尝试一次续期后重试；刷新错误保留旧快照并显示错误。超过 30 分钟或窗口已过重置点显示过期，不凭时间推测已恢复额度。
- 设备轮询处理 403/404 等待、15 分钟超时、取消；授权码交换使用服务返回的 PKCE verifier。JWT 只读路由/过期提示，不把未验签 claims 当作身份验证。
- Widget 请求约 30 分钟后的 timeline；**实际刷新时机受 iOS 电量/后台预算控制，不能保证实时**。首次开机未解锁、系统终止网络、网络拦截等情况保留快照。
- 支持两个及更多独立设备授权账号；分开显示、刷新、移除，不合并额度。相同 subject + workspace 的重新授权更新原账号；缺失 subject 时不猜测合并。保留旧 phone-owned Keychain 项与 usage.json。没有跨签名读取旧凭据的权限时需要重新登录。暂不支持附加模型限额、余额或历史统计。

## 非公开接口与来源

本 App 非 OpenAI 官方产品。设备代码客户端 ID 与协议依据 OpenAI 开源 Codex；`chatgpt.com/backend-api/wham/usage` 是非公开端点，**不是承诺稳定的公开 API**。服务可能限制第三方客户端、账号、地区、授权方式或返回格式。本工程编译与离线协议测试通过不等于已验证你的账号能成功登录。

实现为独立 Swift 代码，参考协议而非复制上游实现。研究资料保留在 `Research/`，不加入编译：

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

```sh
# 无需 Ruby 或生成器，现有 Xcode 工程可直接使用
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath BuildDevice CODE_SIGNING_ALLOWED=NO build

# 核心模型与协议测试（macOS，不访问真实账号）
swift test

# 模拟器完整测试：使用本地 ad-hoc 签名，不用个人证书。
# 不能关闭签名运行安全存储测试：App Groups/Keychain 需要 entitlements。
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath BuildSignedSim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test
```

测试涵盖：used→remaining、缺失/越界窗口、过期、device interval、等待状态、PKCE/表单编码、refresh token 轮换兼容、撤销、授权/账号请求头、取消、429、错误响应；iOS 额外测试真实模拟器 Keychain + App Group 缓存读写/清除以及并发文件锁。测试中的 token 是明确标记的合成夹具，不是抓取的真实凭据。

`Logs/` 保留真实构建/测试日志和 `.xcresult`。早期失败记录也保留：扩展 Bundle ID 前缀错误已修复；关闭签名时安全存储测试因缺 entitlements 失败，改用 ad-hoc 模拟器签名后通过。真机实际 OAuth、账号额度、跨进程刷新轮换、系统 Widget 调度尚须用户签名并登录后验证。

## 工程维护

- `App/` SwiftUI App 和绘制图标；`Widget/` WidgetKit；`Shared/` 协议/存储/视图；`Tests/` XCTest。
- `Scripts/generate_project.rb` 使用项目内 `.tools/gems` 的 xcodeproj 可重建工程（**会覆盖你在 Xcode 手改的签名设置，修改脚本再生成**）。
- `Scripts/configure.py` 生成 plist/entitlements/asset metadata；`Scripts/draw_icon.swift` 使用 AppKit 矢量路径绘制 1024px 图标。
- 没有全局 gem 安装；运行 App 不依赖这些生成工具。

## 兼容重签版（compatible-unsigned）

- 已定位原故障：设备 OAuth 成功后，安装凭据前创建共享锁时因 App Group 不可用而失败；并非尚未完成授权。
- 同时具备可用 App Group 与经 Keychain 非秘密写入探测确认的共享组时保留共享路径。Info.plist 的旧 Team 前缀不可作为权限证明；从本机新建的非秘密 Keychain 探测项返回属性取得实际默认组前缀，再验证共享候选组。没有读入任何用户 token 作为探测。
- 任一共享条件不满足：主 App 使用本机 Application Support 缓存/锁和独立 Keychain service；私有查询完全省略 kSecAttrAccessGroup，不用空字符串冒充默认组。token 仍为 AfterFirstUnlockThisDeviceOnly，不写明文文件、不日志输出。
- Widget 不回退到扩展自己的私有登录；显示「共享未授权 · 打开 App 配置」。购买 p12/全能签不能自动赋予 App Groups 权限。App 与 Widget 都必须获得相同共享授权，才能共享查询。首次解锁前探测可能保守进入兼容模式，请解锁后重启进程再试。
- 重签更换 Team/Bundle ID 可能导致旧钥匙串不可访问。此前 OAuth 已成功但保存失败的用户安装新版后需重新登录；保存失败提示明确说明授权完成、解锁/检查签名/重新登录。
- 多账号：点「添加账号 / 重新授权」，在官方授权页退出/切换账号后授权第二个账号；不要继续使用浏览器里第一个账号的会话。App 使用明确的本机账号序号/标识，不声称未验证的邮箱身份。共享可用时点「用于组件」选择唯一的组件账号；本版不是每个 Widget 实例独立选择账号。
- App 与 Widget 跟随系统深浅色，使用语义背景与前景色。iOS 26+ 登录/添加按钮使用原生 Liquid Glass（glassProminent），iOS 17–25 使用常规按钮和 material 回退。额度数据不覆盖玻璃，Widget 保留 Codex / 5h / 7d 的紧凑布局；没有调用不支持的 Widget 玻璃接口。没有额外外观设置开关。
- 当前包：`~/Downloads/CodexUsage-3.2-build36-tokensci-unsigned.ipa`，含 Widget，未签名，须自行重签安装；模拟器测试不能代替购买证书下的真机 OAuth、联网刷新和触摸验收。

### 旧版变更摘要（已清理旧版产物）

- build 24：DeepSeek 小号组件的刷新控件贴黑卡右下角（44pt 点击区距右/底各 4pt），金额行预留 48pt。
- build 23：Codex 的刷新控件移到组件整体右上角；DeepSeek 按钮曾上移过多，build 24 已修正。
- build 22：把组件刷新授权的严格握手与经风险确认的手动授权分开；配置的 Keychain 组不代表真实 entitlement，只使用本机实测的精确组。Claude 登录移到状态页 ChatGPT 登录下方。
- build 21：已授权时是组件内 AppIntent 真刷新；未授权时为不同外观的「打开 App」控件，不把打开 App 伪装成刷新。Claude 改为 OAuth 账号登录；删除旧的 WebKit 会话和手动 sessionKey 路径。
- 历史 build34 构建：`python3 Scripts/build34_release.py`，然后 `python3 Scripts/package_widget_build34.py`；使用 `Build34Direct`，私有 ID 只从 `Private.xcconfig` 读取并显式覆盖工程设置。详情见 `VERIFICATION-build34.md`。

## 当前版本

当前源码对应 **3.2 / build 36**。底栏依次为「状态 / 用量 / 设置」；状态页原有四类账号卡、登录和刷新逻辑保留，用量页独立提供 tokens.ci 连接与只读用量。

- 修复旧实现把顶层 `clients: string[]` 当对象解码的问题，实际客户端/模型统计来自 `contributions[].clients`。保存了不含凭据的公开 API 完整响应供回归重放。
- 今日按设备本地日历日期匹配上报日，缺记录显示 0，不把最后上报日冒充今日；费用是模型定价估算、不是账单。缓存百分比定义为缓存读取 Token / 总 Token。
- 错误归属每个账号，显示于对应卡片，保留缓存；说明换行。tokens.ci 小组件真实 16pt 内边距、跟随共享主题，仅缓存并明确打开 App 更新。
- 验证：核心 91、模拟器 84、静态契约 19+4+3+1 项通过；8 个真实 SwiftUI 组件渲染。完整边界与 SHA-256 见 `VERIFICATION-build34.md`。
- 后续版本约定：修复营销版本 +0.1（3.1、3.2），重大功能 +1（4.0）；内部 build 继续单调递增。

build 31 保留的登录可靠性修复：

- ChatGPT 设备代码登录在等待授权期间遇到断网、429 或 5xx 时继续轮询（429 后放慢），15 分钟仍超时；授权码换取令牌只能用一次，失败仍直接报错。
- 刚轮换出的 Codex 令牌若请求用量即返回 401，不再第二次轮换刷新令牌。
- App 刷新后组件 timeline 不再立刻重复请求：缓存 5 分钟内的槽位直接显示缓存；组件内刷新按钮不受影响。每栏只读取自身服务的缓存。

build 30（刷新可靠性与无障碍）的变更摘要见提交历史。核心测试 87 项、签名模拟器测试 82 项、静态契约 19+1+3 项通过，设备 Release 构建与未签名 IPA 校验通过。完整证据、SHA-256 和待真机验收项见 `VERIFICATION-build31.md`。未验证真实账号 OAuth/联网、手机签名下的 WidgetKit 或物理触摸效果。
