# Rspack behavior for external Cordova documents

Research date: 2026-07-31

## Question

With current Meteor and its standard Rspack integration, what actually works when Capacitor loads the remote `/__cordova/` document: initial startup, full reload/autoupdate, CSS refresh, and module HMR; and which behaviors are stable enough for bundler-neutral community documentation?

## Decision

Document external `web.cordova` development as supporting initial startup and Meteor's normal full-bundle refresh path, provided the Meteor process is actually building and serving the `web.cordova` architecture and the Capacitor plugin installs `window.WebAppLocalServer` in the external document.

Do not promise Rspack module HMR, React Fast Refresh, framework HMR, or CSS HMR for `web.cordova`. Meteor deliberately disables the Rspack development server, HMR entry script, WebSocket proxy, and hot-update proxy in native mode. JavaScript and CSS changes instead flow through the Cordova autoupdate path and refresh the whole document.

Keep the plugin's concise external-document documentation bundler-neutral. A detailed Rspack launch recipe is not yet suitable for the main README because Meteor has no documented web-only Cordova development command: the documented native commands also prepare and launch a Cordova shell, while the source-level `METEOR_CORDOVA_DISABLE=true` escape hatch is undocumented.

## Behavior matrix

| Behavior | Current result | Community documentation |
| --- | --- | --- |
| Load `/__cordova/` initially | Works when the running Meteor process includes the real `web.cordova` program | Supported, with a requirement that the development server actually serve `web.cordova` |
| JavaScript change | Rspack rebuilds the Cordova bundle; Meteor publishes a new `web.cordova` version; Cordova autoupdate requests the update and reloads the document | Describe as full refresh, not HMR |
| CSS change | Changes the Cordova program version and refreshable version, but Cordova still refreshes the whole document | Describe as full refresh; explicitly say there is no CSS-only hot swap |
| Rspack module HMR / framework fast refresh | Disabled in Meteor native mode | Unsupported; do not imply or advertise it |
| Plain `meteor run` plus `/__cordova/` | Under the current default `modern.webArchOnly`, `web.cordova` is omitted and `/__cordova/` can fall back to `web.browser` | Do not recommend as a Cordova development recipe |
| Force `web.cordova` into a non-native run with `--exclude-archs` | Produces a `web.cordova` shell without the Rspack application entry in the tested configuration | Not a supported workaround |

## Why initial startup works in native mode

