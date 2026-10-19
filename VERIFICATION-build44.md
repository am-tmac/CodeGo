# CodeGo 4.7 / build 44 — 新 App 图标

## 交付物
- `CodeGo-4.7-build44-unsigned.ipa`（未签名，需自行重签）
- SHA-256: `0c926a637cf3c2bfe62d59f31462ee53329a934e3ea11b15d1956b9e303f8485`

## 改动
- 新图标 Gauge G（墨黑 `#111214` / 白 / 青柠 `#C8F03C`），浅色、深色、着色三种外观；源 SVG 在 `Design/logo/final/`。
- 删除 `Scripts/draw_icon.swift`；`Scripts/configure.py` 生成的 AppIcon Contents.json 同步三外观。
- 版本 4.6 → 4.7，43 → 44。其余代码未改。

## 验证
| 检查 | 结果 |
|---|---|
| `swift test` | 119 个测试，0 失败 |
| `Tests/*_contract.py`（8 个，含新 `build44_icon_contract.py`）+ 签名检查 | 全部 OK |
| Release 构建 + 打包 | 通过，Bundle ID 与 build 43 一致 |
| `assetutil --info Assets.car` | AppIcon 含默认 / UIAppearanceDark / ISAppearanceTintable 三种 1024 图 |
| 主图标透明通道 | 无（RGB） |

未做：模拟器 `xcodebuild test`（本版只改资源与版本号）；真机三种外观的视觉确认。
