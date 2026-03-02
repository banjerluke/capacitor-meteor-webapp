# Test Suite Improvement Plan (iOS + Android)

## Goal
Close cross-platform test gaps between iOS and Android while preserving intended behavioral differences, improve assertion quality, and reduce flakiness/brittleness.

## Current Baseline
- iOS tests: 43
- Android tests: 50 (JVM + instrumented)
- Main asymmetry: Android has broader lifecycle/partial-download/cleanup coverage; iOS has stronger BundleOrganizer breadth and stronger manifest field assertions.

## Guiding Principles
- Keep behavior parity where plugin behavior should match.
- Keep platform-specific tests only where platform behavior intentionally differs.
- Prefer stable assertions (typed errors/state transitions/request counts) over message substring checks.
- Prefer deterministic synchronization over timeout-only “no callback” assertions.

## Workstreams

### WS1: Close iOS parity gaps with Android lifecycle + recovery coverage (Highest Priority)

#### WS1.1 Add iOS `CapacitorMeteorWebApp` lifecycle tests
- Target source behaviors:
  - `startupDidComplete` happy path
  - pending update signaling
  - `reload` path selecting downloaded bundle
  - startup timeout rollback/retry marking
- Source references:
  - `ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebApp.swift`
- New test file:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/CapacitorMeteorWebAppLifecycleTests.swift`
- Scenario parity targets (mirror Android intent, not line-by-line):
  - Startup good clears failed states and applies expected bundle
  - Pending update emits expected state transition/event
  - Reload flips from current to pending/current-downloaded as intended
  - Startup timeout reverts and marks version for retry/blacklist flow
- Acceptance criteria:
  - All four lifecycle scenarios covered with deterministic pass/fail
  - Assertions include state/config transitions and selected bundle version

#### WS1.2 Add iOS partial download recovery tests
- Target source behaviors:
  - transition from downloading to partial-download persistence
  - reuse partial assets on resume for same/new version when hashes match
- Source references:
  - `ios/Sources/CapacitorMeteorWebAppPlugin/Downloader/AssetBundleManager.swift`
- New test file:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleManagerPartialDownloadTests.swift`
- Acceptance criteria:
  - Resume path proves reduced network fetches for reused assets
  - Partial state is either cleaned or intentionally retained (explicitly asserted)

#### WS1.3 Add iOS downloaded-bundle discovery + cleanup tests
- Target source behaviors:
  - scanning previously downloaded bundles from disk
  - cleanup APIs keeping expected versions only
- Source references:
  - `ios/Sources/CapacitorMeteorWebAppPlugin/Downloader/AssetBundleManager.swift`
- New test file:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleManagerCleanupTests.swift`
- Acceptance criteria:
  - Valid bundles are loaded; invalid/corrupt ones are skipped deterministically
  - cleanup removes only non-retained bundles

### WS2: Improve parser and bundle-level parity

#### WS2.1 Strengthen iOS `AssetManifest` negative-path coverage
- Add tests for:
  - invalid manifest format rejection
  - invalid JSON rejection
- Target files:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetManifestTests.swift`
- Acceptance criteria:
  - iOS manifest failure matrix matches Android core set for version/compat/format/JSON failures

#### WS2.2 Clarify iOS optional-field expectations (`hash` semantics)
- Update/replace misleading optional-field test to explicitly validate intended contract:
  - If `hash` is required: test fails on missing hash
  - If `hash` is optional: parser and tests updated consistently (future code change)
- Target files:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetManifestTests.swift`
- Acceptance criteria:
  - Test name and setup align with actual parser contract

#### WS2.3 Add iOS `AssetBundle` missing runtime config script failure test
- Add explicit negative test for missing runtime config script in `index.html`
- Target files:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleTests.swift`
- Acceptance criteria:
  - Failure path covered and asserts typed/structured failure details

#### WS2.4 Add iOS bundle-level query-string normalization coverage
- Add `AssetBundle` test proving lookup/parsing strips query strings at bundle level (not only utility helper)
- Target files:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleTests.swift`
- Acceptance criteria:
  - URL with query resolves to correct manifest asset entry

### WS3: Improve assertion quality and reduce brittleness on both platforms

#### WS3.1 Replace string-substring error assertions with structured checks (Android first)
- Current issue: many Android error tests assert message snippets only
- Plan:
  - Assert error codes/types/enums and related metadata fields
  - Keep message assertion only as secondary sanity check where needed
- Target files:
  - `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/AssetBundleManagerErrorHandlingTest.java`
  - iOS error tests where applicable for consistency
- Acceptance criteria:
  - Primary assertions are resilient to wording changes

#### WS3.2 Strengthen in-flight dedupe assertions (both platforms)
- Current issue: iOS dedupe verifies outcome but not request-count dedupe
- Plan:
  - Add explicit network request counting assertions for manifest/index/assets
  - Verify only one active fetch sequence per version
- Target files:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleManagerTests.swift`
  - `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/AssetBundleManagerUpdateLifecycleTest.java`
- Acceptance criteria:
  - Dedupe is proven by request counts, not just completion

#### WS3.3 Replace timeout-only “no callback” checks with deterministic synchronization
- Current issue: `await(timeout)==false` style can miss late callbacks
- Plan:
  - Introduce event recorder / callback spy with explicit post-condition barriers
  - Ensure no callback during action window and after controlled drain point
