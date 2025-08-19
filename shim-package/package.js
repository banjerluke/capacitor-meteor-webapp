Package.describe({
  name: 'banjerluke:capacitor-meteor-webapp-shim',
  version: '0.1.0',
  summary: 'Shims WebAppLocalServer to use the @banjerluke/capacitor-meteor-webapp plugin.',
  git: 'https://github.com/banjerluke/capacitor-meteor-webapp',
  documentation: 'README.md',
});

Package.onUse(function (api) {
  api.versionsFrom('3.3.1');
  api.use('ecmascript');
  api.addFiles('webapp_local_server_capacitor.js', 'web.cordova');
});
