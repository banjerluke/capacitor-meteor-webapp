Package.describe({
  name: 'banjerluke:capacitor-meteor-webapp-shim',
  version: '0.1.2',
  summary: 'No longer needed - @banjerluke/capacitor-meteor-webapp injects this directly.',
  git: 'https://github.com/banjerluke/capacitor-meteor-webapp',
  documentation: 'README.md',
});

Package.onUse(function (api) {
  api.versionsFrom('3.0');
  api.use('ecmascript');
  api.addFiles('webapp_local_server_capacitor.js', 'web.cordova');
});