Meteor recognizes a path whose first segment is `__cordova` and selects the `web.cordova` client program when that program exists. If it does not exist, request categorization falls through to a browser program, which is why a `200` response alone is not proof that the requested document is Cordova. See [`WebApp.categorizeRequest`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/packages/webapp/webapp_server.js#L153-L203).

Meteor's own Cordova HCP test starts `meteor run android`, fetches `/__cordova/index.html`, and verifies that it receives the Cordova runtime configuration. See [`tools/tests/cordova-hcp.js`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/tools/tests/cordova-hcp.js#L22-L42).

Capacitor defines `server.url` specifically to load an external live-reload server and warns against using it in production. This makes an external `/__cordova/` document a development mode, not another production/HCP serving mode. See the official [Capacitor configuration reference](https://capacitorjs.com/docs/config#schema).

The plugin still has one prerequisite beyond Meteor's serving behavior: it must inject `window.WebAppLocalServer` into the external main-frame document before Meteor's Cordova runtime needs it. That prerequisite is the subject of the separate remote-document compatibility change.

## Why Rspack HMR is disabled for native mode

Meteor classifies a run as native only when the command arguments contain `ios`, `ios-device`, `android`, or `android-device`. See [`isMeteorAppNative`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/packages/tools-core/lib/meteor.js#L243-L269).

Once native mode is active, the Rspack integration sets `RSPACK_NATIVE`, uses `runRspackBuild({ watch: true })` instead of the Rspack development server, and skips the development-server path that provides HMR. See [`rspack_plugin.js`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/packages/rspack/rspack_plugin.js#L177-L253).

The integration also omits the `/__rspack__/...` client entry script in native mode. See [`configureMeteorForRspack`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/packages/rspack/lib/config.js#L370-L387).

On the server, native mode disables the WebSocket and asset proxy that would otherwise forward `/ws`, `/__rspack__/`, hot-update files, chunks, and assets to the Rspack development server. See [`rspack_server.js`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/packages/rspack/rspack_server.js#L31-L99).

This behavior was intentional in Meteor 3.4.1. The merged change says the Rspack HMR proxy caused incorrect errors in Cordova development and therefore must be skipped. See Meteor [pull request #14226](https://github.com/meteor/meteor/pull/14226) and the [Meteor 3.4.1 changelog](https://docs.meteor.com/history#v341-2026-04-28).

The general Rspack documentation advertises Rspack-native HMR and CSS HMR, but those claims describe the Rspack development-server path. The native-mode guards above are more specific and exclude Cordova from that path. See the official [Rspack integration guide](https://docs.meteor.com/about/modern-build-stack/rspack-bundler-integration.html#dev-server).

## Why full refresh remains supported

Meteor's Cordova autoupdate client subscribes to the `web.cordova` version, calls `WebAppLocalServer.checkForUpdates()` when the full version changes, and reloads after `onNewVersionReady`. See [`autoupdate_cordova.js`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/packages/autoupdate/autoupdate_cordova.js#L1-L84).

Meteor's reload package calls `WebAppLocalServer.switchToPendingVersion()` before refreshing a Cordova document. See [`reload.js`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/packages/reload/reload.js#L278-L303).

Meteor's official autoupdate documentation is explicit that Cordova has no soft update and always fully refreshes when a change is detected. Its HCP troubleshooting guide separately states that CSS-only changes also reload the whole Cordova app. See [Autoupdate: Cordova Client](https://docs.meteor.com/packages/autoupdate#cordova-client) and [Cordova doesn't hot reload CSS separately](https://docs.meteor.com/troubleshooting/hot-code-push#cordova-doesnt-hot-reload-css-separately).

The Capacitor plugin's compatibility shim delegates those `WebAppLocalServer` calls to its existing native update and reload operations. External-document injection should reuse that exact shim rather than define different development semantics.

## Launch-command caveat

Current Meteor defaults `modern.webArchOnly` to active. For a non-native `meteor run`, Meteor automatically filters out both `web.browser.legacy` and `web.cordova`; an explicit `--exclude-archs` changes that filtering behavior. See [`filterWebArchs`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/tools/cli/commands.js#L269-L304) and the run setup that selects architectures in [`doRunCommand`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/tools/cli/commands.js#L536-L560).

The same source contains `METEOR_CORDOVA_DISABLE`, which suppresses construction of the Cordova runner while leaving the native command arguments and `web.cordova` build in place. It is not described in Meteor's CLI help or current documentation, so it should be treated as an internal implementation detail rather than a stable community interface. See [`commands.js`](https://github.com/meteor/meteor/blob/e0e2d0d805ee600a555ab6fe0f5448119a771bf3/tools/cli/commands.js#L556-L569).

A future first-party Meteor flag such as a documented “serve `web.cordova` without launching Cordova” mode would give the community a clean Rspack launch recipe. Until then, the plugin README should specify the required architecture and observable checks instead of canonizing the internal environment variable.

Useful checks are:

1. `/__cordova/manifest.json` returns JSON rather than the HTML app shell.
2. The runtime configuration in `/__cordova/index.html` contains an `autoupdate.versions["web.cordova"]` entry.
3. The manifest's `versionHmr` is absent or `null` in native mode; this is expected.
4. A source edit changes the manifest's top-level `version` and triggers a full refresh.

## Reproduction against Meteor 3.5

The source conclusions were reproduced with the official Meteor 3.5 React skeleton on macOS:

```sh
meteor create --react app
cd app
meteor add-platform ios
METEOR_CORDOVA_DISABLE=true meteor run ios \
  --port 4370 \
  --mobile-server http://localhost:4370
```

This served a real `web.cordova` index and JSON manifest. The manifest contained the Rspack-built application and `versionHmr: null`. Editing a React module changed the top-level version and Meteor logged `Client modified -- refreshing`. Editing CSS changed both the top-level and refreshable versions and produced the same full-refresh log.

For comparison, plain `meteor run` returned `200` for `/__cordova/index.html` but its runtime configuration only contained `web.browser`, and `/__cordova/manifest.json` returned HTML. An explicit `--exclude-archs web.browser.legacy` made the Cordova program appear in a non-native run, but its generated app module said `No link to Rspack Client App as served by HMR server` and the Cordova document had no `/__rspack__/` entry script. That is not a viable HMR recipe.

## Documentation wording

Suggested concise wording for the remote-document PR:

> When Capacitor is configured with an external `server.url`, the plugin installs the same `window.WebAppLocalServer` compatibility shim in each main-frame document. This supports development servers that serve Meteor's `web.cordova` architecture. Reload behavior is determined by the bundler: current Meteor Rspack Cordova development rebuilds and fully refreshes the document; it does not provide Rspack module or CSS HMR. Capacitor documents `server.url` as a live-reload development option and does not recommend it for production.

The detailed README follow-up should add the observable `web.cordova` checks above and should not call the feature “Rspack HMR.”
