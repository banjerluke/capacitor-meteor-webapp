# Capacitor Meteor WebApp Plugin

A Capacitor plugin that brings hot code push functionality to Meteor apps, allowing over-the-air updates without going through app stores. This is a direct port of the proven `cordova-plugin-meteor-webapp` for the Capacitor ecosystem.

## Features

- 🚀 **Hot Code Push**: Update your Meteor app instantly without app store approval
- 🔄 **Automatic Updates**: Downloads and applies updates seamlessly in the background
- 🛡️ **Rollback Protection**: Automatically reverts to the last known good version if updates fail
- 📱 **iOS Support**: Full native implementation with robust error handling
- 🔗 **Drop-in Compatibility**: Works with existing Meteor Cordova apps via `window.WebAppLocalServer` shim
- 🎯 **TypeScript Support**: Complete type definitions for modern development

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| iOS      | ✅ Implemented | Production ready |
| Android  | 📋 Planned | Coming in Phase 2 |
| Web      | ⚠️ Warning stubs | Not applicable for hot code push |

## Installation

```bash
npm install @strummachine/capacitor-meteor-webapp
npx cap sync
```

### iOS Configuration

<docgen-index>

- [`echo(...)`](#echo)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

### echo(...)

```typescript
export default {
  plugins: {
    CapacitorMeteorWebapp: {
      // Meteor server URL (required)
      serverUrl: 'https://your-meteor-app.com',
      
      // Startup timeout in seconds (default: 30)
      startupTimeout: 30,
      
      // Enable client-side routing support (default: false)
      enableRoutingSupport: false,
      
      // Check for updates on app launch (default: true)
      checkOnLaunch: true
    }
  }
};
```

## API Reference

### TypeScript Interface

---

  // Event listeners
  addListener(
    eventName: 'updateAvailable',
    listenerFunc: (event: UpdateAvailableEvent) => void,
  ): Promise<PluginListenerHandle>;

  addListener(
    eventName: 'updateComplete',
    listenerFunc: (event: UpdateCompleteEvent) => void,
  ): Promise<PluginListenerHandle>;

  removeAllListeners(): Promise<void>;
}

interface UpdateAvailableEvent {
  version: string;
}

interface UpdateCompleteEvent {
  version: string;
  isReady: boolean;
}
```

### Method Documentation

#### `checkForUpdates()`
Manually checks the Meteor server for new versions and downloads them if available.

```typescript
import { MeteorWebapp } from '@strummachine/capacitor-meteor-webapp';

await MeteorWebapp.checkForUpdates();
```

#### `startupDidComplete()`
**Critical**: Must be called after your app has successfully loaded to mark the current version as stable. This prevents rollback to previous versions.

```typescript
// In your main app component after successful initialization
await MeteorWebapp.startupDidComplete();
```

#### `getCurrentVersion()`
Returns the version string of the currently running Meteor bundle.

```typescript
const { version } = await MeteorWebapp.getCurrentVersion();
console.log(`Running version: ${version}`);
```

#### `isUpdateAvailable()`
Checks if a downloaded update is ready to be applied.

```typescript
const { available } = await MeteorWebapp.isUpdateAvailable();
if (available) {
  // Prompt user or automatically reload
}
```

#### `reload()`
Restarts the app with the latest downloaded version.

```typescript
await MeteorWebapp.reload();
```

### Event System

Listen for update lifecycle events:

```typescript
// Listen for when new versions become available
const updateListener = await MeteorWebapp.addListener(
  'updateAvailable', 
  (event) => {
    console.log(`New version available: ${event.version}`);
    // Show update prompt to user
  }
);

// Listen for when updates complete
const completeListener = await MeteorWebapp.addListener(
  'updateComplete',
  (event) => {
    console.log(`Update to ${event.version} completed. Ready: ${event.isReady}`);
  }
);

// Clean up listeners
await MeteorWebapp.removeAllListeners();
```

## Cordova Compatibility Layer

For seamless migration from `cordova-plugin-meteor-webapp`, this plugin provides full API compatibility via `window.WebAppLocalServer`:

```javascript
// Existing Cordova code continues to work unchanged
window.WebAppLocalServer.onNewVersionReady(function(event) {
  console.log('New version ready:', event.version);
});

