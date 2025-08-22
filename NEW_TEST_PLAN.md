# New Swift Testing Plan for Capacitor Meteor WebApp Plugin

## Overview

This plan recreates the 50 Cordova plugin tests (`tests/cordova_tests.js`) adapted for the new Capacitor plugin architecture. The key architectural differences are:

- **No embedded web server**: Uses Capacitor's `setServerBasePath()` instead
- **Bundle organization**: Replaces in-memory serving with directory-based serving
- **Directory-based serving**: Replaces HTTP server endpoints
- **Native Swift logic**: Replaces JavaScript coordination

Note that the plugin has been tested and basic functionality is working in a real Capacitor app, so keep that in mind if you have failures for tests you've written.

## Test Structure Mapping

### 1. Basic Server Functionality Tests

**Old Test Group**: "the local server" (lines 7-55)

| Old Test                                                                                           | Line  | New Swift Test                               | Description                                         | Status                                        |
| -------------------------------------------------------------------------------------------------- | ----- | -------------------------------------------- | --------------------------------------------------- | --------------------------------------------- |
| "should serve index.html for /"                                                                    | 8-10  | `testServeIndexForRoot()`                    | Test that root path serves index.html via Capacitor | ✅ **Done**                                   |
| "should serve assets based on the URL in the manifest"                                             | 12-21 | `testServeManifestAssets()`                  | Test manifest-based asset serving                   | ✅ **Done** (`testAssetBundleAssetsAccess()`) |
| "should serve assets from the bundled www directory"                                               | 23-31 | `testServeBundledAssets()`                   | Test serving from bundle directory                  | ✅ **Done**                                   |
| "should serve index.html for any URL that does not correspond to an asset"                         | 33-35 | `testServeIndexForNonAssets()`               | Test fallback to index.html                         | ✅ **Done**                                   |
| "should serve index.html when accessing an asset through /application"                             | 37-39 | `testServeIndexForApplicationPath()`         | Test /application path handling                     | ✅ **Done**                                   |
| "should serve index.html for an asset that is not in the manifest"                                 | 41-43 | `testServeIndexForMissingManifestAsset()`    | Test missing manifest asset handling                | ✅ **Done** (`testMissingAssetFallback()`)    |
| "should serve index.html when accessing an asset that is not in the manifest through /application" | 45-47 | `testServeIndexForMissingApplicationAsset()` | Test missing /application asset                     | ✅ **Done** (`testMissingAssetFallback()`)    |
| "should not serve index.html for a non-existing /favicon.ico"                                      | 49-54 | `testReturn404ForMissingFavicon()`           | Test 404 for missing favicon                        | ✅ **Done** (`testFaviconAssetHandling()`)    |

### 2. Update Tests - Bundled to Downloaded

**Old Test Group**: "when updating from the bundled app version to a downloaded version" (lines 57-112)

| Old Test                                                | Line    | New Swift Test                      | Description                         |
| ------------------------------------------------------- | ------- | ----------------------------------- | ----------------------------------- |
| "should only serve the new version after a page reload" | 66-76   | `testServeNewVersionAfterReload()`  | Test version switching after reload |
| "should only download changed files"                    | 78-91   | `testDownloadOnlyChangedFiles()`    | Test selective file downloading     |
| "should still serve assets that haven't changed"        | 93-101  | `testServeUnchangedAssets()`        | Test unchanged asset serving        |
| "should remember the new version after a restart"       | 103-111 | `testRememberVersionAfterRestart()` | Test version persistence            |

### 3. Update Tests - Downloaded to Downloaded

**Old Test Group**: "when updating from a downloaded app version to another downloaded version" (lines 114-190)

| Old Test                                                | Line    | New Swift Test                                         | Description                                      |
| ------------------------------------------------------- | ------- | ------------------------------------------------------ | ------------------------------------------------ |
| "should only serve the new verson after a page reload"  | 125-135 | `testServeNewerDownloadedVersionAfterReload()`         | Test downloaded-to-downloaded version switching  |
| "should only download changed files"                    | 137-149 | `testDownloadOnlyChangedFilesDownloadedToDownloaded()` | Test selective download between versions         |
| "should still serve assets that haven't changed"        | 151-159 | `testServeUnchangedAssetsDownloadedToDownloaded()`     | Test unchanged assets between downloads          |
| "should delete the old version after startup completes" | 161-179 | `testDeleteOldVersionAfterStartup()`                   | Test cleanup of old versions                     |
| "should remember the new version after a restart"       | 181-189 | `testRememberNewerVersionAfterRestart()`               | Test version persistence for downloaded versions |

