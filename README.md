# Capacitor Meteor WebApp Plugin

A Capacitor plugin that brings hot code push functionality to Meteor apps, allowing over-the-air updates without going through app stores. This is a direct port of the proven `cordova-plugin-meteor-webapp` for the Capacitor ecosystem.

Works with existing Meteor Cordova apps by shimming the `window.WebAppLocalServer` API that `cordova-plugin-meteor-webapp` provides and Meteor assumes is present. **You don't need to change your Meteor app code,** just the build process.

### WARNING: Still in development. Theoretically complete, with full test suite, but not tested in production yet.
> **Still in development.** Theoretically complete, with full test suite, but not tested in production yet.

Most of the coding, review, and test-writing was done by Opus 4.6 and Codex 5.3, with heavy review and cross-checking through the process. I took my time because I'm making this for my mature production app, with real users that will be burned if I ship broken code, but I haven't reviewed much of the code myself.

For a deep dive into how the plugin works -- update lifecycle, asset bundle system, version management, failure recovery, and the Cordova compatibility shim -- see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## Features

This plugin inherits the nifty functionality of [Meteor's `cordova-plugin-meteor-webapp`](https://github.com/meteor/cordova-plugin-meteor-webapp):

- **Hot Code Push** -- Update your Meteor app instantly without app store approval
- **Background Downloads** -- Only changed assets are downloaded; partial downloads are resumed automatically
- **Automatic Rollback** -- If an update fails to start, the plugin reverts to the last known good version; failed versions get one retry before being permanently blacklisted
- **Cordova Compatibility** -- The `window.WebAppLocalServer` API is shimmed automatically, so Meteor's `autoupdate` package works without changes
- **iOS & Android** -- Full native implementations (Swift & Java) with closely aligned behavior

## Capacitor Setup

> Note: This section is subject to change when Meteor (hopefully) adopts official support for Capacitor in the future.

We'll assume you're using Meteor v3 -- earlier versions may not work due to being stuck on Node 14 (untested).

Note: You **must** have at least one Cordova platform added to your Meteor project. Run either `meteor add-platform ios` or `meteor add-platform android`, then run `meteor run` at least once before continuing.

### Installation

In your Meteor project directory:

```bash
# Install Capacitor
meteor npm i @capacitor/core
meteor npm i -D @capacitor/cli

# Install iOS and/or Android platforms for Capacitor
meteor npm i @capacitor/ios
meteor npm i @capacitor/android

# Install Capacitor plugin
meteor npm install @banjerluke/capacitor-meteor-webapp

# Init Capacitor
# Enter your name and bundle ID as in mobile-config.js
# 👉 When asked for a web asset directory, enter capacitor/www-dist
npx cap init

```

Now you should edit `capacitor.config.json` or `capacitor.config.ts` file -- the latter will be created if TypeScript is used in your project. Add `path` entries under `ios` and `android` to keep the native projects in the `capacitor` directory, next to `www-dist`:

```json
{
  "appId": "com.myapp.id",
  "appName": "My App Name",
  "webDir": "capacitor/www-dist",
  "ios": {
    "path": "capacitor/ios"
  },
  "android": {
    "path": "capacitor/android"
  }
}
```

You'll need to add the following to `.meteorignore` to prevent Meteor from trying to build files in the `capacitor` directory:

```
/capacitor
```

Now we can create the native Xcode and/or Android projects:

```bash
npx cap add ios
npx cap add android
```

Ignore the warning that says `sync could not run--missing capacitor/www-dist directory.` That will be completed as part of the build script.

At this point, everything should be set up and ready to run the build script.

### Building/Syncing Capacitor

See `build-and-sync-capacitor.sh` in this repository for a build script that you can use and modify. It has a bunch of comments to help you understand what's going on. In brief, it:

- Starts a local dev server to get a valid MongoDB instance running
- Sets env variables and then builds the production server
- Copies build files from the `web.cordova` platform to the `capacitor/www-dist` directory
- Builds and runs the production server (requires a valid MongoDB instance, hence the local dev server)
- Fetches `__cordova/index.html` and `__cordova/manifest.json` (renamed to `program.json`) from the production server
- Kills running servers
- Runs `npx cap sync` to sync contents of `www-dist` and plugins in `package.json` to native projects
- Runs `npx cap open ios` to open the iOS project in Xcode

> Note that if your server has other boot-time requirements, you may need to adapt this script. For example, the author's app fails to boot unless `STRIPE_API_KEY` is set, so he added `export STRIPE_API_KEY="pk_test_asdf"` after the `export ROOT_URL` line to get it booting.

## Cordova Compatibility

The plugin automatically shims `window.WebAppLocalServer` so that Meteor's runtime (and your existing app code) works without changes. The one exception is `localFileSystemUrl()`, which is not supported since Capacitor doesn't embed a local web server. Use [@capacitor/filesystem](https://capacitorjs.com/docs/apis/filesystem) if you need local file access.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full compatibility mapping table and details on how the shim is injected.

## Version & Failure Management

The plugin tracks version state across launches and automatically handles failures: if `startupDidComplete()` isn't called within 30 seconds of switching to a new version, the plugin reverts to the last known good version. A failed version is retried once, then permanently blacklisted if it fails again. The startup timer is paused while the app is backgrounded and resumes on foreground. When the app is updated through the App Store / Google Play, all downloaded versions are wiped so the new bundled assets take precedence.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full version state machine, blacklisting logic, and startup timer behavior.

## Running Tests

### iOS

The iOS tests use Swift Package Manager and run on the iOS Simulator via `xcodebuild`. They cover unit tests for all core components and integration tests using a `MockURLProtocol`-based network layer.

```bash
xcodebuild test \
  -scheme CapacitorMeteorWebApp \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.2' \
  -only-testing:CapacitorMeteorWebAppPluginTests -quiet
```

If that simulator isn't available, list yours with `xcrun simctl list devices available | grep iPhone` and substitute the name.

### Android

Android has both local unit tests (JVM) and instrumented tests (require emulator/device). They use JUnit 4 and OkHttp's `MockWebServer`.

```bash
# Unit tests (JVM — no emulator needed)
cd android && ./gradlew test

# Instrumented tests (requires a running emulator or connected device)
cd android && ./gradlew connectedAndroidTest
```

## License & Acknowledgments

This plugin is released under the MIT License. See [LICENSE](LICENSE) for details.

It is closely adapted from [`cordova-plugin-meteor-webapp`](https://github.com/meteor/meteor/tree/devel/npm-packages/cordova-plugin-meteor-webapp) by Meteor Software. My aim was to reuse as much tried-and-tested code and maintain as much compatibility as possible, while taking advantage of some opportunities for simplicity that Capacitor offers (i.e. not having to bundle a local web server).

This plugin would not have been created without the big head-start provided by [@nachocodoner](https://github.com/nachocodoner)'s [post on the Meteor forums](https://forums.meteor.com/t/building-capacitor-mobile-app-from-meteor-react/63560/4). His post gave an overview of how he was able to get Capacitor working with Meteor, and it had enough detail for me (well, Claude initially) to reproduce his workflow and get the ball rolling.
