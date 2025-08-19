# ~~Shim for @banjerluke/capacitor-meteor-webapp~~ NO LONGER NEEDED

~~This Meteor package must be installed when using the `@banjerluke/capacitor-meteor-webapp` Capacitor plugin to add Capacitor support to Meteor apps. It adds a shim for the `WebAppLocalServer` object on `window`, usually provided by Cordova's `cordova-plugin-meteor-webapp`, and proxies methods on it to the Capacitor plugin.

The [@banjerluke/capacitor-meteor-webapp](https://github.com/banjerluke/capacitor-meteor-webapp) Capacitor plugin now injects this code directly into the `index.html` file, bypassing the need for this Meteor package.
