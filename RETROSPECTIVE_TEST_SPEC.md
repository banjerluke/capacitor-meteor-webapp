# Retrospective Spec: Architectural changes from 0d13dcbc104b60d0cd521fc3bbf1f3de468c41df to HEAD

Goal: enable an AI agent to re-implement the HEAD-era design starting from the base commit. Focus on high-level architecture (DI, serving model, update orchestration, tests) with selective code snippets.

Decisions (from maintainer)
- Plugin initialization and DI entrypoint: assistant to choose best pattern
- Shim injection policy: always on
- Minimum platforms: iOS 14 (shipping target), macOS 11 only to enable `swift test`
- macOS support scope: test-only, otherwise not required
- JS bridge/shim API: final, unchanged
- Startup timeout: default 10s, configurable via Capacitor config if easy
- DI surface: pragmatic (enough to port Cordova tests with minimal mocks)
- URLSessionConfiguration: injectable, no custom prod overrides needed
- Serving root: only `public` (no `www` fallback)
- CI: manual `swift test` for now
- Cordova test file: documentation/traceability only
- Error text parity: semantic equivalence preferred; exact strings not required

---

## 1) Core architecture and responsibilities

Layering (target state):
- Core business logic: [CapacitorMeteorWebApp.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebApp.swift)
  - Orchestrates bundle initialization, bundle switching, startup timeout/rollback, and eventing
  - Sets Capacitor server base path to a disk directory (no embedded server)
- Update/download subsystem:
  - [AssetBundleManager.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Downloader/AssetBundleManager.swift): coordinates checks and lifecycle
  - [AssetBundleDownloader.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Downloader/AssetBundleDownloader.swift): fetches manifest/assets, verifies responses/hashes/runtime config, tolerates 404 source maps
  - Data model: [AssetBundle.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Bundle/AssetBundle.swift), [Asset.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Bundle/Asset.swift), AssetManifest (unchanged file name)
- Serving/organization:
  - [BundleOrganizer.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Bundle/BundleOrganizer.swift): lays out files into a per-version "serving" directory and injects the WebAppLocalServer shim into `index.html`
- Persistence/config/utilities: 
  - [WebAppConfiguration.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/WebAppConfiguration.swift): UserDefaults-backed state (last good/downloaded, blacklist, etc.)
  - [Errors.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Utils/Errors.swift) & [Utility.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Utils/Utility.swift)
  - [Timer.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Utils/Timer.swift): GCD-backed one-shot timer
- Dependency injection:
  - [CapacitorMeteorWebAppDependencies.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebAppDependencies.swift): container + protocol abstractions (filesystem, timer, bundle, bridge, URLSessionConfiguration, and key URLs)
- Capacitor bridge wrapper:
  - [CapacitorMeteorWebAppPlugin.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebAppPlugin.swift): CAPBridgedPlugin that forwards JS calls and emits events mapped from native notifications

High-level theme changes from base:
- Embedded HTTP server removed; serving is directory-based via Capacitor’s `setServerBasePath()`
- Hard separation between business logic and Capacitor via a small `CapacitorBridge` protocol
- Testable design via injected dependencies and URLProtocol-based network mocking
- Bundle organization and JS API compatibility retained via shim injection into `index.html`

---

## 2) Dependency Injection contract

Create a DI container and protocol surfaces to enable real-vs-mock boundaries while keeping business logic real.

Key protocols and container (abbreviated from the current code):

