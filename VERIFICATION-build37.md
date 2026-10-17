# CodexUsage 4.0 (37) — tokens.ci analytics

## Delivered artifact

- `/Users/fangyang/Downloads/CodexUsage-4.0-build37-tokensci-unsigned.ipa`
- 1,795,964 bytes
- SHA-256 `b00c5b81d55dc730dc8e0533d65f208604b60e5839d7eeca7838ef57852d7810`
- App and embedded Widget: 4.0 / 37, minimum iOS 17.0, arm64, unsigned, no provisioning profile/signature. Private bundle/group settings compared in memory against `Configuration/Private.xcconfig`, not printed. ZIP integrity and all 10 packaged files match actual Release products byte-for-byte. Evidence: `Logs/build37-archive-verification.json`, `Logs/build37-package.log`.
- No commit/push, REA install, real token retrieval, private-profile request or physical phone installation. Existing uncommitted build34–36 changes retained.

## Implemented

`App/TokensCIAnalyticsView.swift` follows approved section order: identity and large total/cost/time selector; daily activity/selected reported day/client details; four tiles; daily native stacked Charts with Token/cost and 7/30/90-day menus; Provider top three/show-all and model top five/show-all; composition; annual weekday and peak-day habits. Existing three tabs, quota/settings, dedicated plus sheet, per-account error/refresh/remove remain. Initial avatar matches approved initial-based preview; no brand art copied.

Lifetime uses source stats. Period analytics use real contributions, not fixtures or screenshot values. Recent windows end at explicitly labelled latest reported date, never described as today. Daily selected totals remain source totals, while bars/client shares are explicitly client-detail sums; disagreement is disclosed. Duplicate dates merge; missing dates stay missing; invalid dates skipped; zero differs from absent. Gregorian date keys preserve leap dates and do not shift source buckets using timestampMs. Existing build36 device-calendar today behavior and uploader timezone disclosure remain.

`Shared/TokensCIHistory.swift` retains contributions, model maps and five distinct token categories. Forecast stays unavailable; messages only display when reported total agrees with all client counts. Cache-read ratio = cacheRead / five-category sum, labelled not request hit rate. Histories write atomically with data protection to App-private Application Support; usernames use URL-safe base64 paths. Shared snapshot strips history. Missing/invalid history decodes independently and does not invalidate the quota snapshot; old caches without history display refresh guidance. Widget extension refuses private history access.