### 4. Update Tests - Downloaded to Bundled

**Old Test Group**: "when updating from a downloaded app version to the bundled version" (lines 192-275)

| Old Test                                                | Line    | New Swift Test                                       | Description                                 |
| ------------------------------------------------------- | ------- | ---------------------------------------------------- | ------------------------------------------- |
| "should only serve the new verson after a page reload"  | 203-213 | `testServeReversionToBundledAfterReload()`           | Test reverting to bundled version           |
| "should only download the manifest"                     | 215-223 | `testDownloadOnlyManifestForBundledReversion()`      | Test minimal download for bundled reversion |
| "should still serve assets that haven't changed"        | 225-233 | `testServeUnchangedAssetsForBundledReversion()`      | Test asset serving during reversion         |
| "should not redownload the bundled version"             | 235-244 | `testNotRedownloadBundledVersion()`                  | Test bundled version not re-downloaded      |
| "should delete the old version after startup completes" | 246-264 | `testDeleteDownloadedVersionAfterBundledReversion()` | Test cleanup when reverting to bundled      |
| "should remember the new version after a restart"       | 266-274 | `testRememberBundledVersionAfterRestart()`           | Test bundled version persistence            |

### 5. No Update Tests

**Old Test Group**: "when checking for updates while there is no new version" (lines 277-309)

| Old Test                                                | Line    | New Swift Test                            | Description                          |
| ------------------------------------------------------- | ------- | ----------------------------------------- | ------------------------------------ |
| "should not invoke the onNewVersionReady callback"      | 288-298 | `testNoCallbackForNoNewVersion()`         | Test no callback when no updates     |
| "should not download any files except for the manifest" | 300-308 | `testDownloadOnlyManifestWhenNoUpdates()` | Test minimal traffic when no updates |

### 6. Error Handling Tests

**Old Test Groups**: Various error scenarios (lines 311-591)

| Old Test                                                                     | Line    | New Swift Test                                          | Description                                    |
| ---------------------------------------------------------------------------- | ------- | ------------------------------------------------------- | ---------------------------------------------- |
| "should invoke the onError callback with an error" (missing asset)           | 321-327 | `testErrorCallbackForMissingAsset()`                    | Test error handling for 404 assets             |
| "should not invoke the onNewVersionReady callback" (missing asset)           | 329-339 | `testNoReadyCallbackForMissingAsset()`                  | Test no ready callback on asset error          |
| "should invoke the onError callback with an error" (invalid asset)           | 352-358 | `testErrorCallbackForInvalidAsset()`                    | Test error handling for hash mismatch          |
| "should not invoke the onNewVersionReady callback" (invalid asset)           | 360-370 | `testNoReadyCallbackForInvalidAsset()`                  | Test no ready callback on hash error           |
| "should invoke the onError callback with an error" (version mismatch)        | 383-389 | `testErrorCallbackForVersionMismatch()`                 | Test error for version mismatch                |
| "should not invoke the onNewVersionReady callback" (version mismatch)        | 391-401 | `testNoReadyCallbackForVersionMismatch()`               | Test no ready callback on version error        |
| "should invoke the onError callback with an error" (missing ROOT_URL)        | 414-420 | `testErrorCallbackForMissingRootURL()`                  | Test error for missing ROOT_URL                |
| "should not invoke the onNewVersionReady callback" (missing ROOT_URL)        | 422-432 | `testNoReadyCallbackForMissingRootURL()`                | Test no ready callback for ROOT_URL error      |
| "should invoke the onError callback with an error" (wrong ROOT_URL)          | 447-453 | `testErrorCallbackForWrongRootURL()`                    | Test error for incorrect ROOT_URL              |
| "should not invoke the onNewVersionReady callback" (wrong ROOT_URL)          | 455-465 | `testNoReadyCallbackForWrongRootURL()`                  | Test no ready callback for ROOT_URL error      |
| "should invoke the onError callback with an error" (missing appId)           | 478-484 | `testErrorCallbackForMissingAppId()`                    | Test error for missing appId                   |
| "should not invoke the onNewVersionReady callback" (missing appId)           | 486-496 | `testNoReadyCallbackForMissingAppId()`                  | Test no ready callback for appId error         |
| "should invoke the onError callback with an error" (wrong appId)             | 509-515 | `testErrorCallbackForWrongAppId()`                      | Test error for incorrect appId                 |
| "should not invoke the onNewVersionReady callback" (wrong appId)             | 517-527 | `testNoReadyCallbackForWrongAppId()`                    | Test no ready callback for appId error         |
| "should invoke the onError callback with an error" (missing compatibility)   | 540-546 | `testErrorCallbackForMissingCompatibilityVersion()`     | Test error for missing cordova compatibility   |
| "should not invoke the onNewVersionReady callback" (missing compatibility)   | 548-558 | `testNoReadyCallbackForMissingCompatibilityVersion()`   | Test no ready callback for compatibility error |
| "should invoke the onError callback with an error" (different compatibility) | 571-577 | `testErrorCallbackForDifferentCompatibilityVersion()`   | Test error for different cordova compatibility |
| "should not invoke the onNewVersionReady callback" (different compatibility) | 580-590 | `testNoReadyCallbackForDifferentCompatibilityVersion()` | Test no ready callback for compatibility error |