```swift
public protocol FileSystemProvider {
    func fileExists(atPath path: String) -> Bool
    func removeItem(at url: URL) throws
    func createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]?) throws
    func urls(for: FileManager.SearchPathDirectory, in: FileManager.SearchPathDomainMask) -> [URL]
}

public protocol TimerProvider { func createTimer(queue: DispatchQueue?, block: @escaping () -> Void) -> TimerInterface }
public protocol TimerInterface { func start(withTimeInterval: TimeInterval); func stop() }

public protocol BundleProvider { var resourceURL: URL? { get } }
public protocol CapacitorBridge: AnyObject {
    func setServerBasePath(_ path: String)
    func getWebView() -> AnyObject?
    var webView: WKWebView? { get }
    func reload()
}

public struct CapacitorMeteorWebAppDependencies {
    public let configuration: WebAppConfiguration
    public let fileSystem: FileSystemProvider
    public let timerProvider: TimerProvider
    public let bundleProvider: BundleProvider
    public let capacitorBridge: CapacitorBridge?
    public let wwwDirectoryURL: URL
    public let servingDirectoryURL: URL
    public let versionsDirectoryURL: URL
    public let urlSessionConfiguration: URLSessionConfiguration
}
```

Production builder rules:
- Use only `public` for web assets root (no `www` fallback)
- Resolve Library dir via `FileManager.urls(for: .libraryDirectory, in: .userDomainMask).first`
- Define "NoCloud/meteor" (versions) and "NoCloud/meteor-serving" (serving) subpaths
- Default `URLSessionConfiguration.default`
- Provide a `SystemTimerProvider` that wraps the custom [Timer.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Utils/Timer.swift)

Test builder rules:
- Allow injection of: `FileSystemProvider`, `TimerProvider`, `CapacitorBridge`, and a `URLSessionConfiguration` pre-configured with a test `URLProtocol` class
- Accept explicit temp directories for `www`, `serving`, `versions`

Rationale: This is the minimum surface needed to port the Cordova tests with minimal mocking while keeping the core downloading, organizing, and switching logic real.

---

## 3) Core business logic (CapacitorMeteorWebApp)

Responsibilities:
- Initialize from a bundled web bundle (program.json + assets) and compute the initial `AssetBundle`
- Create/clean `versions` and `serving` directories, reset config when initial bundle version changes
- Select current bundle: prefer `lastDownloadedVersion` if present/available; otherwise use the bundled bundle
- Organize the current bundle into a per-version directory under `serving`, then call `setServerBasePath()` on the bridge
- Track potential update via `pendingAssetBundle`; switch atomically on reload
- Startup watchdog: when switching to a new version, start a one-shot timer (default 10s) that reverts to a last known good version (or bundled) on timeout
- On successful startup: mark `lastKnownGoodVersion` and asynchronously purge older versions
- Expose async or callback APIs: checkForUpdates, startupDidComplete, isUpdateAvailable, reload, getCurrentVersion
- Emit notifications: `MeteorWebappUpdateAvailable` and `MeteorWebappUpdateFailed` (bridged to JS)

Implementation notes and constraints:
- Always inject the WebAppLocalServer shim during organization (see §4)
- Startup timeout: default 10s; allow override via Capacitor config (see §7)
- Ensure all bridge calls (`setServerBasePath`, `reload`, webView reloads) are dispatched to main queue
- Keep bundle switching serialized via an internal queue to avoid races

Minimal API surface to implement:

```swift
public func checkForUpdates(completion: @escaping (Error?) -> Void)
public func checkForUpdates() async throws
public func startupDidComplete(completion: @escaping (Error?) -> Void)
public func startupDidComplete() async throws
public func getCurrentVersion() -> String
public func isUpdateAvailable() -> Bool
public func reload(completion: @escaping (Error?) -> Void)
public func reload() async throws
```

Expected behaviors important for tests:
- `checkForUpdates` constructs base URL `rootURL/__cordova/` and delegates to `AssetBundleManager`
- On `didFinishDownloadingBundle`, set `lastDownloadedVersion` and stage `pendingAssetBundle`, then post update-available notification
- On download errors, post update-failed notification
- `reload` organizes the pending bundle to a new serving dir, atomically sets `currentAssetBundle`, clears `pendingAssetBundle`, calls `setServerBasePath`, then triggers a reload and starts the startup timer
- `startupDidComplete` stops the timer and marks current version as `lastKnownGoodVersion`, then triggers background cleanup of older downloaded bundles

---

## 4) Directory-based serving & shim injection

