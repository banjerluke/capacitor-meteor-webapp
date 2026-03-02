# Test Suite Improvement Plan (iOS + Android)

## Goal
Close cross-platform test gaps between iOS and Android while preserving intended behavioral differences, improve assertion quality, and reduce flakiness/brittleness.

## Current Baseline
- iOS tests: 52
- Android tests: 50 (JVM + instrumented)
- Main asymmetry: Android has broader lifecycle/partial-download/cleanup coverage; iOS has stronger BundleOrganizer breadth and stronger manifest field assertions.

## Progress Update (2026-03-02)
- Milestone A completed.
- Implemented iOS lifecycle, partial-download, and cleanup/discovery test coverage.
- Added small iOS testability seam in `CapacitorMeteorWebApp` for deterministic lifecycle testing.
- Reduced iOS BLACKLIST log noise for empty arrays.

### Completed in Code
- Commit `fd7bceb`
  - Added:
    - `ios/Tests/CapacitorMeteorWebAppPluginTests/CapacitorMeteorWebAppLifecycleTests.swift`
    - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleManagerPartialDownloadTests.swift`
    - `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetBundleManagerCleanupTests.swift`
  - Updated:
    - `ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebApp.swift`
- Commit `3dd5ce0`
  - Updated:
    - `ios/Sources/CapacitorMeteorWebAppPlugin/WebAppConfiguration.swift`

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
- Status: Completed
- Delivered WS1.1, WS1.2, WS1.3
- Exit criteria:
  - iOS has lifecycle/partial/cleanup suites analogous to Android coverage domains (done)

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
1. PR1: iOS lifecycle tests (done)
2. PR2: iOS partial-download + cleanup/discovery tests (done)
3. PR3: iOS manifest/bundle negative-path additions (next)
4. PR4: Assertion hardening (Android + iOS dedupe/no-callback)
5. PR5: Android BundleOrganizer/AssetManifest/FileOps upgrades
6. PR6: Android partial-download policy assertion finalization

## Next Agent Start Here

### Context

This plugin is a port of a legacy Meteor/Cordova plugin (`_cordova-reference/` in the repo root) being prepared for proposal as the official Meteor Capacitor integration for both iOS and Android. The test suite must demonstrate maturity and thoroughness to earn community trust, serve as a safety net for future contributors who don't know the internals, and handle the diversity of Meteor apps in the wild.

### General Rules

1. **Test-only changes.** Do not modify production source files unless a test seam is absolutely required. If you must add a seam, keep it minimal and clearly commented.
2. **Follow existing patterns.** Each platform has established test helpers and conventions — match them exactly. Details below.
3. **Run tests after each task.** iOS: `cd ios && swift test`. Android unit: `cd android && ./gradlew test`. Android instrumented: `cd android && ./gradlew connectedAndroidTest` (if emulator available; skip if not and note it).
4. **One commit per task.** Commit after completing each numbered task below with a descriptive message.
5. **Update the tracking checklist** at the bottom of this file as you complete each item.

### iOS Test Patterns to Follow

- **Error assertions:** Use the existing `assertInvalidManifest()` helper in `AssetManifestTests.swift` which checks exception type is `.invalidAssetManifest` and reason `.contains()` a fragment. For `AssetBundle` errors, use `XCTAssertThrowsError` with a closure that casts to `WebAppError` and guard-checks the case (see `testMissingRuntimeConfigScriptThrowsUnsuitableAssetBundle` for the pattern).
- **Positive assertions:** Use `XCTAssertEqual`, `XCTAssertNil`, `XCTAssertNotNil` on parsed properties.
- **File references:** Pass `#filePath` and `#line` through custom assertion helpers.
- **Temporary directories:** Use `setUp`/`tearDown` with `FileManager.default.temporaryDirectory`.
- **Error types available:** `WebAppError.invalidAssetManifest(reason:underlyingError:)`, `WebAppError.unsuitableAssetBundle(reason:underlyingError:)` — defined in `ios/Sources/.../Utils/Errors.swift`.

### Android Test Patterns to Follow

- **Unit tests** (`android/src/test/`): Use structured error type checking via `error.getType()` enum (e.g., `assertEquals(WebAppError.Type.INVALID_ASSET_MANIFEST, error.getType())`). See `AssetManifestTest.java` `assertInvalidManifest()` helper.
- **Integration tests** (`android/src/androidTest/`): Currently use `error.getMessage().contains("keyword")` substring matching with `CountDownLatch` + `AtomicReference`. The `WebAppError.Type` enum is available at `android/src/main/java/.../WebAppError.java` with cases: `INVALID_ASSET_MANIFEST`, `FILE_SYSTEM_ERROR`, `DOWNLOAD_FAILURE`, `UNSUITABLE_ASSET_BUNDLE`, `INITIALIZATION_FAILED`, `BRIDGE_UNAVAILABLE`, `NO_PENDING_VERSION`, `NO_ROOT_URL_CONFIGURED`, `STARTUP_TIMEOUT`.
- **No-callback pattern:** Currently `assertFalse(latch.await(3, TimeUnit.SECONDS))` — this is what Task 1 will improve.