### 7. Partial Download Tests

**Old Test Groups**: Partial download scenarios (lines 593-674)

| Old Test                                                                                                       | Line    | New Swift Test                                    | Description                                  |
| -------------------------------------------------------------------------------------------------------------- | ------- | ------------------------------------------------- | -------------------------------------------- |
| "should only download the manifest, the index page, and the remaining assets" (same version)                   | 607-614 | `testResumePartialDownloadSameVersion()`          | Test resuming partial download               |
| "should only serve the new verson after a page reload" (same version)                                          | 616-622 | `testServeAfterResumedDownload()`                 | Test serving after resumed download          |
| "should serve assets that have been downloaded before" (same version)                                          | 624-628 | `testServePartiallyDownloadedAssets()`            | Test serving partially downloaded assets     |
| "should only download the manifest, the index page, and both remaining and changed assets" (different version) | 645-653 | `testResumePartialDownloadDifferentVersion()`     | Test resuming with different version         |
| "should only serve the new verson after a page reload" (different version)                                     | 655-661 | `testServeAfterResumedDownloadDifferentVersion()` | Test serving after resumed different version |
| "should serve assets that have been downloaded before" (different version)                                     | 663-667 | `testServePartialAssetsForDifferentVersion()`     | Test partial assets for different version    |
| "should serve changed assets even if they have been downloaded before"                                         | 669-673 | `testServeChangedAssetsAfterPartialDownload()`    | Test changed assets after partial download   |

## Implementation Strategy

### Phase 1: Test Infrastructure

1. **Mock Remote Server**: Create `MockMeteorServerProtocol` using URLProtocol to intercept network requests and serve fixture data
2. **Test Fixtures**: Use existing fixture data from `tests/fixtures/`
3. **Capacitor Integration**: Set up mock Capacitor environment for testing
4. **Async Testing**: Implement proper async testing patterns for Swift

### Phase 2: Core Tests (Basic Server Functionality)

- Implement tests 1-8 from the basic server functionality group
- Focus on directory-based serving instead of HTTP endpoints
- Test Capacitor's `setServerBasePath()` integration

### Phase 3: Update Mechanism Tests - **IMPLEMENTED ✅**

- ✅ Implemented version update tests (groups 2-4)
- ✅ Test bundle organization and file management
- ✅ Version persistence and cleanup (structure implemented, some tests need refinement)

### Phase 4: Error Handling & Edge Cases

- Implement error handling tests (group 6)
- Test partial download scenarios (group 7)
- Ensure proper callback behavior

## Test Files Organization

```
tests/swift/
├── CapacitorMeteorWebAppTests/
│   ├── BasicServingTests.swift           # Tests 1-8: Basic serving functionality
│   ├── VersionUpdateTests.swift          # Tests 9-26: Version update scenarios
│   ├── ErrorHandlingTests.swift          # Tests 27-42: Error scenarios
│   ├── PartialDownloadTests.swift        # Tests 43-49: Partial download scenarios
│   └── TestHelpers/
│       ├── MockMeteorServerProtocol.swift # URLProtocol-based mock server
│       ├── TestFixtures.swift            # Fixture loading utilities
│       └── AsyncTestHelpers.swift        # Async testing utilities
```

## Key Architectural Adaptations

1. **HTTP Server → Directory Serving**: Replace fetch() calls with file system operations
2. **JavaScript Callbacks → Swift Delegates**: Convert callback-based testing to delegate patterns
3. **Mock Remote Server → URLProtocol Mocking**: Use URLProtocol to intercept network requests and serve fixture data without actual HTTP server
4. **Version Management → Bundle Management**: Test bundle copying and organization instead of in-memory serving