Serving model:
- Replace embedded HTTP server with disk-based directory per active version under `serving` root
- After organizing, call Capacitor `setServerBasePath()` with that directory; Capacitor serves assets directly

Bundle organization (always-on shim injection):
- For each asset in the active bundle and its inherited parent assets, lay out to `targetDirectory` using URL mapping rules
- For `"/"` or `index.html`, read-modify-write by injecting a JS "shim" that provides the Cordova WebAppLocalServer API surface backed by the Capacitor plugin

Essential shim surface (abbreviated):

```html
<script>
(function() {
  if (window.WebAppLocalServer) return;
  function setup() {
    const P = (window.Capacitor?.Plugins || {}).CapacitorMeteorWebApp;
    if (!P) throw new Error('WebAppLocalServer shim: CapacitorMeteorWebApp plugin not available');
    window.WebAppLocalServer = {
      startupDidComplete(cb) { P.startupDidComplete().then(() => cb && cb()).catch(console.error); },
      checkForUpdates(cb) { P.checkForUpdates().then(() => cb && cb()).catch(console.error); },
      onNewVersionReady(cb) { P.addListener('updateAvailable', cb); },
      switchToPendingVersion(cb, errCb) { P.reload().then(() => cb && cb()).catch(e => { console.error(e); errCb?.(e); }); },
      onError(cb) { P.addListener('error', (e) => cb(new Error(e.message || 'Unknown'))); },
      localFileSystemUrl(_) { throw new Error('Local filesystem URLs not supported by Capacitor'); },
    };
  }
  if (window.Capacitor) setup(); else document.addEventListener('deviceready', setup);
})();
</script>
```

---

## 5) Update subsystem (manifest + selective downloads)

AssetBundleManager responsibilities:
- Load any already-downloaded asset bundles from the versions directory into an in-memory index
- Download `manifest.json` from `rootURL/__cordova/manifest.json`
- Decide to download based on delegate veto, blacklisted versions, and Cordova compatibility version
- If the requested version matches bundled, short-circuit to "download finished"
- If already downloaded, short-circuit to finished
- Create/clean a working `Downloading` directory, move any previous partial to `PartialDownload` and load as a cache source
- Build an `AssetBundle` from the manifest in `Downloading` and pass to `AssetBundleDownloader` with the set of missing assets
- On downloader completion, move bundle to a version-named directory and notify delegate

AssetBundleDownloader responsibilities:
- For each missing asset, create directories, try to link to cached assets, else queue network downloads
- For data tasks: validate 2xx responses; allow 404 for `*.map`; verify `ETag` hash against expected when available; switch to download task for non-index assets
- For `index.html`: after download, parse embedded runtime config and validate: `autoupdateVersionCordova` matches manifest version; has `ROOT_URL`; `appId` equals configuration’s `appId`; prevent ROOT_URL regressions to `localhost`
- Handle retries with simple exponential backoff and optional reachability
- Notify finish/failure via delegate

Important compat behaviors (for test parity with Cordova):
- Tolerate missing source maps (404) without failing the whole update
- Verify ETag-SHA1 where provided; treat mismatches as invalid asset errors
- Treat mismatched version/appId/ROOT_URL in index runtime config as errors

---

## 6) Capacitor plugin bridge

Implement a thin CAP plugin that adapts to the `CapacitorBridge` protocol and forwards calls to `CapacitorMeteorWebApp`:
- JS methods: `checkForUpdates`, `startupDidComplete`, `getCurrentVersion`, `isUpdateAvailable`, `reload`
- Eventing: translate native notifications to JS listeners `updateAvailable` and `error`

Initialization pattern (recommended):
- Prefer a simple production entrypoint in the app/plugin: create the bridge adapter and initialize `CapacitorMeteorWebApp` using its convenience initializer that composes production dependencies internally. Keep a separate `init(dependencies:)` strictly for tests.
- Read optional plugin configuration to override startup timeout (see §7)

Sketch:

```swift
override public func load() {
  bridgeAdapter = CapacitorBridgeAdapter(bridge: self.bridge)
  // Read config (if present) and pass via a hook on CapacitorMeteorWebApp post-init
  implementation = CapacitorMeteorWebApp(capacitorBridge: bridgeAdapter)
  if let timeout = readStartupTimeoutFromConfig() { implementation.setStartupTimeout(timeout) }
  subscribeToNotifications()
}
```

With this approach, tests don’t rely on the plugin class; they instantiate the core directly with injected test dependencies.

---

## 7) Startup timeout (10s default, optional config override)

Default: 10 seconds.

Configuration: add support for an optional plugin setting in `capacitor.config.*` under:

```jsonc
{
  "plugins": {
    "CapacitorMeteorWebApp": {
      "startupTimeoutSeconds": 10
    }
  }
}
```

iOS bridge read (pseudo):

```swift
private func readStartupTimeoutFromConfig() -> TimeInterval? {
  // CAPBridgeProtocol exposes configuration; read `plugins["CapacitorMeteorWebApp"]["startupTimeoutSeconds"]`
}
```

Core hook:

```swift
public func setStartupTimeout(_ seconds: TimeInterval) { self.startupTimeoutInterval = seconds }
```

Note: Keep this optional; absence means default 10s.

---

## 8) Package and platform setup

Update [Package.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/Package.swift):
- Platforms: `.iOS(.v14)`, `.macOS(.v11)` (test-only support)
- Targets: 
  - `CapacitorMeteorWebAppPlugin` (exclude the Capacitor plugin file from compilation under tests if necessary to avoid hard Capacitor dependency)
  - Test target `CapacitorMeteorWebAppTests` that copies `tests/fixtures` and defines `TESTING`

---

## 9) Testing strategy and structure (Swift XCTest)

Port Cordova tests conceptually to Swift tests that assert the behaviors of the new architecture (directory serving + update pipeline), not the legacy HTTP server.

Test projects and helpers:
- New test target under `ios/Tests/CapacitorMeteorWebAppTests/`
- Keep Cordova tests file [cordova_tests.js](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/tests/cordova_tests.js) as documentation/traceability only (do not execute)
- Helpers:
  - [MockMeteorServerProtocol.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Tests/CapacitorMeteorWebAppTests/TestHelpers/MockMeteorServerProtocol.swift): URLProtocol mock server
  - [TestFixtures.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Tests/CapacitorMeteorWebAppTests/TestHelpers/TestFixtures.swift): writes `program.json` and files for fake bundles
  - [TestDependencies.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Tests/CapacitorMeteorWebAppTests/TestHelpers/TestDependencies.swift): DI factory + mocks (filesystem, timer, bridge)
  - [AsyncTestHelpers.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Tests/CapacitorMeteorWebAppTests/TestHelpers/AsyncTestHelpers.swift)

Test suites (examples):
- Basic serving: file presence and content in the serving directory; that `setServerBasePath` is called; version name in path
- Update scenarios: bundled→downloaded, downloaded→downloaded, downloaded→bundled; selective network requests; persistence across restarts; cleanup after `startupDidComplete`
- No-update scenarios: only `manifest.json` requested; no ready callback
- Error handling: missing asset (404 non-map), ETag mismatch, wrong/missing `ROOT_URL`, wrong/missing `appId`, missing/different Cordova compatibility version
- Partial download: resume behavior with the `PartialDownload` cache

Network mocking pattern:

```swift
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockMeteorServerProtocol.self]
let deps = CapacitorMeteorWebAppDependencies.test(
  capacitorBridge: mockBridge,
  wwwDirectoryURL: bundled,
  servingDirectoryURL: serving,
  versionsDirectoryURL: versions,
  urlSessionConfiguration: config
)
```

Startup timer mocking:
- Provide a `MockTimerProvider`/`MockTimer` that captures `start`/`stop` and allows manual `fireNow()` to simulate timeout-driven reversion