---

### Task 1: Harden Android no-callback assertions (WS3.3)

**Why:** Timeout-based "no callback" assertions (`assertFalse(latch.await(3, SECONDS))`) are flaky in CI. A late callback at 3.1s passes incorrectly. This is the highest-value reliability improvement.

**Files to modify:**
- `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/ShouldDownloadFilterTest.java`
- `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/AssetBundleManagerUpdateLifecycleTest.java`

**What to do:**
1. Introduce a small test helper (private method or inner class in the test file, not a new file) that acts as an event recorder/callback spy. It should:
   - Record whether a callback was invoked (and with what arguments)
   - Allow a "drain" step: after the action under test, perform a known-succeeding operation on the same async path to prove the queue has been flushed
   - Then assert the spy was never called
2. Replace the `assertFalse(latch.await(3, SECONDS))` pattern with the new spy-based pattern in:
   - `ShouldDownloadFilterTest`: the "should skip download" assertions (currently at ~lines 137, 195, 255)
   - `AssetBundleManagerUpdateLifecycleTest`: `sameVersionOnServer_callbackNotInvoked` test
3. Keep the existing positive-path timeout assertions (`assertTrue(latch.await(30, SECONDS))`) unchanged — those are fine.

**Acceptance criteria:**
- No-callback assertions are deterministic (not dependent on a timeout race)
- Existing passing tests still pass
- No production code changes

---

### Task 2: Replace Android string-matching error assertions with structured checks (WS3.1)

**Why:** `assertTrue(error.getMessage().contains("Hash mismatch"))` breaks on wording changes and passes if the wrong error happens to contain the keyword. The `WebAppError.Type` enum already exists but integration tests don't use it.

**File to modify:**
- `android/src/androidTest/java/com/banjerluke/capacitormeteorwebapp/AssetBundleManagerErrorHandlingTest.java`