## Critical Architecture Insight ⚡

**The plugin works by:**

1. **Organizing assets** into a serving directory based on their URL paths
2. **Using Capacitor's `setServerBasePath()`** to serve from that directory
3. **Handling non-asset routes** by serving index.html (typical SPA behavior)

**For testing, this means:**

- Tests should verify the **logical behavior** of asset resolution, not actual HTTP serving
- Unit tests focus on AssetBundle API (URL path → asset mapping)
- Integration behavior is handled by Capacitor's built-in server
- Bundle organization and switching logic is the core functionality to test

## Success Criteria

- [ ] All 50 original test scenarios covered
- [ ] Test execution time under 30 seconds
- [ ] 100% code coverage of plugin functionality
- [x] Integration with XCTest framework
- [ ] Automated CI/CD integration capability
- [ ] Clear documentation for test maintenance

## Implementation Progress

**Phase 1: Test Infrastructure** - **COMPLETE ✅**

- ✅ `MockMeteorServerProtocol` using URLProtocol to intercept network requests
- ✅ `TestFixtures` for creating mock bundle structures with proper `program.json` manifests
- ✅ `MockCapacitorBridge` implementing the `CapacitorBridge` protocol
- ✅ `AsyncTestHelpers` with comprehensive async testing utilities

**Phase 2: Core Tests (Basic Server Functionality)** - **COMPLETE ✅**

- ✅ 12 foundational tests implemented and passing
- ✅ ALL 8 original cordova test requirements fully implemented
- ✅ Tests properly target AssetBundle API (the correct layer for Capacitor architecture)
- ✅ All missing basic server functionality tests now implemented

**Phase 3: Update Mechanism Tests** - **IMPLEMENTED ✅**

- ✅ 17 version update tests implemented covering all major scenarios
- ✅ Bundled to Downloaded update tests (4 tests)
- ✅ Downloaded to Downloaded update tests (5 tests)
- ✅ Downloaded to Bundled update tests (6 tests)
- ✅ No Update tests (2 tests)
- ✅ Mock architecture created for testing complex update scenarios
- ⚠️ Some tests require additional mock implementation for full functionality

**Implemented Tests:**

1. `testInitializeWithMockBridge()` - Plugin initialization ✅
2. `testAssetBundleCreationFromDirectory()` - Bundle creation ✅
3. `testAssetBundleAssetsAccess()` - Asset access ✅
4. `testAssetContentLoading()` - Content loading ✅
5. `testAssetExistsInBundle()` - Asset existence ✅
6. `testMissingAssetFallback()` - Missing asset handling ✅
7. `testFaviconAssetHandling()` - Favicon handling ✅
8. `testBridgeIntegration()` - Capacitor bridge integration ✅
9. `testServeIndexForRoot()` - Root path serving index.html ✅
10. `testServeBundledAssets()` - Bundled asset serving ✅
11. `testServeIndexForNonAssets()` - SPA fallback behavior ✅
12. `testServeIndexForApplicationPath()` - Application path handling ✅

**Key Achievement:** All tests pass with `swift test` ✅

**Phase 2 Key Insights:**

- Tests correctly verify **logical asset resolution** behavior (URL path → asset mapping)
- AssetBundle API is the right testing layer for Capacitor architecture
- SPA behavior (non-asset routes fallback to index.html) properly tested via nil returns
- Foundation ready for complex update mechanism testing in Phase 3

### 📋 Next Steps: Phase 4 (Error Handling & Edge Cases)

Phase 3 is now implemented! The foundation is solid for implementing the remaining test phases:

- Error handling tests for missing assets, invalid assets, version mismatches
- Network error scenarios and callback verification  
- Partial download resumption logic
- Edge case handling for various failure modes

## Implementation Findings from Phase 1 & 2

### Actual Plugin Architecture (Critical for Phase 3+)

The plugin uses a layered architecture that differs slightly from initial assumptions:

**Core Classes:**

- `CapacitorMeteorWebApp`: Main business logic class
- `CapacitorMeteorWebAppPlugin`: Capacitor bridge/plugin wrapper
- `AssetBundleManager`: Handles download logic and lifecycle
- `AssetBundle`: Represents individual asset bundles
- `AssetManifest`: Parses and validates manifest files
- `BundleOrganizer`: Manages bundle directory structure
- `WebAppConfiguration`: Persistent configuration storage