// Check for updates
const newVersion = await window.WebAppLocalServer.getNewCordovaVersion();
if (newVersion) {
  // Apply the update
  await window.WebAppLocalServer.switchToPendingVersion();
}
```

### Compatibility API Reference

| Cordova Method | Description | Capacitor Equivalent |
|---------------|-------------|---------------------|
| `onNewVersionReady(callback)` | Listen for available updates | `addListener('updateAvailable', callback)` |
| `getNewCordovaVersion()` | Get version of available update | `isUpdateAvailable()` + `getCurrentVersion()` |
| `switchToPendingVersion()` | Apply downloaded update | `reload()` |

## Usage Examples

### Basic Setup

```typescript
import { MeteorWebapp } from '@strummachine/capacitor-meteor-webapp';

export class App {
  async ngOnInit() {
    // Mark startup as successful
    await MeteorWebapp.startupDidComplete();
    
    // Check for updates on launch
    await MeteorWebapp.checkForUpdates();
    
    // Listen for available updates
    await MeteorWebapp.addListener('updateAvailable', async (event) => {
      const shouldUpdate = confirm(`Update to ${event.version} is available. Apply now?`);
      if (shouldUpdate) {
        await MeteorWebapp.reload();
      }
    });
  }
}
```

### Advanced Update Flow

```typescript
import { MeteorWebapp } from '@strummachine/capacitor-meteor-webapp';

class UpdateManager {
  private isUpdating = false;

  async initialize() {
    // Critical: Mark successful startup
    await MeteorWebapp.startupDidComplete();
    
    // Set up update listeners
    await MeteorWebapp.addListener('updateAvailable', this.handleUpdateAvailable);
    await MeteorWebapp.addListener('updateComplete', this.handleUpdateComplete);
    
    // Check for updates periodically
    setInterval(() => this.checkForUpdates(), 5 * 60 * 1000); // Every 5 minutes
  }

  async checkForUpdates() {
    if (this.isUpdating) return;
    
    try {
      await MeteorWebapp.checkForUpdates();
    } catch (error) {
      console.error('Update check failed:', error);
    }
  }

  handleUpdateAvailable = async (event: UpdateAvailableEvent) => {
    // Show non-intrusive update notification
    this.showUpdateBanner(event.version);
  };

  async applyUpdate() {
    if (this.isUpdating) return;
    
    this.isUpdating = true;
    this.showUpdateProgress();
    
    try {
      await MeteorWebapp.reload();
    } catch (error) {
      console.error('Update failed:', error);
      this.hideUpdateProgress();
      this.isUpdating = false;
    }
  }

  private showUpdateBanner(version: string) {
    // Implementation specific to your UI framework
  }

  private showUpdateProgress() {
    // Show loading indicator
  }
}
```

### React Hook Example

```typescript
import { useEffect, useState } from 'react';
import { MeteorWebapp } from '@strummachine/capacitor-meteor-webapp';

export function useHotCodePush() {
  const [updateAvailable, setUpdateAvailable] = useState(false);
  const [currentVersion, setCurrentVersion] = useState('');

  useEffect(() => {
    let mounted = true;

    async function initialize() {
      // Mark startup complete
      await MeteorWebapp.startupDidComplete();
      
      // Get current version
      const { version } = await MeteorWebapp.getCurrentVersion();
      if (mounted) setCurrentVersion(version);
      
      // Listen for updates
      await MeteorWebapp.addListener('updateAvailable', () => {
        if (mounted) setUpdateAvailable(true);
      });
      
      // Check for updates
      await MeteorWebapp.checkForUpdates();
    }

    initialize().catch(console.error);

    return () => {
      mounted = false;
      MeteorWebapp.removeAllListeners();
    };
  }, []);

  const applyUpdate = async () => {
    setUpdateAvailable(false);
    await MeteorWebapp.reload();
  };

  return {
    updateAvailable,
    currentVersion,
    applyUpdate,
  };
}
```

## Hot Code Push Workflow

### 1. Update Detection
```
App Launch → checkForUpdates() → Meteor Server → Download Manifest → Compare Versions
```

### 2. Download Process
```
New Version Detected → Download Assets → Verify Hashes → Organize Files → Trigger 'updateAvailable'
```

### 3. Update Application
```
User Confirms → reload() → Switch Bundle Path → Reload WebView → startupDidComplete()
```

### 4. Rollback Protection
```
Startup Timeout → Revert to Last Known Good → Blacklist Failed Version → Retry Logic
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

### Step 1: Install Capacitor Plugin

