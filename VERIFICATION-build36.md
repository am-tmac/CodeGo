# CodexUsage 3.2 / build36 — aligned reported-day tokens.ci usage

## Delivered artifact

- IPA: `/Users/fangyang/Downloads/CodexUsage-3.2-build36-tokensci-unsigned.ipa`
- Bytes: 1,604,025
- SHA-256: `8aa171a0e6a3b7920b2b8f7cb28b4564ddae5a74db4b412cfadf2b8659e21e50`
- App and Widget: 3.2 (36), arm64, minimum iOS 17.0, unsigned with extension present. Private overlay identity and App Group / Keychain group compared in memory against `Configuration/Private.xcconfig`; not printed. ZIP passed; all 10 packaged files match the actual Release products byte-for-byte. Read-back evidence: `Logs/build36-archive-verification.json`.
- No installation, commit or push. No user account/token was supplied, read or needed. Synthetic tokens only in tests; public endpoint fetched without Authorization. Built binaries scanned for credential-shaped `tkr_` values (none).

## Root cause and correction

Previous implementation chose the current UTC date for left totals, then aggregated every contribution's clients/models for the right rows. At 01:17 Asia/Shanghai the new local-date regression actually returned zero instead of the fixture's current-day 120 and mixed historical 9,000 with today's 120. RED log records all five expected assertions.

`Shared/TokensCI.swift` now requests explicit supported `?period=all`, generates the date key in device current timezone and selects `contributions.date == localKey` once. Today's total and client/model sums use the same day set, including repeated same-day entries. Stale prior-day entries never become today; absent today returns zero and no client rows. Top model cost comes from that selected model, not whole client cost. Official-style source labels include Hermes Agent, Codex CLI and Claude Code; unknown IDs stay visible. Compact 万 values retain one decimal.

`App/TokensCIPanel.swift` and tokens.ci-only sections in `Widget/CodexUsageWidget.swift` retain layout and show aligned day rows. Bars are client tokens / selected-day total, clamped 0...1 (no false 4% minimum); App explains denominator. Lifetime bottom fields are labelled 累计. Existing usage plus sheet, tabs, quota/provider code and cache-only widget networking policy are preserved.

Cache adds optional selected day/timezone metadata (backward-compatible decoding). Yesterday's retained data is labelled `缓存日 YYYY-MM-DD`, not today; timezone-changed cache also gets that label. Pre-build36 caches can contain lifetime client rows: reading those suppresses only old day total/detail and labels 日数据待刷新, preserving stored bytes, lifetime data and credentials until a real successful refresh. API failures still retain exact cache bytes.

## Source evidence and timezone boundary

Inspected clean local source `https://github.com/missuo/tokens` at commit `98d3443b41b72f0f152fec56577e22fdcd87d3d1` (2026-10-15), checked by git. Relevant permanent source links:

- [Profile query and aggregation](https://github.com/missuo/tokens/blob/98d3443b41b72f0f152fec56577e22fdcd87d3d1/web/src/lib/publicProfileData.ts): lines 21–58 accept only `all`, `week`, `month` (unknown values fall back to all). No supported today/daily/timezone profile query. Week/month ranges use UTC date keys and cannot resolve a local day. All-time stats are queried separately; contributions are daily records. Lines 342–363 merge by date and retain the minimum timestamp hint.
- [CLI timezone pin](https://github.com/missuo/tokens/blob/98d3443b41b72f0f152fec56577e22fdcd87d3d1/cli/tokens-cli/src/timezone.rs): fixed top-level timezone / scanner bucketTimezone / detected system zone; pinned on submit. [Core rebucketing](https://github.com/missuo/tokens/blob/98d3443b41b72f0f152fec56577e22fdcd87d3d1/cli/tokens-core/src/lib.rs), lines 6403–6423, sets date from bucket timezone. [Aggregator](https://github.com/missuo/tokens/blob/98d3443b41b72f0f152fec56577e22fdcd87d3d1/cli/tokens-core/src/aggregator.rs) groups by message.date.
- [Schema timestamp comment](https://github.com/missuo/tokens/blob/98d3443b41b72f0f152fec56577e22fdcd87d3d1/web/src/lib/db/schema.ts), lines 293–294, calls timestampMs the earliest message in a UTC bucket; this legacy comment does not establish that newer CLI date keys are UTC. [date-utils](https://github.com/missuo/tokens/blob/98d3443b41b72f0f152fec56577e22fdcd87d3d1/web/src/lib/date-utils.ts) uses it for a display hint. **An earliest-message timestamp is not a bucket boundary or raw event stream. We do not move/split entire daily totals by it.**

Live public validation: initial Python urllib call got HTTP403; curl with browser User-Agent succeeded HTTP200, 388,075 bytes, 233 contributions, latest dates 2026-10-02/03/04 with timestampMs null. Stored public response at `/Users/fangyang/.hermes/cache/scratch/tokensci-public-build36.json`. Existing complete public fixture is replayed at its actual 2026-10-04 date and verifies daily clients sum to daily tokens/cost while lifetime stats remain unchanged. No private am-tmac request was made.

**Boundary limitation:** the current CLI's date is a pinned uploader-calendar day, not universally UTC. Matching device-local YYYY-MM-DD reproduces the same selected calendar date when uploader and phone zones agree (e.g. Asia/Shanghai). API lacks a reliable per-bucket timezone and raw intra-day events; legacy/mixed-zone/travel buckets cannot be exactly converted. App explains this next to metrics, widget title says 上报日. We do not claim to have verified the user's private 604.4万 / $1.80 values; no screenshot numbers are hardcoded.

## Recent-30-day metrics investigation

Detailed reference shows 月度预估 and 缓存命中率 based on 最近30天, but screenshot does not establish their algorithms. Searching inspected upstream source found no corresponding monthly forecast/cache-hit calculation. Therefore this release does **not** invent a monthly projection, assert the 96% equals rounded token composition, or relabel lifetime cache as 30 days. Existing month forecast stays “— / 不外推”; cache metric remains explicitly 累计缓存读取 / 总 Token (lifetime cacheRead / totalTokens). Exact Nowdex 30-day formula parity remains unverified/out of this period-correction delivery. No charts, heatmaps, expanded analytics or controls added.

## Actual execution results

| Check | Actual output | Log |
|---|---|---|
| Period UI/source contract RED | 2 tests failed as expected before implementation | `Logs/build36-period-contract-red.log` |
| Local-midnight/mixed-period Swift RED | 1 test, 5 expected assertions failed | `Logs/build36-period-red.log` |
| Legacy cache RED | 1 test failed after nonzero legacy fixture corrected | `Logs/build36-cache-red.log` |
| Focused local-day GREEN | 1 passed | `Logs/build36-period-green.log` |
| All targeted tokens.ci regressions | 7 passed, zero failures | `Logs/build36-targeted.log` |
| Period contract GREEN | 2 passed | `Logs/build36-period-contract-green.log` |
| Existing widget policy | 19 passed | `Logs/build36-contract.log` |
| tokens.ci policy/version | 4 passed | `Logs/build36-tokensci-contract.log` |
| Dedicated sheet/navigation | 2 passed | `Logs/build36-navigation.log` |
| Shape policy | 3 passed | `Logs/build36-shape.log` |
| Signing configuration | passed | `Logs/build36-signing.log` |
| Final SwiftPM | Executed 94 tests, 0 failures | `Logs/build36-swift.log` |
| Final signed Simulator Debug | Executed 84 tests, 0 failures; TEST SUCCEEDED | `Logs/build36-simulator.log` |
| iphoneos Release | BUILD SUCCEEDED, exit0 | `Logs/build36-release.log` |
| Real Release package | exit0; correct hash/version | `Logs/build36-package.log` |
| Archive read-back | 10 file matches, identity/version/groups/integrity passed | `Logs/build36-archive-verification.json` |
| Swift source parse and whitespace | exit0 | `swiftc -parse`; `git diff --check` |

SwiftPM and Xcode test memberships differ: the 7 tokens.ci parser regressions run in SwiftPM, while Xcode includes the existing real Keychain/cache failure and App-model attribution tests (84 total, no skips). Do not combine counts. Initial legacy-cache test accidentally used zero/empty current data and passed; strengthened with nonzero lifetime rows before recorded RED. New behavior coverage includes 23:59:59 → 00:00:00 Asia/Shanghai, fractional updatedAt, contradictory earliest-message timestamp, stale prior day, no today, real public aggregate-vs-row sums, model cost and retained cache failures. No full E2E UI automation claimed.

## Reproduce / remaining acceptance

```sh
python3 Tests/tokensci_period_contract.py -v
python3 Tests/tokensci_navigation_contract.py -v
python3 Tests/widget_refresh_contract.py -v
python3 Tests/tokensci_contract.py -v
python3 Tests/build9_contract.py
python3 Tests/signing_configuration_test.py
swift test --filter TokensCI
swift test
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Debug \
 -destination 'platform=iOS Simulator,id=8B9CF510-9779-4545-BAA8-AAF9C5FE8EB5' \
 -derivedDataPath Build36Sim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
 -parallel-testing-enabled NO test
python3 Scripts/build36_release.py
python3 Scripts/package_widget_build36.py
```

Release build helper passes private identity keys explicitly without printing them. All six project configurations set 3.2 / 36. Retained all inherited uncommitted build34/35 work; no cleanup or history changes. Files changed this task: Shared/TokensCI.swift, App/TokensCIPanel.swift, tokens.ci Widget sections, Tests/TokensCITests.swift, new Tests/tokensci_period_contract.py, Tests/tokensci_contract.py, Package.swift, project versions, README; new Scripts/build36_release.py and Scripts/package_widget_build36.py. Skill corrected the previously unsupported blanket UTC claim.

Physical re-sign/overlay upgrade, on-device layout and home-screen WidgetKit compositor, private live profile values and source timezone remain device acceptance checks. User must open App and refresh once to replace pre-build36 mixed-period cache; no reauthorization/migration is requested. This build was not installed.
