Package.describe({
  name: 'banjerluke:capacitor-meteor-webapp-shim',
  version: '0.1.0',
  summary: 'Adds compatibility for Meteor and Capacitor when using the @banjerluke/capacitor-meteor-webapp Capacitor plugin.',
  git: '',
  documentation: 'README.md'
});

Package.onUse(function (api) {
  api.versionsFrom('3.3.1');
  api.use('ecmascript');
  api.addFiles('webapp_local_server_capacitor.js', 'web.cordova');
});
