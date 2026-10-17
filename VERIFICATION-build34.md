# CodexUsage 3.0 / build 34 — tokens.ci repair

## Delivered artifact

- `/Users/fangyang/Downloads/CodexUsage-3.0-build34-tokensci-unsigned.ipa`
- 1,587,554 bytes
- SHA-256: `51d0c49c880422e4d911597649f9b42e7920e10e58683ef1662228e29d7fd7f8`
- App + Widget extension: marketing 3.0, build 34, arm64, minimum iOS 17.0; private bundle/group identifiers compared in memory to `Configuration/Private.xcconfig`, unchanged and not reproduced here.
- ZIP integrity passed; both Info.plists read back from archive; no `_CodeSignature` or embedded provisioning profile. Packager validates unsigned binaries, provider assets and new user-visible binary markers.

## Root cause and changes

The previous uncommitted build32 implementation decoded top-level `clients` as a dictionary. The real endpoint returns `string[]`, so the entire response threw `.malformed`, including for public profiles. A saved Keychain entry was not proof of valid authorization. Daily `contributions[].clients` supplies the actual token breakdown and nested model dictionary.

- Read local upstream `web/src/lib/types.ts`, `publicProfileData.ts` and token summation implementation; retrieved the full public `GET https://tokens.ci/api/users/Alice39s` response without Authorization. Initial `junhoyeo` lookup returned 404; a public leaderboard lookup supplied an existing profile. No user token or private-account request was used.
- Retained complete real response in `Tests/Fixtures/tokensci-public.json` (388,075 bytes), SHA-256 `8a839cac547e6d1ba30367ab33113083ffa8d9b54fa6c8af050285823c6eeb8a`. Fixture is replayed through HTTPTransport; it is not fabricated.
- Correct client/model accumulation across returned daily buckets. Totals stay service all-time stats; UI discloses daily client details may cover less history.
- Exact UTC today matching; absent day = 0 reported tokens, never latest day masquerading as today. Fractional ISO timestamps supported. Current calendar month subtotal no longer means rolling 30 days. Monthly forecast intentionally unavailable: sparse uploads cannot justify extrapolation. Costs labeled estimated/non-billing. Cache ratio explicitly cache-read tokens / total tokens.
- tokens.ci state, targeted/full/automatic refresh and account-specific safe error attribution use UsageModel; failure retains cache. Error is next to the affected profile, not hidden in connection form. Read token fields are cleared on leave/background. Descriptions wrap in card content.
- Native tabs 状态 / 用量 / 设置. tokens.ci connection/display appears only under 用量. Original status-card rendering/order/menus/provider logos/palettes remain unchanged; build31 login code retained.
- Dedicated widget has real 16pt content padding, shared-theme resolution and honest cache-only labeling/open-App routing. Dashboard slot renders tokens.ci; cache-only dispatch cannot fall through into Codex networking. Catalog deliberately publishes no tokens.ci refresh credential group. Quota widget retains its existing interactive refresh behavior.
- Internal build34 exceeds delivered33; all six marketing settings now 3.0. Future requested marketing convention is documented in README.

## Executed evidence

