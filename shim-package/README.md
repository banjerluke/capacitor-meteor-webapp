# Shim for @banjerluke/capacitor-meteor-webapp

This Meteor package must be installed when using the `@banjerluke/capacitor-meteor-webapp` Capacitor plugin to add Capacitor support to Meteor apps. It adds a shim for the `WebAppLocalServer` object on `window`, usually provided by Cordova's `cordova-plugin-meteor-webapp`, and proxies methods on it to the Capacitor plugin.

See [https://github.com/banjerluke/capacitor-meteor-webapp](https://github.com/banjerluke/capacitor-meteor-webapp) for more information.
