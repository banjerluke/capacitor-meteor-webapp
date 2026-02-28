# Android Port Plan — capacitor-meteor-webapp

## Overview

Port the Meteor hot code push plugin from the iOS Capacitor implementation to
Android. The iOS port is already complete and battle-tested against the legacy
Cordova codebase. The Android port should mirror the iOS architecture as closely
as possible, adapted for Android platform APIs.

**Source of truth**: The *current iOS Capacitor code* (post-P0-fix), NOT the
legacy Cordova Android code. The Cordova code is a useful reference for
Android-specific patterns, but the iOS Capacitor code is the canonical
implementation.

**Capacitor version**: 8. Java 21 target (recommended by Capacitor 8).
**Min SDK**: 24 (Android 7.0). Bumped from scaffold default of 23 to enable
`ConnectivityManager.registerDefaultNetworkCallback()` without fallback.
**Compatibility constraint**: Keep API 24 support. Do not use
`java.nio.file.*` (`Files`, `Path`, `Paths`, `StandardCopyOption`) in
implementation code. Use API-24-safe `java.io`/`File`-based helpers.

---

## What This Plugin Does

Serves a bundled Meteor web app through Capacitor's local server and implements
hot code push (OTA updates). On startup, it either serves the initial bundled
assets or the last successfully downloaded version. In the background, it checks
the Meteor server for new versions, downloads changed assets, and makes them
available for the next reload. A startup timer and version blacklisting system
provides rollback safety if a new version fails to boot.

---

## Architecture

### How Capacitor Serves Files (Both Platforms)

Capacitor's `WebViewLocalServer` intercepts WebView requests and serves files
from a configurable base path on the filesystem. When the plugin calls
`bridge.setServerBasePath(path)`, the server switches to serving files from
that directory. The WebView requests files by URL path (e.g.,
`/packages/templating/template.html.js`), and the server resolves them as
`<basePath>/packages/templating/template.html.js`.

**Critical implication**: Meteor bundles store files by `filePath` (e.g.,
`app/template.html.js`), which differs from their `urlPath`. The plugin must
"organize" bundles — copying files into a serving directory laid out
by URL path — before pointing Capacitor at them. This is handled by
`BundleOrganizer`.

### Android-Specific Bridge API

| Method | Behavior |
|--------|----------|
| `bridge.setServerBasePath(String)` | Changes serving directory AND reloads WebView (one call) |
| `bridge.setServerAssetPath(String)` | Same but for APK `assets/` directory |
| `bridge.reload()` | Reloads WebView only |
| `bridge.getWebView()` | Returns the `WebView` instance |
| `bridge.getContext()` | Returns Android `Context` |
| `bridge.getActivity()` | Returns `AppCompatActivity` |
| `bridge.getServerBasePath()` | Returns current serving path |

Key difference from iOS: `setServerBasePath` on Android **automatically
reloads** the WebView. On iOS, `setServerBasePath` and `reload` are separate
operations. The Android implementation should account for this (e.g., don't
call `reload()` after `setServerBasePath()` — it's redundant and would cause
a double reload).

**Verified** against Capacitor source (`Bridge.java:1417-1420`):
```java
public void setServerBasePath(String path) {
    localServer.hostFiles(path);
    webView.post(() -> webView.loadUrl(appUrl));  // auto-reloads
}
```

The initial asset path is `assets/public/` — confirmed via
`Bridge.DEFAULT_WEB_ASSET_DIR = "public"` (`Bridge.java:92`), loaded at
startup via `localServer.hostAssets(DEFAULT_WEB_ASSET_DIR)` (`Bridge.java:275`).

### Directory Layout on Android

```
/data/data/<app>/files/
  meteor/                           — versionsDirectory
    <version-hash>/                 — downloaded bundle (by version)
      program.json
      <asset files by filePath>
    Downloading/                    — in-progress download
    PartialDownload/                — previous incomplete download (for cache reuse)
  meteor-serving/                   — servingDirectory
    <version-hash>/                 — organized bundle (files laid out by urlPath)
      index.html                    — with injected WebAppLocalServer shim
      packages/
        templating/
          template.html.js
      ...
```