- Target files:
  - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleManagerTests.swift`
  - `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/ShouldDownloadFilterTest.java`
  - `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/AssetBundleManagerUpdateLifecycleTest.java`
- Acceptance criteria:
  - No-callback assertions remain stable under repeated runs

### WS4: Fill Android weak spots and align with stronger iOS patterns

#### WS4.1 Strengthen Android `BundleOrganizer` traversal assertions
- Current issue: checks non-empty error list only
- Plan:
  - Assert specific validation result/error type for traversal attempts
  - Add coverage for target URL mapping and inherited assets (parity with iOS breadth)
- Target files:
  - `android/src/test/java/com/banjerluke/capacitormeteorwebapp/BundleOrganizerTest.java`
- Acceptance criteria:
  - Traversal tests validate exact reason, not generic failure
  - Mapping/inheritance behavior verified

#### WS4.2 Expand Android `AssetManifest` success assertions
- Add explicit positive assertions for parsed `hash` and `sourceMapUrlPath`
- Target files:
  - `android/src/test/java/com/banjerluke/capacitormeteorwebapp/AssetManifestTest.java`
- Acceptance criteria:
  - Android manifest success-path assertion depth matches iOS

#### WS4.3 Add Android `FileOps` error-path tests
- Add failures for invalid source/destination, permission-like constraints (where feasible in test env), and partial move failures
- Target files:
  - `android/src/test/java/com/banjerluke/capacitormeteorwebapp/FileOpsTest.java`
- Acceptance criteria:
  - Failure behavior is explicit and deterministic

#### WS4.4 Make Android partial-download cleanup expectation explicit
- Current issue: cleanup behavior left intentionally unspecified in test comments
- Plan:
  - Define expected policy (retain vs cleanup partial artifacts)
  - Assert policy explicitly
- Target files:
  - `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/AssetBundleManagerPartialDownloadTest.java`
- Acceptance criteria:
  - Test documents and enforces desired policy

## Cross-Platform Consistency Matrix (Target End State)
- Lifecycle coverage: parity (iOS added)
- Partial download recovery: parity (iOS added, Android clarified)
- Bundle cleanup/discovery: parity (iOS added, Android keeps coverage)
- Manifest negative matrix: parity (iOS expanded)
- Manifest positive field assertions: parity (Android expanded)
- Bundle organizer breadth: parity (Android expanded)
- Error assertion style: parity (structured assertions on both)
- No-callback determinism: parity (both hardened)

## Recommended Execution Order
1. WS1 (iOS parity closure)
2. WS2 (iOS parser/bundle gaps)
3. WS3 (assertion hardening across platforms)
4. WS4 (Android spot improvements)

## Milestone Plan

### Milestone A: iOS parity closure
- Deliver WS1.1, WS1.2, WS1.3
- Exit criteria:
  - iOS has lifecycle/partial/cleanup suites analogous to Android coverage domains

### Milestone B: Parser and bundle parity
- Deliver WS2.1, WS2.2, WS2.3, WS2.4
- Exit criteria:
  - iOS `AssetManifest` and `AssetBundle` paths have full positive/negative coverage parity with Android intent

### Milestone C: Assertion quality hardening
- Deliver WS3.1, WS3.2, WS3.3
- Exit criteria:
  - Reduced flaky timeout-based checks
  - Reduced brittle message-matching assertions

### Milestone D: Android parity uplift
- Deliver WS4.1, WS4.2, WS4.3, WS4.4
- Exit criteria:
  - Android quality aligns with strongest iOS testing patterns

## Definition of Done (Overall)
- Both platforms include equivalent coverage for shared behavior domains.
- Platform-specific behavior remains explicitly documented in test names/comments.
- New/updated tests are deterministic under repeated local/CI runs.
- No remaining known “blind spots” from the prior review findings list.

## Risk and Mitigation
- Risk: asynchronous tests remain flaky.
  - Mitigation: introduce deterministic callbacks/event recorders and controlled synchronization points.
- Risk: intended platform differences become over-normalized.
  - Mitigation: tag tests as parity-required vs platform-specific.
- Risk: refactors required for testability.
  - Mitigation: keep production changes minimal and localized; add test seams only where necessary.

## Suggested PR Breakdown
1. PR1: iOS lifecycle tests
2. PR2: iOS partial-download + cleanup/discovery tests
3. PR3: iOS manifest/bundle negative-path additions
4. PR4: Assertion hardening (Android + iOS dedupe/no-callback)
5. PR5: Android BundleOrganizer/AssetManifest/FileOps upgrades
6. PR6: Android partial-download policy assertion finalization

## Tracking Checklist
- [ ] WS1.1 iOS lifecycle suite
- [ ] WS1.2 iOS partial download suite
- [ ] WS1.3 iOS cleanup/discovery suite
- [ ] WS2.1 iOS manifest negative-path tests
- [ ] WS2.2 iOS optional-field contract clarity
- [ ] WS2.3 iOS missing runtime-config-script test
- [ ] WS2.4 iOS bundle-level query-string normalization test
- [ ] WS3.1 Structured error assertions
- [ ] WS3.2 Dedupe request-count assertions
- [ ] WS3.3 Deterministic no-callback assertions
- [ ] WS4.1 Android BundleOrganizer assertion depth + breadth
- [ ] WS4.2 Android manifest success assertion depth
- [ ] WS4.3 Android FileOps error-path coverage
- [ ] WS4.4 Android partial cleanup policy assertion