Widget/*.swift and Shared/UsageViews.swift SHA-256 match pre-task build36 baseline exactly (`Logs/build37-widget-baseline.json`). Shared model additions are backward-compatible. `otool -L` proves Charts linked in App and not Widget.

## Actual tests/builds

| Check | Result | Log |
|---|---|---|
| Analytics fail-first | Missing history APIs caused expected compile RED | `Logs/build37-analytics-red.log` |
| Focused analytics initial GREEN | 3 passed | `Logs/build37-analytics-green.log` |
| TokensCI targeted final | 11 passed | `Logs/build37-targeted-green.log` |
| Widget policy | 19 passed | `Logs/build37-widget_refresh_contract.log` |
| tokens.ci version/policy | 4 passed | `Logs/build37-tokensci_contract-green.log` |
| Navigation | 2 passed | `Logs/build37-tokensci_navigation_contract.log` |
| Day semantics | 2 passed | `Logs/build37-tokensci_period_contract.log` |
| Analytics/privacy/membership | 3 passed | `Logs/build37-legend-green.log` |
| Widget shapes | 3 passed | `Logs/build37-build9_contract.log` |
| Signing policy | passed | `Logs/build37-signing_configuration_test.log` |
| Final SwiftPM suite | 98 tests, 0 failures | `Logs/build37-swift.log` |
| Ad-hoc signed Simulator Debug | 84 tests, 0 failures; TEST SUCCEEDED | `Logs/build37-simulator.log` |
| Final production Debug after legend-only review fix | BUILD SUCCEEDED | `Logs/build37-final-debug.log` |
| Final private-ID iphoneos Release | BUILD SUCCEEDED | `Logs/build37-release.log` |
| Final package/archive | passed | `Logs/build37-package.log`, `Logs/build37-archive-verification.json` |

SwiftPM and Xcode compile different test memberships; analytics/parser tests are SwiftPM, storage/keychain/App-model tests are Xcode. Counts are not combined. Final full suites ran once; later chart-legend layout fix got focused RED/GREEN plus real final Debug/Release, not another full suite. Initial new isolation test compared URL directory flag rather than standardized path; corrected test assertion. Initial version contract expected six configurations; project+targets now have eight explicit entries, all 4.0/37; updated contract accordingly.

New calculation regressions cover missing day, duplicate date, leap day/invalid date, streak gap, NaN/infinity/negative rejection, source totals vs client sums, synthetic model exclusion, missing forecast/messages, complete real public fixture, legacy missing history, malformed history entries, private path and no-history shared encoding. Existing midnight/no-stale-today tests pass. Public fixture yields 30-day 225540807855 tokens / 63482.6795 cost, 30 active days and 153-day streak; these are test expectations, not production constants.

## Actual UI render evidence

- Approved reference: `/Users/fangyang/.hermes/cache/scratch/tokensci-usage-redesign/usage-{dark,light}-board.png` and eight individual section PNGs, HTML/CSS and data provenance reviewed.
- Actual simulator captures: `/Users/fangyang/Projects/CodexUsage/Build37Screenshots/`.
- Exactly 18 final captures, 18 distinct SHA-256 hashes recorded in `Build37Screenshots/manifest.json`: dark/light × overview, activity, analytics, chart, rankings, composition, habits, expanded, range7cost.
- Reproduce isolated copy: `python3 Scripts/render_tokensci_build37.py`; simulator-only project is `Build37Preview`, build outputs `Build37PreviewDerived`; capture with `python3 Scripts/capture_tokensci_build37.py`. Copy embeds only complete public fixture and never reads a token/network. Delivered source and Release binary contain no fixture account or PREVIEW_SECTION hook.
- Image inspection: 20pt outer inset, 60pt initial avatar, dominant ~57pt total, gradient, 25pt grouped cards, heatmap and four tiles match approved structural geometry. Provider percentages/model fees and annual Thursday/peak-day results agree with preview calculations. Chart legend initially overflowed; fixed to top three + Other and bounded 2×2 legend, confirmed in final dark-chart image. Final light-range7cost image shows seven bars, Cost selected and dollar axis. Expanded image shows eight clients.
- Capture startup initially too early, producing blanks; optimized repeated date formatting/chart aggregation and waited for real rendering, then recaptured all 18. Final manifest replaces rejected captures.
- These are isolated renders of production analytics with public data, not evidence of private live retrieval or physical touch. Preview shell has one Usage tab and example labels; production retains original three-tab shell unchanged. Native floating tab scroll-edge treatment overlaps content passing underneath but final footer is reachable; no claim of pixel-perfect full-shell parity. Small heatmap cells have date-labelled accessibility actions; physical finger targeting at that density is not verified. Expanded/range states were seeded in the isolated harness, not asserted as automated finger-tap E2E.

## Review and remaining boundary

Reviewed full tracked diff plus new TokensCI source, private persistence, source memberships, packager and preview scripts; preserved inherited quota changes rather than restoring git HEAD. No private IDs added to source, fixture hooks absent from production; credential-shaped binary scan passed. Model-specific fees remain model fees; no percentile/quota-derived token analytics. No blocking build/archive failure remains.

Physical phone re-sign/overlay upgrade, widget compositor/refresh, actual private profile values/timezone alignment, dense heatmap touch targeting, large text layout and all controls via physical touch remain user acceptance. Old snapshots need a real refresh to fetch history, not reauthorization. API supplies no reliable per-bucket timezone or exact forecast formula; report keeps those unavailable/qualified. Sparse reporting cannot establish complete bills or true uninterrupted activity outside observed records.