The initial bundle lives in the APK at `assets/public/` (Capacitor's default).

### Data Flow

```
1. App starts
2. Plugin initializes:
   a. Load initial bundle from APK assets/public/
   b. Check if lastSeenInitialVersion changed (app binary update) → if so, wipe downloads + reset config
   c. Load previously downloaded bundles from versionsDirectory
   d. Select currentAssetBundle (lastDownloadedVersion if exists, else initial)
   e. If current bundle is initial (no downloaded version): keep Capacitor default serving from assets/public (no organize, no setServerBasePath call)
   f. If current bundle is downloaded: organize it into servingDirectory via BundleOrganizer, then call bridge.setServerBasePath(servingDirectory/<version>)
   g. If serving an unverified downloaded version, start startup timer
3. JS calls startupDidComplete() → cancel timer, mark version as lastKnownGoodVersion, prune old bundles
4. JS calls checkForUpdates() → AssetBundleManager fetches manifest.json from server
5. AssetBundleManager downloads changed assets → stores in versionsDirectory
6. Plugin sets pendingAssetBundle, fires "updateAvailable" event to JS
7. JS calls reload() → plugin organizes pending bundle, calls setServerBasePath (which reloads)
8. If startup timer fires before startupDidComplete → revert to lastKnownGoodVersion or initial bundle (`bridge.setServerAssetPath("public")` for initial)
```

### API 24 File Operations (Implementation Constraint)

Because min SDK remains 24, all filesystem operations must use API-24-safe
`java.io`/`File` operations. Introduce a small internal `FileOps` utility
class and use it from `AssetBundleManager`, `AssetBundleDownloader`, and
`BundleOrganizer`.

Required helper methods:
- `copy(InputStream in, File to)`
- `copy(File from, File to)`
- `moveAtomicallyOrCopyDelete(File from, File to)` — try `renameTo` first, then copy+delete fallback
- `deleteRecursively(File root)`
- `ensureParentDirectory(File file)`

Rules:
- Never call `java.nio.file.*` APIs.
- Always write to temporary files first, then move into place.
- If `renameTo` fails (cross-volume or filesystem restriction), fall back to
  copy+delete.

---

## File Structure

```
android/src/main/java/com/banjerluke/capacitormeteorwebapp/
├── CapacitorMeteorWebAppPlugin.java   — Capacitor plugin bridge
├── CapacitorMeteorWebApp.java         — Core orchestration logic
├── WebAppConfiguration.java           — SharedPreferences persistence
├── AssetBundle.java                   — Bundle model + runtime config parsing
├── Asset.java                         — Single asset within a bundle
├── AssetManifest.java                 — program.json parser
├── AssetBundleManager.java            — Download coordinator + bundle cache
├── AssetBundleDownloader.java         — Individual asset downloader with retry
├── BundleOrganizer.java               — File layout for serving
├── RetryStrategy.java                 — Triangular backoff
├── NetworkReachabilityManager.java    — Connectivity monitoring
└── WebAppError.java                   — Error types
```

Also update:
- `android/build.gradle` — bump `minSdkVersion` to 24, keep Java 21 compile options
- `android/src/main/AndroidManifest.xml` — add `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />` for connectivity monitoring

---

## File-by-File Specifications

### CapacitorMeteorWebAppPlugin.java

**Mirrors**: `ios/.../CapacitorMeteorWebAppPlugin.swift`

Thin bridge layer. Extends `com.getcapacitor.Plugin`.

Responsibilities:
- `@CapacitorPlugin(name = "CapacitorMeteorWebApp")` annotation
- `load()` → create `CapacitorMeteorWebApp` instance, passing `getBridge()`
- Plugin methods: `checkForUpdates`, `startupDidComplete`, `getCurrentVersion`,
  `isUpdateAvailable`, `reload` — each delegates to the implementation and
  calls `call.resolve()` / `call.reject()`
- Forward events from the implementation to JS via `notifyListeners("updateAvailable", data)` and `notifyListeners("error", data)`

The iOS version uses `NotificationCenter` to decouple the plugin from the
implementation. On Android, use a direct callback interface (`EventCallback`,
see Resolved Decision #5). The implementation holds a reference to the
plugin's event callback and calls it directly. Simpler and more debuggable
than `NotificationCenter`.

### CapacitorMeteorWebApp.java

**Mirrors**: `ios/.../CapacitorMeteorWebApp.swift`

Core orchestration class. This is the largest and most important file.

Responsibilities:
- Holds references to `Bridge`, `WebAppConfiguration`, `AssetBundleManager`
- Manages `currentAssetBundle`, `pendingAssetBundle`, `switchedToNewVersion`
- `initializeAssetBundles()` — load initial bundle from APK, detect app
  binary updates, load previously downloaded bundles, select current bundle
- `setupCurrentBundle()` — if current bundle is downloaded: organize via
  `BundleOrganizer` and call `bridge.setServerBasePath()`; if current bundle
  is initial: keep default `assets/public` serving (or call
  `bridge.setServerAssetPath("public")` when explicitly reverting from a
  downloaded bundle), then clean up old serving directories
- `checkForUpdates()` — resolve rootURL, call `assetBundleManager.checkForUpdates(baseUrl)`
- `startupDidComplete()` — stop startup timer, set lastKnownGoodVersion,
  trigger background cleanup of old bundles
- `reload()` — organize pending bundle, swap current/pending, call
  `bridge.setServerBasePath()` (which auto-reloads on Android)
- `revertToLastKnownGoodVersion()` — blacklist current version, select
  fallback, organize and switch (or `setServerAssetPath("public")` for
  initial fallback)
- Startup timer management (see Startup Timer section below)
- Implements `AssetBundleManager.Callback` interface

**Bridge interaction differences from iOS**:
- On iOS, `setServerBasePath` does NOT reload; a separate `bridge.reload()`
  or `webView.reloadFromOrigin()` call is needed. On Android,
  `setServerBasePath` reloads automatically. The `reload()` method should
  NOT call `bridge.reload()` after `setServerBasePath()`.
- On iOS, the implementation holds a weak `CapacitorBridge` protocol reference
  (adapter pattern). On Android, it can hold the `Bridge` directly since
  `getBridge()` returns a concrete class. Use a `WeakReference<Bridge>` to
  avoid leaking the Activity.
- Capacitor can switch back to APK assets directly with
  `bridge.setServerAssetPath("public")`. Use this for explicit revert-to-initial
  flows instead of organizing the initial bundle into filesystem directories.

**Loading the initial asset bundle**: On iOS, the initial bundle is at
`Bundle.main.resourceURL/public/` (a directory on the filesystem). On
Android, the initial bundle is inside the APK at `assets/public/` (verified:
`Bridge.DEFAULT_WEB_ASSET_DIR = "public"`) which is NOT directly accessible
as a filesystem path — it must be read via `AssetManager`.

**Decision**: Read directly from AssetManager via the `ResourceReader`
functional interface (see Resolved Decision #1). The caller provides an
AssetManager-backed implementation for the initial bundle. The initial
bundle only needs to read `program.json` and `index.html` — it doesn't need
full filesystem access because `BundleOrganizer` handles the file layout for
serving.

### WebAppConfiguration.java

**Mirrors**: `ios/.../WebAppConfiguration.swift`

Port nearly line-for-line from the Cordova version. Uses Android
`SharedPreferences` (equivalent to iOS `UserDefaults`).

Properties stored:
- `appId` (String)
- `rootUrl` (String — note: iOS stores as `URL`, Android stores as String)
- `cordovaCompatibilityVersion` (String)
- `lastDownloadedVersion` (String)
- `lastSeenInitialVersion` (String)
- `lastKnownGoodVersion` (String)
- `blacklistedVersions` (Set<String>)
- `versionsToRetry` (Set<String>)

The `addBlacklistedVersion()` method implements two-strike blacklisting
(first failure → retry list, second → blacklist). This is identical across
all three codebases (Cordova Android, Cordova iOS, Capacitor iOS).

The `reset()` method clears all stored preferences.

Persistence invariants:
- Set `lastSeenInitialVersion` immediately after initial bundle is loaded.
- Set `lastDownloadedVersion` only after download is fully verified and moved
  into final `<version>/` directory.
- Set `lastKnownGoodVersion` only on `startupDidComplete()`.
- Update two-strike state atomically:
  - first startup failure for a version: add to `versionsToRetry`
  - second startup failure for the same version: move to `blacklistedVersions`
- On binary update detection (`lastSeenInitialVersion` changed), clear
  download-related keys and wipe on-disk bundles in the same flow.

SharedPreferences key names: Use the same `MeteorWebApp*` prefix as iOS to
keep cross-platform consistency. The Cordova Android version used bare keys
(`appId`, `rootUrl`, etc.) but since these are in a named preference file
(`MeteorWebApp`), there's no collision risk either way. Match iOS for
consistency: `MeteorWebAppId`, `MeteorWebAppRootURL`, etc.

### AssetBundle.java

**Mirrors**: `ios/.../AssetBundle.swift`

Represents a versioned collection of assets. Core model class.

Key properties:
- `directoryUrl` — either an AssetManager path (initial) or filesystem `File` (downloaded)
- `version`, `cordovaCompatibilityVersion` — from manifest
- `ownAssetsByURLPath` — `Map<String, Asset>` of this bundle's own assets
- `parentAssetBundle` — for cache inheritance
- `indexFile` — the index.html asset
- `runtimeConfig` — lazily parsed from index.html

Key methods:
- Constructor: parse manifest entries, skip assets cached in parent bundle,
  add source maps, add index.html entry
- `assetForUrlPath(String)` — look up asset, fall through to parent
- `cachedAssetForUrlPath(String, String hash)` — look up with hash matching
  (for download optimization)
- `getRuntimeConfig()` — lazily parse `__meteor_runtime_config__` from index.html
- `getAppId()`, `getRootUrlString()` — extracted from runtime config
- `didMoveToDirectoryAtUrl(File)` — update after download completes

**AssetManager abstraction**: The initial bundle's files live in `assets/public/`
inside the APK and must be read via `android.content.res.AssetManager`. Downloaded
bundles live on the filesystem and are read via `java.io.File`. AssetBundle
abstracts over this via the `ResourceReader` functional interface (see Resolved
Decision #1). The constructor accepts a `ResourceReader`, and the caller
(`CapacitorMeteorWebApp`) provides either an AssetManager-backed or File-backed
implementation.

### Asset.java

**Mirrors**: `ios/.../Asset.swift`

Simple data class representing a single file in a bundle.

Fields: `filePath`, `urlPath`, `fileType`, `cacheable`, `hash`,
`sourceMapUrlPath`, plus a reference to the owning `AssetBundle`.

Computed properties:
- `getFileUrl()` — resolves `filePath` relative to bundle's directory
- `getFile()` — returns `java.io.File` for downloaded bundles (throws or
  returns null for initial bundle assets)

### AssetManifest.java

**Mirrors**: `ios/.../AssetManifest.swift`

Parses `program.json`. Port from Cordova version with one key change:
reads `cordovaCompatibilityVersions.android` (same as Cordova Android).

Note: The iOS version reads `cordovaCompatibilityVersions.ios`. Each platform
reads its own key.

Fields: `version`, `cordovaCompatibilityVersion`, `List<Entry> entries`.

Inner class `Entry`: `filePath`, `urlPath`, `fileType`, `cacheable`, `hash`,
`sourceMapFilePath`, `sourceMapUrlPath`.

Filter: only entries where `where == "client"`.

### AssetBundleManager.java

**Mirrors**: `ios/.../AssetBundleManager.swift`

Coordinates checking for updates and managing the download lifecycle.

Key behaviors:
- `checkForUpdates(URL baseUrl)` — fetch `manifest.json` from server,
  parse, check if download is needed, start download
- Manages `downloadedAssetBundlesByVersion` map
- Uses `Downloading/` temp directory during download, moves to
  `<version>/` on completion
- `PartialDownload/` stores previous incomplete downloads for cache reuse
- Asset caching: before downloading an asset, check if it exists in any
  previously downloaded bundle or the partial download (by URL path + hash match)
- `removeAllDownloadedAssetBundlesExceptForVersion(String)` — cleanup

**HTTP client**: Use `java.net.HttpURLConnection` for the manifest download.
This is a single small JSON file. No need for an external HTTP library.
The Cordova version used OkHttp3, but `HttpURLConnection` is adequate and
avoids adding a dependency.

**Threading**: Use a single-threaded `ExecutorService` for synchronization
(equivalent to iOS's serial `DispatchQueue`). The Cordova version used
OkHttp's async callbacks; we'll use the executor for consistency with iOS.

**Callback interface**:
```
interface Callback {
    boolean shouldDownloadBundleForManifest(AssetManifest manifest);
    void onFinishedDownloadingAssetBundle(AssetBundle assetBundle);
    void onError(Throwable cause);
}
```

### AssetBundleDownloader.java

**Mirrors**: `ios/.../AssetBundleDownloader.swift`

Downloads individual assets for a bundle. This is the most complex file due
to retry logic and network monitoring.

Key behaviors:
- Downloads all missing assets concurrently (up to 6 connections)
- Uses `HttpURLConnection` (Cordova used OkHttp)
- Validates each asset `filePath` before writing to disk (reject absolute,
  `..`, backslashes, and paths that escape the bundle root after canonicalization)
- Verifies ETag SHA1 hash against expected hash for each asset
- For index.html: parses runtime config and verifies
  `autoupdateVersionCordova` matches expected version
- Verifies ROOT_URL won't change to localhost
- Verifies appId matches
- Downloads to temp files, renames on completion
- Skips missing source map files (404) gracefully

**Retry strategy** (ported from iOS):
- On download failure, schedule a retry using `RetryStrategy` (triangular backoff)
- `RetryStrategy` provides intervals: 0.1s, 1s, 2s, 4s, 7s, 11s, 16s, 22s, 30s, 30s...
- On network reachability change (becomes reachable), immediately retry
- On app returning to foreground, resume if suspended

**Network reachability**: Use Android's `ConnectivityManager` with
`registerDefaultNetworkCallback()` (requires API 24, our min SDK). This is
the modern Android equivalent of iOS's `NWPathMonitor`. Register for default
network callbacks and trigger retry when connectivity is restored.

**Threading**: Use a `ThreadPoolExecutor` with max 6 threads for concurrent
downloads. Use a separate single-thread executor for coordination/state
management.

**States**: `SUSPENDED`, `RUNNING`, `WAITING`, `CANCELING`, `INVALID` —
same as iOS.

### BundleOrganizer.java

**Mirrors**: `ios/.../BundleOrganizer.swift`

Organizes bundle files into a serving directory laid out by URL path.

Key behaviors:
- `organizeBundle(AssetBundle, File targetDirectory)` — main entry point
- Validates bundle first:
  - reject path traversal/escape in both `urlPath` and `filePath`
  - reject absolute paths
  - reject backslashes and empty path segments
  - normalize and reject duplicate target URL paths after normalization
  - enforce canonical destination remains under `targetDirectory`
- For each own asset: create directory structure, copy source file to target
  path derived from normalized `urlPath`
- For inherited parent assets: also organize those that aren't overridden
- **index.html special handling**: read the file, inject the
  `WebAppLocalServer` compatibility shim before `</head>`, write to target
- For non-index files: copy via internal `FileOps.copy(...)` helpers
  (hard links are blocked by SELinux on Android — see "Hard Links" in
  Resolved Decisions below)
- Skip missing source map files gracefully

**Shim injection**: The shim script provides `window.WebAppLocalServer` with
the same API as the Cordova plugin (`startupDidComplete`, `checkForUpdates`,
`onNewVersionReady`, `switchToPendingVersion`, `onError`). It bridges to the
Capacitor plugin (`CapacitorMeteorWebApp`) under the hood.

The shim is **identical across iOS and Android** — it's platform-agnostic JS
that calls Capacitor plugin methods. Copy the shim verbatim from
`BundleOrganizer.swift`.

### RetryStrategy.java

**Mirrors**: `ios/.../RetryStrategy.swift`

Trivial port. Triangular backoff: first attempt at 0.1s, then
`1 + n*(n+1)/2` seconds, capped at 30s.

### NetworkReachabilityManager.java

**Mirrors**: `ios/.../NetworkReachabilityManager.swift`

Uses Android `ConnectivityManager.registerDefaultNetworkCallback()` (API 24+)
to monitor connectivity changes. Notifies a callback when the network
becomes reachable.

Android equivalent of iOS's `NWPathMonitor`:
```java
ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
cm.registerDefaultNetworkCallback(new ConnectivityManager.NetworkCallback() {
    @Override
    public void onAvailable(Network network) { /* notify reachable */ }
    @Override
    public void onLost(Network network) { /* notify not reachable */ }
});
```

### WebAppError.java

**Mirrors**: `ios/.../Errors.swift`

Exception class(es) for the plugin. Could be a single class with an enum for
the error type, or separate exception classes. A single class with a reason
string (like Cordova's `WebAppException`) is simplest.

---

## Startup Timer

The startup timer is a safety mechanism that reverts to the last known good
version if the app doesn't call `startupDidComplete()` within a timeout
(default 30 seconds on iOS, 20 seconds on Cordova).

**Android implementation**: Use a `ScheduledExecutorService` or `Handler`
with `postDelayed()`. The `Handler` approach is simpler and runs on the main
looper.

Behaviors:
- Started when serving an unverified downloaded version
- Canceled when `startupDidComplete()` is called
- Suspended when the app enters background; store remaining time
- Resumed on foreground with remaining time
- If remaining time is <= 0 on resume, revert immediately
- When it fires: blacklist current version, revert to last known good or
  initial bundle

For pause/resume handling: register a `LifecycleObserver` on the
`ProcessLifecycleOwner` or use `Application.ActivityLifecycleCallbacks` or
watch for `Activity.onStop()`. The simplest approach for a Capacitor plugin
is to override the plugin's `handleOnPause()` method (Capacitor calls this
when the Activity is paused), and resume in `handleOnResume()`.

---

## build.gradle and Manifest Changes

Bump `minSdk` from 23 to **24** in `android/build.gradle`. This enables
`ConnectivityManager.registerDefaultNetworkCallback()` without fallback.
API 24 = Android 7.0 (2016), extremely safe baseline.

Keep `minSdk` at 24 (do not raise to 26 for this port).

Add to `android/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

The `INTERNET` permission is already required by Capacitor itself and does
not need to be declared by the plugin.

No external dependencies are needed. The implementation uses only:
- `java.net.HttpURLConnection` for HTTP
- API-24-safe `java.io`/`File` operations via internal `FileOps`
- `android.net.ConnectivityManager` for network monitoring
- `android.content.SharedPreferences` for persistence
- `org.json.JSONObject` / `org.json.JSONArray` for JSON parsing (bundled with Android)
- `java.util.concurrent` for threading

---

## JS/TypeScript Layer

No changes needed. The existing `definitions.ts`, `index.ts`, `web.ts`, and
the shim injected by `BundleOrganizer` are all platform-agnostic. The Android
plugin class name matches what `registerPlugin('CapacitorMeteorWebApp', ...)`
expects.

The `@CapacitorPlugin(name = "CapacitorMeteorWebApp")` annotation must match
the `jsName` used in the iOS plugin and `registerPlugin()` call.

---

## Key Differences from iOS Implementation

| Aspect | iOS | Android |
|--------|-----|---------|
| `setServerBasePath` | Does NOT reload | Reloads automatically (verified) |
| Initial bundle location | `Bundle.main/public/` (filesystem) | `assets/public/` (APK, via AssetManager) (verified) |
| Persistence | `UserDefaults` | `SharedPreferences` |
| HTTP client | `URLSession` | `HttpURLConnection` |
| File linking | `FileManager.linkItem()` (hard links) | `FileOps` copy only (hard links blocked by SELinux) |
| Network monitoring | `NWPathMonitor` | `ConnectivityManager.registerDefaultNetworkCallback()` (API 24+) |
| Background task | `UIBackgroundTaskIdentifier` | Not needed (Android doesn't kill downloads as aggressively) |
| Threading | `DispatchQueue` (GCD) | `ExecutorService` / `Handler` |
| Timer | Custom GCD-based `Timer` | `Handler.postDelayed()` or `ScheduledExecutorService` |
| Bridge reference | Weak protocol reference | `WeakReference<Bridge>` |
| Lifecycle hooks | `UIApplication` notifications | Plugin `handleOnPause()`/`handleOnResume()` |

**Hard links are not available on Android.** SELinux enforces a `neverallow`
rule (`neverallow all_untrusted_apps file_type:file link;`) that blocks
`link()` syscalls for all non-system apps since Android 6.0. This is a
compile-time policy assertion that OEMs cannot override. Both `Os.link()`
and hard-link attempts via Java APIs will fail with `EACCES`. Use copy
operations unconditionally via `FileOps`. (See: AOSP
`private/app_neverallows.te`, commit `85ce2c7`.)

---

## Key Differences from Legacy Cordova Android

Things we're **dropping** from the Cordova Android code:
- `CordovaPlugin` base class → `com.getcapacitor.Plugin`
- `CordovaResourceApi` → direct file I/O + AssetManager
- `CordovaPluginPathHandler` / `WebResourceHandler` / URI remapping chain →
  `setServerBasePath()` + `BundleOrganizer`
- `AssetManagerCache` + `build-extras.gradle` → not needed (Capacitor handles
  asset serving differently)
- OkHttp3 + Okio dependencies → `HttpURLConnection` + API-24-safe `java.io`/`File`
- `CallbackContext` with keep-alive → `notifyListeners()` for events

Things we're **adding** that Cordova Android lacked:
- `BundleOrganizer` (new for Capacitor architecture)
- `RetryStrategy` with triangular backoff (iOS had it, Cordova Android didn't)
- `NetworkReachabilityManager` (iOS had it, Cordova Android didn't)
- WebAppLocalServer shim injection into index.html
- Serving directory management and cleanup

---

## Resolved Implementation Decisions

### 1. AssetManager Abstraction for Initial Bundle — DECIDED: Functional Interface

Use a `@FunctionalInterface` to abstract file reading:

```java
@FunctionalInterface
interface ResourceReader {
    InputStream open(String relativePath) throws IOException;
}
```

Callers provide:
- Initial bundle: `(path) -> assetManager.open("public/" + path)`
- Downloaded bundle: `(path) -> new FileInputStream(new File(dir, path))`

This keeps `AssetBundle` clean with no internal branching. The initial
bundle only needs to read `program.json` and `index.html` — it doesn't
need full filesystem access because `BundleOrganizer` handles file layout.

### 2. Hard Links — DECIDED: Copy Only (No Hard Links on Android)

**Hard links are impossible on Android.** SELinux enforces a permanent
`neverallow all_untrusted_apps file_type:file link;` rule (since Android
6.0, commit `85ce2c7` in AOSP `system/sepolicy`). This blocks all `link()`
syscalls for non-system apps. Both `Os.link()` and `Files.createLink()`
will always fail with `EACCES` — there is no workaround.

Use copy operations unconditionally in `BundleOrganizer`. This is a
divergence from iOS (which uses `FileManager.linkItem()`) but unavoidable.
Because min SDK is 24, implement copying with API-24-safe `java.io`/`File`
helpers (`FileOps`), not `java.nio.file.*`.

### 3. File Operations Utility Layer — DECIDED: Internal `FileOps`

Implement one shared `FileOps` utility for all filesystem operations:
- `copy(InputStream, File)`
- `copy(File, File)`
- `moveAtomicallyOrCopyDelete(File, File)` (`renameTo` first)
- `deleteRecursively(File)`
- `ensureParentDirectory(File)`

This centralizes failure handling, avoids duplicated stream code, and keeps
the API-24 restriction explicit.

### 4. Startup Timeout Value — DECIDED: 30 Seconds

Match iOS. Not configurable for now (P2 deferred).

### 5. Event Communication — DECIDED: Callback Interface

```java
interface EventCallback {
    void onUpdateAvailable(String version);
    void onError(String message);
}
```

The plugin implements it and passes itself to the implementation. The
implementation calls the callback, the plugin calls `notifyListeners()`.
Simpler and more debuggable than iOS's `NotificationCenter` approach.

### 6. Threading Model — DECIDED: Executor + Handler

- **AssetBundleManager**: Single-threaded `ExecutorService` (mirrors iOS's
  serial `DispatchQueue` for atomic state management)
- **AssetBundleDownloader**: `ThreadPoolExecutor` with max 6 threads for
  concurrent downloads
- **Main thread**: `Handler(Looper.getMainLooper())` for bridge calls
  (`setServerBasePath`, `setServerAssetPath`, `reload`) and startup timer
- **Bundle switch**: Serialized on AssetBundleManager's executor (equivalent
  to iOS's `bundleSwitchQueue`)
- **Invariant**: all plugin state transitions (`currentAssetBundle`,
  `pendingAssetBundle`, startup timer state, retry state) happen on one serial
  executor; bridge/UI calls happen on main thread only

### 7. Background Download Handling — DECIDED: Skip

Not needed. Android is less aggressive about killing background work.
Cordova Android had no background task handling either. Can add
`WorkManager` later if needed.

### 8. Initial Server Path on Plugin Load — DECIDED: Optimize for Common Case

Same approach as iOS with one optimization: if `lastDownloadedVersion` is
null (no updates have ever been downloaded), skip the organize +
`setServerBasePath` entirely and let Capacitor serve from `assets/public/`
directly. This avoids the double-load on first launch and every cold start
with no pending updates (the common case).

When a downloaded version exists, accept the double-load: organize the
bundle in `load()`, call `setServerBasePath()` (which auto-reloads). The
first page load from `assets/public/` is wasted but fast (local).

---

## Out of Scope for P0

- No `java.nio.file.*` usage or NIO desugaring setup.
- No `WorkManager`-based background download scheduling.
- No configurable startup timeout (keep fixed at 30s).

---

## Testing Strategy

The Cordova test suite had 68 test cases. The iOS Capacitor port currently
has zero functional tests. For the Android port:

- **Unit tests**: `AssetManifest`, `AssetBundle`, `WebAppConfiguration`,
  `RetryStrategy`, `BundleOrganizer` validation logic, `FileOps` (copy/move/delete),
  path validation (`urlPath` + `filePath`) — all testable without
  Android framework dependencies
- **Integration tests**: Full download + organize + serve + revert cycle —
  requires instrumented tests with a mock HTTP server
- **API 24 instrumented run**: Run integration tests on an Android 7.0
  emulator/device to verify API-24 compatibility (file operations and
  connectivity callbacks)
- **Manual testing**: Point a Capacitor app at a Meteor server, verify hot
  code push works end-to-end

The implementing agent should at minimum write the unit tests that don't
require Android framework mocking, plus one API-24 instrumented happy-path
download/switch test.

---

## Verification

After implementation, verify with:

```bash
cd android && ./gradlew clean build test
cd android && ./gradlew connectedAndroidTest
```

Update `verify:android` (or add a companion CI job) to run
`connectedAndroidTest` on an API-24 emulator. All existing tests must
continue to pass, and the build must succeed with no errors.

---

## Reference File Mapping

| Android Target | Primary Reference (iOS) | Secondary Reference (Cordova Android) |
|---------------|------------------------|--------------------------------------|
| `CapacitorMeteorWebAppPlugin.java` | `CapacitorMeteorWebAppPlugin.swift` | `WebAppLocalServer.java` (execute method) |
| `CapacitorMeteorWebApp.java` | `CapacitorMeteorWebApp.swift` | `WebAppLocalServer.java` (lifecycle + revert) |
| `WebAppConfiguration.java` | `WebAppConfiguration.swift` | `WebAppConfiguration.java` (nearly identical) |
| `AssetBundle.java` | `AssetBundle.swift` | `AssetBundle.java` |
| `Asset.java` | `Asset.swift` | inner class in `AssetBundle.java` |
| `AssetManifest.java` | `AssetManifest.swift` | `AssetManifest.java` |
| `AssetBundleManager.java` | `AssetBundleManager.swift` | `AssetBundleManager.java` |
| `AssetBundleDownloader.java` | `AssetBundleDownloader.swift` | `AssetBundleDownloader.java` |
| `BundleOrganizer.java` | `BundleOrganizer.swift` | (no equivalent) |
| `RetryStrategy.java` | `RetryStrategy.swift` | (no equivalent) |
| `NetworkReachabilityManager.java` | `NetworkReachabilityManager.swift` | (no equivalent) |
| `WebAppError.java` | `Errors.swift` | `WebAppException` in `DownloadFailureException.java` |