| Check | Actual result | Log |
|---|---|---|
| Initial decoder regression RED | 4 tests, 4 failures (3 malformed errors plus empty token accepted) | `Logs/build34-red.log` |
| Initial navigation/layout contract RED | failed as expected | `Logs/build34-ui-red.log` |
| Targeted decoder regression GREEN | 4 tests, 0 failures (final rerun with exact captured public totals) | `Logs/build34-targeted.log` |
| Targeted App model + real Keychain/cache service regression | 2 tests, 0 failures, no skips | `Logs/build34-model-targeted.log` |
| Widget policy contract | 19 passed | `Logs/build34-contract.log` |
| tokens.ci navigation/state/padding/version contract | 4 passed | `Logs/build34-ui-contract.log` |
| Existing widget shape contract | 3 passed | `Logs/build34-shape.log` |
| Signing configuration contract | 1 passed | `Logs/build34-signing.log` |
| Final SwiftPM suite | 91 tests, 0 failures | `Logs/build34-swift.log` |
| Final ad-hoc signed iOS Simulator Debug suite | 84 tests, 0 failures, TEST SUCCEEDED | `Logs/build34-simulator.log` |
| iphoneos Release (private identity overrides) | exit 0, BUILD SUCCEEDED | `Logs/build34-release.log` |
| IPA packaging | exit 0 | `Logs/build34-package.log` |
| SwiftUI actual widget rendering | 8 PNGs generated, light/dark × small/medium × real-public/empty | `Logs/build34-render.log` |
| Diff whitespace | `git diff --check` exit 0 | terminal output |

SwiftPM and Xcode target membership differ: 4 new public-wire tests are SwiftPM-only; 2 new App/Keychain integration tests are in the existing iOS StorageTests target. Their counts must not be conflated.

Initial compile attempts exposed a Swift type-checker complexity problem (split client expression), a synthetic test throwing the associated-value ServiceError constructor (fixed), and read-only widgetFamily in the standalone renderer (inject family only in isolated render copy). None are reported as passes. One manually entered expected public-client sum was corrected from the actual captured fixture; final suite asserts exact 210,726,752,060 tokens for pi. Final report uses final logs, not those intermediate failures.

## Render / simulator boundaries

- Actual widget source rendered with SwiftUI ImageRenderer, not HTML. Renderer copies widget source, removes its entry point, and replaces only read-only widgetFamily with an injected family in scratch; delivered sources contain no fixture hooks.
- Rerun: `python3 Scripts/render_tokensci_build34.py`.
- Images: `/Users/fangyang/.hermes/cache/scratch/codexusage-build34-render/widget-{dark,light}-{small,medium}-{public,empty}.png`.
- Vision screening of dark medium and light small found readable edge padding/no clipping or collision; this is second-hand screening, not physical WidgetKit compositor proof.
- Simulator app launches. `simulator-usage.png` proves visible three-tab order but is blocked by iOS's open-URL confirmation and still shows 状态 selected; it does NOT verify the selected usage screen. No physical tap or screenshot claim is made for that page.
- Dedicated cache-only widget chooses the first published tokens.ci profile. Multiple-profile per-instance configuration is not added.

## Independent source review

Read the inherited diff and reviewed the resulting complete source additions plus tracked diff (`Logs/build34-full-diff.patch`). Checked decoder schema against public payload, UTC semantics, timestamp fractions, cache failure ordering, provider dispatch, per-profile error ownership, model shared state, interactive vs cache widget gating, theme palette/background match, and unchanged status card code. Review follow-up made tokens.ci catalog explicitly cache-only (nil credential group), preventing an authorized dashboard intent from advertising a no-op network refresh. No unrelated service authentication implementation was changed. No commit/push performed, no blanket cleanup.

## Reproduce build

```sh
python3 Tests/widget_refresh_contract.py -v
python3 Tests/tokensci_contract.py -v
python3 Tests/build9_contract.py
python3 Tests/signing_configuration_test.py
swift test
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Debug \
  -destination 'platform=iOS Simulator,id=9A8D77A7-84AC-4338-8C55-38B418AA745C' \
  -derivedDataPath Build34Sim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO test
python3 Scripts/build34_release.py
python3 Scripts/package_widget_build34.py
```

## Remaining phone-side acceptance

Re-sign with existing identifiers and overlay-install; confirm preserved logins, real username/read-token authorization, live data after refresh, per-profile error messages, physical taps on tabs, wrapped text, widget home-screen layout/theme and shared-container availability under purchased signing. No real user credential was accessed or validated. tokens.ci widgets intentionally require opening the App to fetch updates. Existing other providers still require their signed-device authorization/network checks.
