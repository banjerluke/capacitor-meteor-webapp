# Capacitor Meteor WebApp Plugin Plan

## Overview
This plan outlines the implementation of a Capacitor plugin that replicates the functionality of the Meteor WebApp Cordova plugin to support hot code push for Meteor apps running in Capacitor.

## Key Requirements
- Download and serve new versions of the Meteor app
- Serve assets from local file system with proper URL mappings
- Support client-side routing (serve index.html for missing files) - MAYBE
- Robust update mechanism with rollback capabilities
- Recovery from faulty versions
- Uses the "Capacitor" way of doing things when possible
- JavaScript API compatibility with existing Cordova plugin via `window.WebAppLocalServer`
- iOS focus initially, Android as explicit Phase 2

## Architecture Overview

### Reference Implementation
This Capacitor plugin is based on the existing Cordova plugin located in [`reference-plugin-cordova/src/ios/`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/). The core algorithms, state management, and download logic will be preserved while adapting the integration layer for Capacitor.

**Key Reference Files:**
- [`WebAppLocalServer.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppLocalServer.swift) - Main plugin logic and HTTP server
- [`AssetBundleManager.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleManager.swift) - Download coordination
- [`AssetBundleDownloader.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleDownloader.swift) - Individual file downloads  
- [`WebAppConfiguration.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppConfiguration.swift) - Persistent state management
- [`AssetBundle.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundle.swift) - Bundle representation
- [`AssetManifest.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetManifest.swift) - Manifest parsing
- [`Asset.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/Asset.swift) - Asset model
- [`Errors.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/Errors.swift) - Error definitions
- [`Utility.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/Utility.swift) - Helper functions

### Core Components

#### 1. Asset Management System
- **AssetBundle**: Represents a version of the app with its files and manifest
- **AssetManifest**: Contains metadata about files, their hashes, and URL mappings
- **BundleOrganizer**: Reorganizes files according to URL mappings (strips query params, creates proper directory structure) **VersionState**: Manages state machine for version tracking and recovery

#### 2. Bundle Serving (iOS)
- Use Capacitor's native `setServerBasePath()` to change the directory Capacitor serves from
- No custom HTTP server needed - leverage Capacitor's built-in web serving
- Handle URL mappings by renaming/organizing files according to manifest structure
- Atomic bundle switching: `setServerBasePath()` + `webView.reload()` with semaphore protection

#### 3. Update System
- Native download implementation using URLSession
- MVP: Single ZIP download (like Capgo) with SHA-256 verification, then local unzip
- Future: Parallel per-file downloads with resumption support
- Hash validation for consistency
- File lock mechanism to prevent concurrent updates

### Key Differences from Cordova Implementation

#### Capacitor Integration
- Use Capacitor's native bridge instead of Cordova's CDVPlugin (replace [`METPlugin`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/METPlugin.h) inheritance)
- Leverage Capacitor's `setServerBasePath()` instead of custom HTTP server (replaces [`GCDWebServer` usage in WebAppLocalServer.swift](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppLocalServer.swift#L385-L411))
- Follow Capacitor plugin patterns and conventions
- Use Capacitor's configuration system and preferences (instead of [`commandDelegate?.settings`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppLocalServer.swift#L88-L97))

#### Bundle Management  
- Keep the same individual file download approach as Cordova (not ZIP-based like Capgo)
- Store bundles in `Library/NoCloud/meteor/<version>/` (iOS) - same as Cordova
- Use same version state management as [`WebAppConfiguration.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppConfiguration.swift)
- Organize files to match exact URL paths from manifest (same [`URLPathByRemovingQueryString` approach](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/Utility.swift#L12-L17))

#### JavaScript Interface
- Export TypeScript definitions for type safety
- Use Capacitor's event system for notifications
- Provide async/await API internally
- **Maintain compatibility** via `window.WebAppLocalServer` shim with original method names

## Implementation Plan

### Phase 1: Core Infrastructure & State Management

#### 1.1 Plugin Structure
```
src/
├── definitions.ts          # TypeScript interfaces
├── web.ts                 # Web implementation (warning stubs)
└── index.ts               # Main export + window.WebAppLocalServer shim

ios/Sources/CapacitorMeteorWebApp/
├── CapacitorMeteorWebAppPlugin.swift     # Main plugin class & bridge (replaces WebAppLocalServer.swift)
├── WebAppConfiguration.swift            # NSUserDefaults-based state (based on reference-plugin-cordova/src/ios/WebAppConfiguration.swift)
├── Bundle/                               # Model layer
│   ├── AssetBundle.swift                 # Bundle representation (based on reference-plugin-cordova/src/ios/AssetBundle.swift)
│   ├── AssetManifest.swift               # Manifest parsing (based on reference-plugin-cordova/src/ios/AssetManifest.swift)
│   ├── Asset.swift                       # Asset model (based on reference-plugin-cordova/src/ios/Asset.swift)
│   └── BundleOrganizer.swift             # File organization logic (new, extracts logic from AssetBundle)
├── Downloader/
│   ├── AssetBundleManager.swift          # Download coordinator (based on reference-plugin-cordova/src/ios/AssetBundleManager.swift)
│   └── AssetBundleDownloader.swift       # Individual download task (based on reference-plugin-cordova/src/ios/AssetBundleDownloader.swift)
└── Utils/
    ├── Errors.swift                      # Standard error definitions (based on reference-plugin-cordova/src/ios/Errors.swift)
    └── Utility.swift                     # Helper functions (based on reference-plugin-cordova/src/ios/Utility.swift)
```

#### 1.2 TypeScript Definitions
```typescript
export interface MeteorWebAppPlugin {
  checkForUpdates(): Promise<void>;
  startupDidComplete(): Promise<void>;
  getCurrentVersion(): Promise<{ version: string }>;
  isUpdateAvailable(): Promise<{ available: boolean }>;
  reload(): Promise<void>;
}

export interface UpdateAvailableEvent {
  version: string;
}

export interface UpdateCompleteEvent {
  version: string;
  isReady: boolean;
}

// Compatibility shim
declare global {
  interface Window {
    WebAppLocalServer: {
      onNewVersionReady(callback: Function): void;
      getNewCordovaVersion(): Promise<string | null>;
      switchToPendingVersion(): Promise<void>;
    }
  }
}
```

#### 1.3 Version State Management
Use NSUserDefaults/Capacitor preferences (following exact Cordova pattern from [`reference-plugin-cordova/src/ios/WebAppConfiguration.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppConfiguration.swift)):

```swift
// Persistent state keys (following Cordova pattern exactly)
private let lastDownloadedVersionKey = "MeteorWebAppLastDownloadedVersion"
private let lastKnownGoodVersionKey = "MeteorWebAppLastKnownGoodVersion"
private let blacklistedVersionsKey = "MeteorWebAppBlacklistedVersions"
private let lastSeenInitialVersionKey = "MeteorWebAppLastSeenInitialVersion"
private let versionsToRetryKey = "MeteorWebAppVersionsToRetry"
```

State management logic (following Cordova exactly):
1. On app launch: Check if startup completed within timeout, if not → revert to `lastKnownGoodVersion`
2. On successful startup: `startupDidComplete()` → set `lastKnownGoodVersion = current`
3. App Store update detection: Compare `lastSeenInitialVersion` to detect new app version

### Phase 2: Asset Management & File Organization

#### 2.1 Bundle Storage
- Create version-specific directories under `Library/NoCloud/meteor/<version>/`
- Use hard links for file reuse between versions (exactly like Cordova)
  - Automatic cleanup: when version directory removed, unused files deleted automatically
  - Shared files remain until no versions reference them
  - Performance benefit: no file copying overhead
- Handle partial downloads: `Downloading` → `PartialDownload` → version directory pattern
- Cleanup strategy: Remove old versions after successful startup (keep lastKnownGood)

#### 2.2 Manifest Processing & File Organization
- Parse JSON manifest with file hashes and URL mappings (based on [`AssetManifest.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetManifest.swift))
- **BundleOrganizer** logic: For each manifest entry `{ path: "file.js", url: "/path/file.js?hash=abc" }`
  - Strip query parameters from URL (using [`URLPathByRemovingQueryString` from Utility.swift](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/Utility.swift#L12-L17))
  - Create directory structure to match URL path
  - Place file at exact URL path location
- Handle duplicate URLs pointing to same file (copy/symlink as needed)

#### 2.3 Download System
- Parallel individual file downloads using URLSession (exactly like Cordova [`AssetBundleDownloader.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleDownloader.swift))
- Download asset manifest first, then missing individual files (like [`AssetBundleManager.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleManager.swift#L92-L181))
- ETag header validation against manifest hashes (like [`verifyResponse` method](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleDownloader.swift#L325-L340))
- Resumable downloads with partial completion tracking via `PartialDownload` directory (like [`moveExistingDownloadDirectoryIfNeeded`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleManager.swift#L186-L205))
- Background task support for 3-minute continuation when app backgrounded (like [`AssetBundleDownloader` init](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleDownloader.swift#L90-L103))
- Retry logic with exponential backoff and network reachability monitoring (using [`METRetryStrategy`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleDownloader.swift#L49-L54) and [`METNetworkReachabilityManager`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleDownloader.swift#L76-L79))
- Hard link existing files when possible, download only missing assets (like [`cachedAssetForAsset`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleManager.swift#L260-L275))

### Phase 3: Bundle Switching & Serving

#### 3.1 Bundle Directory Structure
Organized to match Meteor URL mappings:
```
Library/NoCloud/meteor/v1.2.3/
├── index.html
├── packages/
│   ├── meteor.js
│   └── webapp.js
├── client/
│   └── main.js
└── ...
```

#### 3.2 Atomic Bundle Switching
1. Download and organize new bundle completely
2. Use semaphore to prevent concurrent switches
3. Call `setServerBasePath(newBundlePath)`
4. Immediately call `webView.reload()`
5. Update state to `launching: newVersion`
6. Start startup timeout timer

#### 3.3 Client-Side Routing Support (Opt-in)
- For apps using pushState routing
- Implement via WKWebView `decidePolicyFor navigationAction` 
- If requested path not found on filesystem → serve `index.html`
- Document as optional feature to avoid unnecessary complexity

### Phase 4: Recovery & Error Handling

#### 4.1 Startup Timeout & Recovery
- Configurable timeout in Capacitor config (default 30s)
- Timer starts after `setServerBasePath()` + `reload()`
- If `startupDidComplete()` not called within timeout:
  - Revert to `lastKnownGood` bundle
  - Add failed version to blacklist
  - Clear `launching` state
  - Reload with safe bundle

#### 4.2 Cold-Start Crash Detection
- Track app lifecycle state in preferences (like [`startupTimer` in WebAppLocalServer.swift](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppLocalServer.swift#L208-L214))
- Detect abnormal termination (crash without proper app lifecycle)
- Treat as launch failure and trigger recovery (like [`revertToLastKnownGoodVersion`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppLocalServer.swift#L320-L340))

#### 4.3 Version Blacklisting
- Maintain blacklist in state JSON (like [`blacklistedVersions` and `versionsToRetry`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppConfiguration.swift#L114-L172) in WebAppConfiguration.swift)
- Check against blacklist before attempting to use any version (like [`shouldDownloadBundleForManifest`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppLocalServer.swift#L350-L369))
- Never attempt to download or switch to blacklisted versions

### Phase 5: JavaScript API Compatibility

#### 5.1 window.WebAppLocalServer Shim
```typescript
// In index.ts
import { registerPlugin } from '@capacitor/core';
const Native = registerPlugin<MeteorWebAppPlugin>('CapacitorMeteorWebApp');

window.WebAppLocalServer = {
  onNewVersionReady(callback) {
    Native.addListener('updateAvailable', callback);
  },
  
  async getNewCordovaVersion() {
    const update = await Native.isUpdateAvailable();
    if (update.available) {
      const current = await Native.getCurrentVersion();
      return current.version;
    }
    return null;
  },
  
  async switchToPendingVersion() {
    return Native.reload();
  }
};
```

#### 5.2 Event Compatibility
- Use original Cordova event names for seamless migration
- Events: `'updateAvailable'`, `'updateComplete'`, `'updateFailed'`
- Maintain synchronous API behavior where possible by caching values

### Phase 6: Testing & Validation

#### 6.1 Unit Testing
- XCTest for Swift components (VersionState, BundleOrganizer, etc.)
- Mock network responses and file system operations
- Test state machine transitions and error conditions

#### 6.2 Integration Testing
- Local test server serving Meteor manifests and ZIPs
- XCUITests for full update lifecycle
- Simulate app crashes and verify recovery
- Test blacklisting and rollback scenarios

## Key Technical Decisions

### Bundle Serving Approach
- **Decision**: Use Capacitor's `setServerBasePath()` + reload pattern
- **Rationale**: Simpler than custom HTTP server, leverages Capacitor's built-in capabilities
- **iOS Only**: Android requires different approach (TBD in Phase 2)

### Download Strategy
- **Decision**: Parallel individual file downloads with resumption (exactly like Cordova [`AssetBundleDownloader.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/AssetBundleDownloader.swift))
- **Rationale**: Must match what Meteor server provides, proven robust approach with excellent performance. The Cordova implementation handles all edge cases.

### File Organization Strategy
- **Decision**: Rename files to match URL paths exactly (strip query params)
- **Rationale**: Works with standard web serving, no custom routing logic needed

### State Management
- **Decision**: NSUserDefaults/Capacitor preferences (exactly like [`WebAppConfiguration.swift`](file:///Users/luke/Code/@strummachine/capacitor-meteor-webapp/reference-plugin-cordova/src/ios/WebAppConfiguration.swift))
- **Rationale**: Proven approach, handles all recovery scenarios including retry logic, leverages platform standards

### JavaScript Compatibility
- **Decision**: Full `window.WebAppLocalServer` API compatibility
- **Rationale**: Zero-migration path for existing Meteor Cordova apps

## Error Handling Strategy

### Error Codes & Types
```typescript
enum MeteorWebAppError {
  DOWNLOAD_FAILED = 'DOWNLOAD_FAILED',
  VALIDATION_FAILED = 'VALIDATION_FAILED', 
  BLACKLISTED_VERSION = 'BLACKLISTED_VERSION',
  STARTUP_TIMEOUT = 'STARTUP_TIMEOUT',
  FILE_SYSTEM_ERROR = 'FILE_SYSTEM_ERROR'
}
```

### Graceful Degradation
- Network failures → retry with exponential backoff
- Validation failures → revert to last known good
- File system errors → fallback to built-in bundle
- All errors logged with detailed context for debugging

## Android Implementation (Phase 2)

### Key Differences
- No `setServerBasePath()` equivalent
- Options:
  - Modify Capacitor's embedded server base path
  - Use `file://` URLs with WebViewClient interception
- File system: Use `context.getNoBackupFilesDir()/meteor/<version>/`
- Same state management and recovery logic

## Future Enhancements

### Post-MVP Features
- Delta updates (only download changed files)
- Background downloads using iOS background tasks  
- Bandwidth-aware downloading
- Source map support
- Update channels/rollout strategies

### Performance Optimizations
- Hard-link optimization for duplicate files
- Compression for smaller downloads
- Caching strategies for frequently accessed files

## Migration Path

### From Cordova Plugin
1. Install Capacitor plugin
2. Remove Cordova plugin
3. Code continues to work via `window.WebAppLocalServer` shim
4. Optionally migrate to native Capacitor API over time

### Configuration Migration
- Existing server URL configurations work unchanged
- Timeout values map to new config format
- No breaking changes in manifest format or server protocol