**What to do:**
1. For every test that currently asserts on `error.getMessage().contains(...)`, add a **primary** assertion on `error.getType()` (e.g., `assertEquals(WebAppError.Type.DOWNLOAD_FAILURE, ((WebAppError) error).getType())`).
2. Keep the `.contains()` check as a **secondary** assertion (don't remove it — it still documents intent). Add a comment like `// Secondary: verify message mentions specific detail`.
3. If the error is not a `WebAppError` (e.g., a raw `IOException`), assert on the exception class with `assertInstanceOf` or `assertTrue(error instanceof ...)`.

**Tests to update (all in `AssetBundleManagerErrorHandlingTest.java`):**
- `missingAsset_callsOnError` — expect `DOWNLOAD_FAILURE`
- `invalidAssetHash_callsOnError` — expect `DOWNLOAD_FAILURE`
- `versionMismatchInIndexPage_callsOnError` — expect `UNSUITABLE_ASSET_BUNDLE`
- `missingRootUrlInIndexPage_callsOnError` — expect `UNSUITABLE_ASSET_BUNDLE`
- `rootUrlChangingToLocalhost_callsOnError` — expect `UNSUITABLE_ASSET_BUNDLE`
- `missingAppIdInIndexPage_callsOnError` — expect `UNSUITABLE_ASSET_BUNDLE`
- `wrongAppId_callsOnError` — expect `UNSUITABLE_ASSET_BUNDLE`
- `manifestDownloadFailure_callsOnError` — expect `DOWNLOAD_FAILURE`

**Verify** the expected error types by reading the production code that throws them before asserting. The types listed above are best guesses — confirm by tracing the code path.

**Acceptance criteria:**
- Every error test has a primary structured type assertion
- Existing tests still pass (type expectations are correct)
- No production code changes

---

### Task 3: Add iOS `AssetManifest` negative-path tests (WS2.1)

**Why:** The iOS manifest parser already rejects invalid format and invalid JSON, but the test file is missing explicit coverage for some rejection paths that the Android side already tests.

**File to modify:**
- `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetManifestTests.swift`

**What to do:**
1. Review the existing tests — `testThrowsOnIncompatibleFormat` and `testThrowsOnInvalidJSON` may already exist. If they do, verify they are sufficient and move on.
2. If any of these scenarios are NOT covered, add them using the `assertInvalidManifest()` helper:
   - Manifest with unrecognized `format` value (not `"web-program-pre1"`)
   - Manifest with syntactically invalid JSON (not parseable)
   - Manifest with `format` field missing entirely (if the parser rejects this — check the code first)
3. Verify the iOS negative-path set now matches the Android set in `AssetManifestTest.java`: missing version, missing compatibility version, incompatible format, invalid JSON.

**Source reference:** `ios/Sources/.../Bundle/AssetManifest.swift` — parsing starts around line 30. Format check at line 41, version check at line 46, compatibility check at line 53.

**Acceptance criteria:**
- iOS manifest negative-path coverage matches Android's core set
- Uses existing `assertInvalidManifest()` helper
- Tests pass

---

### Task 4: Clarify iOS `hash` field contract (WS2.2)

**Why:** The existing test `testParsesMissingHashAsNil` documents that `hash` is optional, but the test name/setup should be crystal clear about the contract so future contributors don't accidentally make it required.

**File to modify:**
- `ios/Tests/CapacitorMeteorWebAppPluginTests/AssetManifestTests.swift`

**What to do:**
1. Read `AssetManifest.swift` line 19: `hash` is declared as `String?` (optional). Line 71: parsed with `as? String` (nil-safe). This confirms: **hash is optional by design.**
2. Review `testParsesHashAndSourceMapFields` and `testParsesMissingHashAsNil`. Ensure:
   - `testParsesMissingHashAsNil` explicitly asserts `XCTAssertNil(entry.hash)` (it likely already does)
   - The test name clearly communicates the contract (rename if misleading)
   - Add a brief comment like `// hash is intentionally optional — assets without hashes skip cache validation`
3. Cross-check with Android: `AssetManifestTest.java` `parsesOptionalFieldsAsNull()` asserts `assertNull(entry.hash)`. Ensure iOS test mirrors this intent.

**Acceptance criteria:**
- The optional-hash contract is explicitly documented in test name + comment
- No parser behavior changes
- Test passes

---

### Task 5: Expand Android `AssetManifest` success-path assertions (WS4.2)

**Why:** Android's `parsesClientEntriesOnly` test asserts `filePath` and list size but skips `urlPath`, `fileType`, `cacheable`, `hash`, and `sourceMapUrlPath`. iOS tests are more thorough here.

**File to modify:**
- `android/src/test/java/com/banjerluke/capacitormeteorwebapp/AssetManifestTest.java`

**What to do:**
1. In `parsesClientEntriesOnly()`, add assertions for the entry fields that are currently unchecked:
   - `assertEquals("/app.js", entry.urlPath)` (or whatever the test fixture URL is)
   - `assertEquals("js", entry.fileType)` (or the fixture type)
   - `assertTrue(entry.cacheable)` (or the fixture value)
   - Assert `hash` and `sourceMapUrlPath` if present in the test fixture JSON, or `assertNull` if absent
2. Ensure the test fixture JSON includes entries with `hash` and `sourceMap` values so you can assert positive parsing (add a second entry to the fixture if needed, or create a new `parsesAllEntryFields` test).

**Acceptance criteria:**
- Android manifest success-path assertion depth matches iOS
- Tests pass

---

### Task 6: Strengthen Android `BundleOrganizer` assertions (WS4.1)

**Why:** `validateBundleDetectsTraversal` only asserts `assertFalse(errors.isEmpty())` — it doesn't check *what* error was detected. The test should verify the specific validation failure.

**File to modify:**
- `android/src/test/java/com/banjerluke/capacitormeteorwebapp/BundleOrganizerTest.java`

**What to do:**
1. In `validateBundleDetectsTraversal`, replace `assertFalse(errors.isEmpty())` with assertions on the specific error content — e.g., assert the error message mentions path traversal or the offending path.
2. If the validation returns typed error objects, assert on the type. If it returns strings, assert on the specific string content.
3. Add a positive-path test: valid bundle passes validation with an empty error list.
4. If feasible without major refactoring, add a test for URL path mapping (asset lookup by URL path returns correct file).

**Acceptance criteria:**
- Traversal test asserts specific failure reason, not just "something failed"
- Positive validation path is covered
- Tests pass

---

### Lower Priority (do if time permits)

These are lower value. Skip them if the above tasks take significant effort.

- **WS3.2:** Add explicit request-count assertions to iOS `AssetBundleManagerTests.swift` dedupe tests. The test at `testInterruptedDownload_sameVersion_reusesAssetsFromPartialDirectory` already checks `MockURLProtocol.requestedPaths` — verify this is sufficient or add counts.
- **WS4.3:** Add `FileOps` error-path tests in Android for invalid source/destination.
- **WS4.4:** Make Android partial-download cleanup policy explicit in `AssetBundleManagerPartialDownloadTest.java`.

---

## Tracking Checklist
- [x] WS1.1 iOS lifecycle suite
- [x] WS1.2 iOS partial download suite
- [x] WS1.3 iOS cleanup/discovery suite
- [x] WS2.1 iOS manifest negative-path tests
- [x] WS2.2 iOS optional-field contract clarity
- [ ] ~~WS2.3 iOS missing runtime-config-script test~~ (already exists: `testMissingRuntimeConfigScriptThrowsUnsuitableAssetBundle`)
- [ ] ~~WS2.4 iOS bundle-level query-string normalization test~~ (already exists: `testManifestURLPathWithQueryStringIsNormalizedAtBundleLevel`)
- [x] WS3.1 Structured error assertions
- [ ] WS3.2 Dedupe request-count assertions
- [x] WS3.3 Deterministic no-callback assertions
- [x] WS4.1 Android BundleOrganizer assertion depth + breadth
- [x] WS4.2 Android manifest success assertion depth
- [ ] WS4.3 Android FileOps error-path coverage
- [ ] WS4.4 Android partial cleanup policy assertion
