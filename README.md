# Capacitor Meteor WebApp Plugin

A Capacitor plugin that brings hot code push functionality to Meteor apps, allowing over-the-air updates without going through app stores. This is a direct port of the proven `cordova-plugin-meteor-webapp` for the Capacitor ecosystem.

Works with existing Meteor Cordova apps after also installing the `banjerluke:capacitor-meteor-webapp-shim` Meteor package to shim `WebAppLocalServer` on `window`.

## Features

This plugin inherits the nifty functionality of [Meteor's `cordova-plugin-meteor-webapp`](https://github.com/meteor/cordova-plugin-meteor-webapp):

- 🚀 **Hot Code Push**: Update your Meteor app instantly without app store approval
- 🔄 **Automatic Updates**: Downloads and applies updates seamlessly in the background
- 🛡️ **Rollback Protection**: Automatically reverts to the last known good version if updates fail
- 📱 **iOS Support**: Full native implementation with robust error handling
- 📱 ~~**Android Support**~~: MISSING. Totally doable, just haven't gotten around to it yet.

## Installation

```bash
npm install @banjerluke/capacitor-meteor-webapp
npx cap sync
```

## Cordova Compatibility Layer

For seamless migration from `cordova-plugin-meteor-webapp`, this plugin provides full API compatibility via `window.WebAppLocalServer` when you install the "shim" Meteor package:

```sh
meteor add @banjerluke:capacitor-meteor-webapp-shim
```

## Version Management

The plugin maintains several version states:

- **Current Version**: The version currently running
- **Last Known Good**: The last version that successfully started
- **Downloaded Version**: A new version ready to be applied
- **Blacklisted Versions**: Versions that failed to start and should not be retried

### Recovery Mechanism

The plugin automatically handles failures:

1. **Startup Timeout**: If `startupDidComplete()` isn't called within the timeout period, the app reverts to the last known good version
2. **Crash Detection**: Cold start crashes are detected and trigger automatic rollback
3. **Version Blacklisting**: Failed versions are blacklisted to prevent retry loops

## Migration from Cordova

```bash
# Remove Cordova plugin
cordova plugin remove cordova-plugin-meteor-webapp

# Install Capacitor plugin
npm install @banjerluke/capacitor-meteor-webapp
npx cap sync
```

Your existing code continues to work via the compatibility layer:

```javascript
// This continues to work unchanged
window.WebAppLocalServer.onNewVersionReady(function (event) {
  // Handle update
});
```

Optionally migrate to the modern TypeScript API:

```typescript
// NEW: Modern Capacitor API
import { MeteorWebApp } from '@banjerluke/capacitor-meteor-webapp';

await MeteorWebApp.addListener('updateAvailable', (event) => {
  // Handle update
});
```

<docgen-index>

- [`startupDidComplete()`](#startupdidcomplete)
- [`getCurrentVersion()`](#getcurrentversion)
- [`isUpdateAvailable()`](#isupdateavailable)
- [`reload()`](#reload)
- [`addListener('updateAvailable', ...)`](#addlistenerupdateavailable-)
- [`addListener('updateComplete', ...)`](#addlistenerupdatecomplete-)
- [`removeAllListeners()`](#removealllisteners)
- [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### startupDidComplete()

```typescript
startupDidComplete() => Promise<void>
```

Signal that the app startup has completed

---

### getCurrentVersion()

```typescript
getCurrentVersion() => Promise<{ version: string; }>
```

Get the current version of the app

**Returns:** <code>Promise&lt;{ version: string; }&gt;</code>

---

### isUpdateAvailable()

```typescript
isUpdateAvailable() => Promise<{ available: boolean; }>
```

Check if an update is available

**Returns:** <code>Promise&lt;{ available: boolean; }&gt;</code>

---

### reload()

```typescript
reload() => Promise<void>
```

Reload the app with the latest version

---

### addListener('updateAvailable', ...)

```typescript
addListener(eventName: 'updateAvailable', listenerFunc: (event: UpdateAvailableEvent) => void) => Promise<PluginListenerHandle>
```

Listen for update available events

| Param              | Type                                                                                      |
| ------------------ | ----------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'updateAvailable'</code>                                                            |
| **`listenerFunc`** | <code>(event: <a href="#updateavailableevent">UpdateAvailableEvent</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

---

### addListener('updateComplete', ...)

```typescript
addListener(eventName: 'updateComplete', listenerFunc: (event: UpdateCompleteEvent) => void) => Promise<PluginListenerHandle>
```

Listen for update complete events

| Param              | Type                                                                                    |
| ------------------ | --------------------------------------------------------------------------------------- |
| **`eventName`**    | <code>'updateComplete'</code>                                                           |
| **`listenerFunc`** | <code>(event: <a href="#updatecompleteevent">UpdateCompleteEvent</a>) =&gt; void</code> |

**Returns:** <code>Promise&lt;<a href="#pluginlistenerhandle">PluginListenerHandle</a>&gt;</code>

---

### removeAllListeners()

```typescript
removeAllListeners() => Promise<void>
```

Remove all listeners

---

### Interfaces

#### PluginListenerHandle

| Prop         | Type                                      |
| ------------ | ----------------------------------------- |
| **`remove`** | <code>() =&gt; Promise&lt;void&gt;</code> |

#### UpdateAvailableEvent

| Prop          | Type                |
| ------------- | ------------------- |
| **`version`** | <code>string</code> |

#### UpdateCompleteEvent

| Prop          | Type                 |
| ------------- | -------------------- |
| **`version`** | <code>string</code>  |
| **`isReady`** | <code>boolean</code> |

</docgen-api>

## License & Acknowledgments

This plugin is released under the MIT License. See [LICENSE](LICENSE) for details.

It is closely adapted from `cordova-plugin-meteor-webapp` by Meteor Software. My aim was to reuse as much tried-and-tested code and maintain as much compatibility as possible, while taking advantage of some opportunities for simplicity that Capacitor offers (i.e. not having to bundle a local web server).
