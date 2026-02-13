# Capacitor Meteor WebApp Plugin

A Capacitor plugin that brings hot code push functionality to Meteor apps, allowing over-the-air updates without going through app stores. This is a direct port of the proven `cordova-plugin-meteor-webapp` for the Capacitor ecosystem.

Works with existing Meteor Cordova apps by shimming the `window.WebAppLocalServer` API that `cordova-plugin-meteor-webapp` provides and Meteor assumes is present.

# WARNING 🚨 Work in progress. No tests have been written yet. No Android support yet. Not tested in production. Use at your own risk.

I've had both Opus 4.6 and Codex 5.3 do multiple in-depth parity audits against `cordova-plugin-meteor-webapp` to ensure that the new iOS code (which is the "hard part" compared to Android) behaves correctly. I'm almost ready to start testing it in the beta version of my app and start working on the Android version. But yeah... you have been warned!

## Features

This plugin inherits the nifty functionality of [Meteor's `cordova-plugin-meteor-webapp`](https://github.com/meteor/cordova-plugin-meteor-webapp):

- 🚀 **Hot Code Push**: Update your Meteor app instantly without app store approval
- 🔄 **Automatic Updates**: Downloads and applies updates seamlessly in the background
- 🛡️ **Rollback Protection**: Automatically reverts to the last known good version if updates fail
- 📱 **iOS Support**: Full native implementation with robust error handling
- 📱 ~~**Android Support**~~: MISSING. Totally doable, just haven't gotten around to it yet.

## Installation

We'll assume you're using Meteor v3 -- earlier versions may not work due to being stuck on Node 14 (untested).

Note: You **must** have at least one Cordova platform added to your Meteor project. Run either `meteor add-platform ios` or `meteor add-platform android`, then run `meteor run` at least once before continuing.

In your Meteor project directory:

```bash
# Install Capacitor
meteor npm i @capacitor/core
meteor npm i -D @capacitor/cli

# Install iOS and/or Android platforms for Capacitor
meteor npm i @capacitor/ios
meteor npm i @capacitor/android   # Note, this plugin does not support Android yet!

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
npx cap add android  # again, this plugin doesn't yet support Android
```

Ignore the warning that says `sync could not run--missing capacitor/www-dist directory.` That will be completed as part of the build script.

At this point, everything should be set up and ready to run the build script.

## Building/Syncing Capacitor

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

As part of "organizing" the bundle (putting files where the app expects them to be served), the native code installs a shim for the `WebAppLocalServer` object on `window` that is provided by Cordova's `cordova-plugin-meteor-webapp`, bridging the old API to the new Capacitor plugin.

The only exception is `WebAppLocalServer.localFileSystemUrl()`. Since we're no longer embedding our own local web server, we can't hijack `/local-filesystem` URLs to serve local files. If you need this functionality, I recommend looking into [@capacitor/filesystem](https://capacitorjs.com/docs/apis/filesystem) instead.

Otherwise, the Meteor runtime will interact with `WebAppLocalServer` as usual and it should Just Work™.

## Version & Failure Management

As with `cordova-plugin-meteor-webapp`, the plugin keeps track of several version states:

- **Current Version**: The version currently running
- **Last Known Good Version**: The last version that successfully started
- **Downloaded Version**: A new version ready to be applied
- **Blacklisted Versions**: Versions that failed to start and should not be retried

The plugin automatically handles failures:

1. **Startup Timeout**: If `startupDidComplete()` isn't called within the timeout period, the app reverts to the last known good version
2. **Crash Detection**: Cold start crashes are detected and trigger automatic rollback
3. **Version Blacklisting**: Failed versions are blacklisted to prevent retry loops

## License & Acknowledgments

This plugin is released under the MIT License. See [LICENSE](LICENSE) for details.

It is closely adapted from [`cordova-plugin-meteor-webapp`](https://github.com/meteor/meteor/tree/devel/npm-packages/cordova-plugin-meteor-webapp) by Meteor Software. My aim was to reuse as much tried-and-tested code and maintain as much compatibility as possible, while taking advantage of some opportunities for simplicity that Capacitor offers (i.e. not having to bundle a local web server).

This plugin would not have been created without the big head-start provided by [@nachocodoner](https://github.com/nachocodoner)'s [post on the Meteor forums](https://forums.meteor.com/t/building-capacitor-mobile-app-from-meteor-react/63560/4). His post gave an overview of how he was able to get Capacitor working with Meteor, and it had enough detail for me (well, Claude initially) to reproduce his workflow and get the ball rolling.