Expectations on error parity:
- Prefer semantic checks (`contains`, categories) over exact messages; align categories via [Errors.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Utils/Errors.swift)

---

## 10) Configuration and persistence rules

WebAppConfiguration keys (persisted in a dedicated UserDefaults suite in tests):
- `appId`, `rootURL`, `cordovaCompatibilityVersion`, `lastSeenInitialVersion`, `lastDownloadedVersion`, `lastKnownGoodVersion`, `blacklistedVersions`, `versionsToRetry`
- `addBlacklistedVersion(_:)` moves a version between retry/blacklist lists as necessary
- `reset()` clears all version-related state when the bundled initial changes

Re-initialization behavior:
- On app relaunch, prefer `lastDownloadedVersion` if that bundle exists; else fall back to bundled
- When the initial bundled version changes, delete `versions` and `serving` roots and `reset()` configuration

---

## 11) Security and performance considerations
- Avoid copying large files when possible: first attempt hard-links during organization; fall back to copy on failure
- Do not log secrets; no secrets are involved in this plugin
- Organize and deletion operations should be done off the main thread; bridge calls marshalled onto main

---

## 12) Verification plan

Commands:
- Build tests: `swift test`
- Format: `npm run fmt`

Acceptance signals:
- All XCTest suites pass locally on macOS runner
- Basic serving tests confirm correct directory layout and bridge interaction
- Update tests confirm selective downloads and state persistence

---

## 13) File map (target HEAD structure)

- Sources:
  - [ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebApp.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebApp.swift)
  - [ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebAppDependencies.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebAppDependencies.swift)
  - [ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebAppPlugin.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/CapacitorMeteorWebAppPlugin.swift)
  - [ios/Sources/CapacitorMeteorWebAppPlugin/Bundle/*](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Bundle/AssetBundle.swift)
  - [ios/Sources/CapacitorMeteorWebAppPlugin/Downloader/*](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Downloader/AssetBundleManager.swift)
  - [ios/Sources/CapacitorMeteorWebAppPlugin/Utils/*](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/Utils/Errors.swift)
  - [ios/Sources/CapacitorMeteorWebAppPlugin/WebAppConfiguration.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Sources/CapacitorMeteorWebAppPlugin/WebAppConfiguration.swift)
- Tests (Swift):
  - [ios/Tests/CapacitorMeteorWebAppTests/BasicServingTests.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Tests/CapacitorMeteorWebAppTests/BasicServingTests.swift)
  - [ios/Tests/CapacitorMeteorWebAppTests/VersionUpdateTests.swift](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Tests/CapacitorMeteorWebAppTests/VersionUpdateTests.swift)
  - [ios/Tests/CapacitorMeteorWebAppTests/TestHelpers/*](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/ios/Tests/CapacitorMeteorWebAppTests/TestHelpers/TestDependencies.swift)
- Legacy mapping doc:
  - [tests/cordova_tests.js](file:///Users/luke/Code/@banjerluke/capacitor-meteor-webapp/tests/cordova_tests.js) (for traceability only)

---

## 14) Implementation checklist (from base)

1. Add DI surface and container; implement production/test builders as specified (serving root = `public` only)
2. Port/author core classes (CapacitorMeteorWebApp, BundleOrganizer, AssetBundleManager/Downloader, Asset/Bundle/Manifest, WebAppConfiguration, Errors, Utility, Timer)
3. Implement Capacitor bridge adapter and plugin; ensure event relays and JS method bindings; wire optional config for startup timeout
4. Wire startup timer default to 10s and expose a setter used by plugin load to apply config override
5. Add test target, helpers, and parity tests in Swift mirroring Cordova scenarios; use URLProtocol mocking and DI factory
6. Ensure macOS target compiles (test-only); iOS remains primary target (14+)
7. Keep legacy cordova test file for documentation; update comments to link back to Swift tests
8. Verify with `swift test`; run `npm run fmt`

This spec captures the architectural delta and the minimum contracts an AI agent needs to re-implement the changes from the base commit to the current design.
