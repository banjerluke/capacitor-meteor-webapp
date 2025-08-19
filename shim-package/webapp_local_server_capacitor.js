import { CapacitorMeteorWebApp } from '@banjerluke/capacitor-meteor-webapp';

/**
 * WebAppLocalServer compatibility shim (replaces the one installed by cordova-plugin-meteor-webapp)
 * @see https://github.com/meteor/meteor/blob/devel/npm-packages/cordova-plugin-meteor-webapp/www/webapp_local_server.js
 **/
window.WebAppLocalServer = {
  startupDidComplete(callback) {
    CapacitorMeteorWebApp.startupDidComplete()
      .then(() => {
        if (callback) callback();
      })
      .catch((error) => {
        console.error('WebAppLocalServer.startupDidComplete() failed:', error);
      });
  },

  checkForUpdates(callback) {
    CapacitorMeteorWebApp.checkForUpdates()
      .then(() => {
        if (callback) callback();
      })
      .catch((error) => {
        console.error('WebAppLocalServer.checkForUpdates() failed:', error);
      });
  },

  onNewVersionReady(callback) {
    CapacitorMeteorWebApp.addListener('updateAvailable', callback);
  },

  switchToPendingVersion(callback, errorCallback) {
    CapacitorMeteorWebApp.reload()
      .then(() => {
        if (callback) callback();
      })
      .catch((error) => {
        console.error('switchToPendingVersion failed:', error);
        if (typeof errorCallback === 'function') errorCallback(error);
      });
  },

  onError(callback) {
    CapacitorMeteorWebApp.addListener('error', (event) => {
      // Convert error message to a proper error object
      const error = new Error(event.message || 'Unknown CapacitorMeteorWebApp error');
      callback(error);
    });
  },

  // NOTE: This hooked into the custom GCDWebServer class that cordova-plugin-meteor-webapp uses
  // to serve files from the local filesystem. Best to switch to @capacitor/filesystem plugin I think.
  localFileSystemUrl(_fileUrl) {
    throw new Error('Local filesystem URLs not supported by Capacitor');
  },
};
