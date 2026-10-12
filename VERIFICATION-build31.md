# CodexUsage 2.0 / build 31 — login and widget refresh reliability

## Artifact

- Unsigned IPA: `Dist/CodexUsage-widget-build31-unsigned.ipa`
- Size: 1,398,966 bytes
- SHA-256: `2dbef4eead4b66494d23e78e14ab1adaf64fd02abe2a1ba40afdbc0547a13c1d`
- App and extension: version 2.0, build 31, minimum iOS 17.0, arm64.
- Identifiers/groups match the untracked private configuration; no signing identifiers are reproduced here.
- No embedded profiles or code signatures; use the existing phone-side signer for an overlay installation.

## Changes

1. Device-code login: while waiting for approval, a dropped connection (`URLError` other than cancel), HTTP 429 or 5xx no longer aborts sign-in; polling continues until the 15-minute deadline, doubling the interval (max 60 s) after a 429. Other statuses stay fatal. The authorization-code exchange is not retried, because the code is single-use.
2. Codex refresh: if a token rotated in the same refresh gets 401 from the usage endpoint, the 401 is surfaced instead of rotating the refresh token a second time.
3. Widget timeline: a slot whose cache is under 5 minutes old is served from cache instead of re-fetched, so the App's `reloadAllTimelines()` after its own refresh no longer duplicates every request. The in-widget refresh button is unaffected (keeps its own throttle).
4. Widget columns read only their own provider's cache, and the account catalog is read once per entry. When the timeline fetched nothing, it reuses the entry it already built.

## Executed verification

- `python3 Tests/widget_refresh_contract.py -v`: 19 passed (`Logs/build31-contract.log`).
- `python3 Tests/signing_configuration_test.py`: 1 passed. `python3 Tests/build9_contract.py`: 3 passed.
- `swift test`: 87 tests / 0 failures (`Logs/build31-swift.log`), including 5 new protocol tests (transient poll recovery, client error fatal, exchange not retried, failure classification, timeline freshness gate).
- Signed simulator suite: 82 tests / 0 failures (`Logs/build31-simulator.log`; two earlier attempts were refused by the simulator with "Busy / preflight checks" before any test ran, passed after a simulator reboot), including the new iOS-only test that a 401 right after rotation does not rotate again.
- Device Release build succeeded (`Logs/build31-release.log`); packager succeeded (`Logs/build31-package.log`) with the build 30 binary markers plus version 2.0 (31). assetutil printed its usual duplicate-class diagnostic and exited successfully.
- `git diff --check` passed.

## Reproduce

```sh
python3 Tests/widget_refresh_contract.py -v
swift test
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath Build31Sim CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
  -parallel-testing-enabled NO test
xcodebuild -project CodexUsage.xcodeproj -scheme CodexUsage -configuration Release \
  -sdk iphoneos -xcconfig Configuration/Private.xcconfig -derivedDataPath Build31Direct \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CURRENT_PROJECT_VERSION=31 build
python3 Scripts/package_widget_build31.py
```

## Phone-side acceptance still required

- Re-sign with the same identifiers and overlay-install; existing accounts remain accessible.
- Sign in a Codex account and toggle airplane mode briefly while the code page is open: sign-in still completes.
- Refresh in the App, then look at the widget: it shows the new numbers without a second network fetch.
- No real account requests were made during this build.