**Key Protocols:**

- `CapacitorBridge`: Interface for Capacitor integration (needs mocking)
- `AssetBundleManagerDelegate`: Delegate pattern for update callbacks

**Directory Structure:**

```
ios/Sources/CapacitorMeteorWebAppPlugin/
├── Bundle/                      # Asset bundle management
│   ├── Asset.swift
│   ├── AssetBundle.swift
│   ├── AssetManifest.swift
│   └── BundleOrganizer.swift
├── Downloader/                  # Network and download logic
│   ├── AssetBundleDownloader.swift
│   └── AssetBundleManager.swift
├── Utils/                       # Utility classes
├── CapacitorMeteorWebApp.swift  # Core business logic
├── CapacitorMeteorWebAppPlugin.swift # Capacitor bridge
└── WebAppConfiguration.swift    # Configuration management
```

### Testing Infrastructure Insights

**Mock Strategy:**

- `MockMeteorServerProtocol` uses URLProtocol to intercept network requests
- `MockCapacitorBridge` implements the CapacitorBridge protocol
- Test fixtures support bundled and downloadable versions

**Key Dependencies for Phase 3+:**

1. **AssetBundleManager**: Must be mocked for update tests - handles delegate callbacks
2. **BundleOrganizer**: Critical for version switching logic
3. **WebAppConfiguration**: Needs persistence testing
4. **DispatchQueue**: Bundle switching uses serial queue `bundleSwitchQueue`

**Async Patterns:**

- Plugin uses completion handlers and delegate patterns extensively
- Bundle switching is queued to prevent race conditions
- Startup timer logic (30s timeout) needs careful testing

### Critical Test Adaptations Required

**For Version Update Tests (Phase 3):**

1. Must test `AssetBundleManagerDelegate` callbacks:
   - `didStartDownloading(bundleVersion:)`
   - `didFinishDownloading(bundle:, error:)`
   - `didStartValidating(bundle:)`
   - `didFinishValidating(bundle:, error:)`

2. Bundle switching logic requires testing:
   - `currentAssetBundle` vs `pendingAssetBundle` states
   - Serial queue execution via `bundleSwitchQueue`
   - Capacitor `setServerBasePath()` calls

3. Configuration persistence testing:
   - `WebAppConfiguration` save/load operations
   - Version tracking and rollback logic

**Mock Dependencies Needed:**

```swift
// Required for Phase 3+
class MockAssetBundleManager: AssetBundleManager
class MockBundleOrganizer: BundleOrganizer
class MockWebAppConfiguration: WebAppConfiguration
```

### Test Execution Notes

- Tests require iOS 13.0+ availability checks
- URLProtocol registration/unregistration in setup/teardown is critical
- Temporary directories need proper cleanup to avoid test pollution
- Serial queue testing may require careful timing/synchronization

### Phase 3 Implementation Priorities

1. **Start with AssetBundleManager mocking** - this is the core of update logic
2. **Implement delegate callback testing** - essential for update flow verification
3. **Test bundle switching state management** - currentAssetBundle vs pendingAssetBundle
4. **Add configuration persistence tests** - version tracking between app restarts

## Test Implementation Workflow 🔄

**Required workflow for implementing new test phases:**

### 1. Update Cordova Test Comments

- Add comments to `tests/cordova_tests.js` referencing the mapped Swift tests
- **Example format:** `// Implemented in Swift: BasicServingTests.testAssetBundleAssetsAccess()`
- This creates bidirectional traceability between original and new tests

### 2. Verify Tests Work

- **Always run `swift test`** after implementing new tests to confirm they pass
- Fix any compilation or runtime issues before proceeding
- Ensure all existing tests continue to pass

### 3. Format Code

- **Always run `npm run fmt`** after confirming tests work
- This runs ESLint, Prettier, and SwiftLint to maintain code quality
- Required before considering test implementation complete

### 4. Update Test Plan Status

- Update this NEW_TEST_PLAN.md file with completion status
- Mark tests as ✅ **Done** in the status tables above
- Document any key insights or architectural discoveries

**Complete workflow example:**

```bash
# 1. Implement Swift tests
# 2. Add comments to cordova_tests.js
# 3. Verify tests work
swift test
# 4. Format code
npm run fmt
# 5. Update NEW_TEST_PLAN.md status
```

This workflow ensures quality, maintainability, and traceability throughout the testing implementation.
