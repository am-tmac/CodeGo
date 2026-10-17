# CodexUsage 3.1 / build 35 — usage connection sheet

## Artifact

- `/Users/fangyang/Downloads/CodexUsage-3.1-build35-tokensci-unsigned.ipa`
- 1,598,417 bytes
- SHA-256: `a14676953e295511285018fd92b61540080ae82b68ccf7c48c5862215b2986ee`
- Real iphoneos Release in `Build35Direct/Build/Products/Release-iphoneos/CodexUsage.app`; App and Widget arm64, minimum iOS 17.0, version 3.1 / 35.
- Private overlay-compatible bundle identifiers and App Group / Keychain group verified against `Configuration/Private.xcconfig` in memory, not printed. No signing identities or real user credentials were read. Build tooling reads only the private build-configuration keys required to preserve identity.
- Unsigned binaries; no provisioning profiles or `_CodeSignature`. ZIP integrity passed. Independent archive read-back compared all 10 packaged files byte-for-byte to this build's Release products and checked both plists, versions, identity, groups and expanded values. Evidence: `Logs/build35-archive-verification.json`.

## Narrow changes

The inline form was part of `TokensCIPanel` after its profile loop, so it appeared below loaded usage cards. The title bar only exposed a plus on 状态.

- `App/TokensCIPanel.swift`: display component now contains existing data cards or an empty state with a connect action; username/read-token form moved into `TokensCIConnectSheet` in the same App-only source. Existing metrics, card rendering, per-profile refresh/remove/error attribution unchanged. Sheet clears unsubmitted username/token/consent on close/disappearance/background; background also dismisses it. Submitted save requests retain their existing asynchronous service behavior.
- `App/CodexUsageApp.swift`: 用量-only plus immediately before refresh; routes directly to tokens.ci sheet. Empty-state action uses the same route. Reuses the sole `.sheet(item:)`; status provider picker and settings remain intact.
- `App/ConnectViews.swift`: explicit `.tokensCI` identifiable route, without adding tokens.ci to quota-provider picker.
- All six configurations bumped to marketing 3.1 / build35.
- New build/release scripts copied from build34, retargeted to build35; old scripts and all inherited uncommitted work preserved. README documents current build and cache behavior.
- Compared baseline copies: `Widget/CodexUsageWidget.swift`, `Shared/UsageViews.swift`, `Shared/TokensCI.swift` byte-identical to start of this task. No autonomous tokens.ci widget networking added. Its approximately 15-minute timeline request re-reads cache only; App fetch is needed for fresh usage.

## Actual execution

| Check | Actual result | Evidence |
|---|---|---|
| New navigation/form-placement contract RED, before production edits | 2 tests, 2 expected assertion failures | `Logs/build35-navigation-red.log` |
| Same contract GREEN | 2 passed | `Logs/build35-navigation-green.log` |
| Swift source parse | exit 0 | `swiftc -parse App/TokensCIPanel.swift App/ConnectViews.swift App/CodexUsageApp.swift` |
| Targeted public-wire tokens.ci SwiftPM tests | 4 passed | `Logs/build35-targeted.log` |
| Targeted App model + real fixture Keychain/cache tests | 2 passed, no skips, TEST SUCCEEDED | `Logs/build35-model-targeted.log` |
| Widget policy contracts | 19 passed | `Logs/build35-contract.log` |
| tokens.ci tab/model/widget/version contracts | 4 passed | `Logs/build35-tokensci-contract.log` |
| Widget shape contracts | 3 passed | `Logs/build35-shape.log` |
| Signing contract | passed | `Logs/build35-signing.log` |
| Final SwiftPM suite | 91 passed, 0 failures | `Logs/build35-swift.log` |
| Final ad-hoc signed Simulator Debug suite | 84 passed, 0 failures, TEST SUCCEEDED | `Logs/build35-simulator.log` |
| iphoneos Release | exit 0, BUILD SUCCEEDED | `Logs/build35-release.log` |
| Real Release packaging | exit 0 | `Logs/build35-package.log` |
| Independent archive read-back | passed, 10 files matched Release | `Logs/build35-archive-verification.json` |
| Whitespace | `git diff --check` exit 0 | terminal output |

SwiftPM and Xcode membership differ; do not combine their counts. Xcode targeted and full suites ran on private simulator `CodexUsage-build35` (`8B9CF510-9779-4545-BAA8-AAF9C5FE8EB5`) with private `Build35Sim` derived data and parallel testing disabled. These are unit/integration suites, not a UI-automation end-to-end tap test. No fixture hooks were added to production.

## Reproduce

```sh
python3 Tests/tokensci_navigation_contract.py -v
python3 Tests/widget_refresh_contract.py -v
python3 Tests/tokensci_contract.py -v
python3 Tests/build9_contract.py
python3 Tests/signing_configuration_test.py
swift test --filter TokensCI
swift test
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Debug \
  -destination 'platform=iOS Simulator,id=8B9CF510-9779-4545-BAA8-AAF9C5FE8EB5' \
  -derivedDataPath Build35Sim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO test
python3 Scripts/build35_release.py
python3 Scripts/package_widget_build35.py
```

## Review and limitations

Reviewed task-only diff against baseline copies in `Logs/build35-scoped-diff.patch`, plus new contract/build/package scripts. No cards/metrics/provider authentication changes or credential migration. No commit/push or destructive cleanup. Existing build34 files and changes remain.

The first contract draft used a missing-type split that raised an error; it was corrected to assert route/type absence before the recorded final RED (two assertion failures). One standalone archive-verification shell command had a quoting error; rerun as a scratch Python script succeeded. Neither is reported as a test pass.

Phone-side re-sign/overlay install, preserved existing login on device, physical plus/refresh tap targets and left/right placement, swipe-close/background/reopen credential field behavior, successful real save/read and cache-only home-screen widget compositor behavior remain device acceptance checks. No real account authorization/networking was exercised. Static navigation contracts and successful builds prove source placement/routing, not finger hit-testing or on-device visual layout.