```bash
# Remove Cordova plugin
cordova plugin remove cordova-plugin-meteor-webapp

# Install Capacitor plugin  
npm install @strummachine/capacitor-meteor-webapp
npx cap sync
```

### Step 2: Update Configuration

Move configuration from `config.xml` to `capacitor.config.ts`:

```xml
<!-- OLD: config.xml -->
<preference name="WebAppServerUrl" value="https://your-meteor-app.com" />
<preference name="WebAppStartupTimeout" value="30000" />
```

```typescript
// NEW: capacitor.config.ts
export default {
  plugins: {
    CapacitorMeteorWebapp: {
      serverUrl: 'https://your-meteor-app.com',
      startupTimeout: 30
    }
  }
};
```

### Step 3: Code Migration (Optional)

Your existing code continues to work via the compatibility layer:

```javascript
// This continues to work unchanged
window.WebAppLocalServer.onNewVersionReady(function(event) {
  // Handle update
});
```

Optionally migrate to the modern TypeScript API:

```typescript
// NEW: Modern Capacitor API
import { MeteorWebapp } from '@strummachine/capacitor-meteor-webapp';

await MeteorWebapp.addListener('updateAvailable', (event) => {
  // Handle update
});
```

## Troubleshooting

### Common Issues

#### Updates Not Downloading
- Verify `serverUrl` configuration is correct
- Check network connectivity
- Ensure Meteor server is serving the manifest at `/__cordova/manifest.json`
- Check browser console for error messages

#### App Keeps Reverting to Old Version
- Make sure `startupDidComplete()` is called after successful app initialization
- Check if the startup timeout is too short for your app
- Verify that the new version doesn't have JavaScript errors preventing startup

#### Black Screen After Update
- Usually indicates a startup timeout due to JavaScript errors
- Check device logs for error details
- The plugin should automatically revert to the previous version

#### Version Not Updating
- Check if the version is blacklisted due to previous failures
- Clear app data to reset plugin state
- Verify the manifest contains a different version string

### Debug Configuration

Enable detailed logging in development:

```typescript
export default {
  plugins: {
    CapacitorMeteorWebapp: {
      serverUrl: 'https://your-meteor-app.com',
      debugLogging: true // Enable detailed logs
    }
  }
};
```

### Reset Plugin State

To clear all downloaded versions and reset plugin state:

```typescript
// This will clear all cached versions and force re-download
await MeteorWebapp.resetPlugin();
```

### File Storage Locations

The plugin stores files in platform-specific locations:

#### iOS
```
Library/NoCloud/meteor/
├── v1.2.3/          # Version-specific bundle directory
│   ├── index.html   # Organized to match URL structure
│   ├── packages/
│   └── client/
└── PartialDownload/ # Temporary download location
```

## Error Handling

The plugin defines specific error types for different failure scenarios:

```typescript
enum MeteorWebappError {
  DOWNLOAD_FAILED = 'DOWNLOAD_FAILED',
  VALIDATION_FAILED = 'VALIDATION_FAILED',
  BLACKLISTED_VERSION = 'BLACKLISTED_VERSION',
  STARTUP_TIMEOUT = 'STARTUP_TIMEOUT',
  FILE_SYSTEM_ERROR = 'FILE_SYSTEM_ERROR'
}
```

Handle errors gracefully:

```typescript
try {
  await MeteorWebapp.checkForUpdates();
} catch (error) {
  if (error.code === 'DOWNLOAD_FAILED') {
    // Handle network issues
  } else if (error.code === 'BLACKLISTED_VERSION') {
    // Version was previously problematic
  }
}
```

## Integration with Meteor Deployment

### Server Requirements

Your Meteor server must serve the manifest at `/__cordova/manifest.json`. This happens automatically when you:

1. Add the `webapp` package (included by default)
2. Build your app with `meteor build --server=https://your-server.com`

### Deployment Workflow

```bash
# 1. Build your Meteor app
meteor build --server=https://your-meteor-app.com ../builds/

# 2. Deploy to your server
# Your deployment process here...

# 3. App automatically detects and downloads the new version
# No app store submission required!
```

### Version Strategy

Consider your versioning strategy:

```javascript
// In your Meteor app's package.json or version file
{
  "version": "1.2.3-20240815.1430" // Include timestamp for uniqueness
}
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

This plugin is based on the excellent `cordova-plugin-meteor-webapp` by the Meteor Development Group, adapted for the Capacitor ecosystem while maintaining full compatibility.
