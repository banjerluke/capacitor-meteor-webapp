import _ from 'underscore';

exports.defineAutoTests = function () {
  describe('WebAppLocalServer', function () {
    // IMPORTANT: As you know, we're no longer embedding our own web server, but relying on Capacitor to serve up files based on setServerBasePath.
    // As a result, some of the "should serve" tests may no longer be relevant, but we should try to implement them if they make sense.
    describe('the local server', function () {
      it('should serve index.html for /', function (done) {
        fetchFromLocalServer('/').then(expectIndexPageToBeServed(done));
      });

      it('should serve assets based on the URL in the manifest', function (done) {
        // Implemented in Swift: BasicServingTests.testAssetBundleAssetsAccess()
        // The file path is app/some-file, while the URL is /some-file
        fetchFromLocalServer('/some-file').then(function (response) {
          expect(response.status).toBe(200);
          response.text().then(function (text) {
            expect(text).toContain('some-file');
            done();
          });
        });
      });

      it('should serve assets from the bundled www directory', function (done) {
        fetchFromLocalServer('/cordova_plugins.js').then(function (response) {
          expect(response.status).toBe(200);
          response.text().then(function (text) {
            expect(text).toContain("cordova.define('cordova/plugin_list'");
            done();
          });
        });
      });

      it('should serve index.html for any URL that does not correspond to an asset', function (done) {
        fetchFromLocalServer('/anything').then(expectIndexPageToBeServed(done));
      });

      it('should serve index.html when accessing an asset through /application', function (done) {
        fetchFromLocalServer('/application/packages/meteor.js').then(expectIndexPageToBeServed(done));
      });

      it('should serve index.html for an asset that is not in the manifest', function (done) {
        // Implemented in Swift: BasicServingTests.testMissingAssetFallback()
        fetchFromLocalServer('/not-in-manifest').then(expectIndexPageToBeServed(done));
      });

      it('should serve index.html when accessing an asset that is not in the manifest through /application', function (done) {
        // Implemented in Swift: BasicServingTests.testMissingAssetFallback()
        fetchFromLocalServer('/application/not-in-manifest').then(expectIndexPageToBeServed(done));
      });

      it('should not serve index.html for a non-existing /favicon.ico', function (done) {
        // Implemented in Swift: BasicServingTests.testFaviconAssetHandling()
        fetchFromLocalServer('/favicon.ico').then(function (response) {
          expect(response.status).toBe(404);
          done();
        });
      });
    });

    describe('when updating from the bundled app version to a downloaded version', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('version2', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should only serve the new version after a page reload', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          expectVersionServedToEqual('version1', function () {
            WebAppLocalServer.simulatePageReload(function () {
              expectVersionServedToEqual('version2', done);
            });
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should only download changed files', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppMockRemoteServer.receivedRequests(
            expectPathsForRequestsToMatch(
              [
                '/__cordova/manifest.json',
                '/__cordova/',
                '/__cordova/app/template.mobileapp.js',
                '/__cordova/app/3f6275657e6db3a21acb37d0f6c207cf83871e90.map',
                '/__cordova/some-file',
                '/__cordova/some-other-file',
              ],
              done,
            ),
          );
        });

        WebAppLocalServer.checkForUpdates();
      });

      it("should still serve assets that haven't changed", function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulatePageReload(function () {
            expectAssetToBeServed('some-text.txt', done);
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should remember the new version after a restart', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulateAppRestart(function () {
            expectVersionServedToEqual('version2', done);
          });
        });

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when updating from a downloaded app version to another downloaded version', function () {
      beforeEach(function (done) {
        downloadAndServeVersionLocally('version2', function () {
          WebAppMockRemoteServer.serveVersion('version3', done);
        });
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should only serve the new verson after a page reload', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          expectVersionServedToEqual('version2', function () {
            WebAppLocalServer.simulatePageReload(function () {
              expectVersionServedToEqual('version3', done);
            });
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should only download changed files', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppMockRemoteServer.receivedRequests(
            expectPathsForRequestsToMatch(
              [
                '/__cordova/manifest.json',
                '/__cordova/',
                '/__cordova/app/template.mobileapp.js',
                '/__cordova/app/36e96c1d40459ae12164569599c9c0a203b36db7.map',
                '/__cordova/some-file',
              ],
              done,
            ),
          );
        });

        WebAppLocalServer.checkForUpdates();
      });

      it("should still serve assets that haven't changed", function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulatePageReload(function () {
            expectAssetToBeServed('some-text.txt', done);
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should delete the old version after startup completes', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulatePageReload(function () {
            WebAppLocalServer.downloadedVersionExists('version2', function (versionExists) {
              expect(versionExists).toBe(true);

              WebAppLocalServer.startupDidComplete(function () {
                WebAppLocalServer.downloadedVersionExists('version2', function (versionExists) {
                  expect(versionExists).toBe(false);

                  done();
                });
              });
            });
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should remember the new version after a restart', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulateAppRestart(function () {
            expectVersionServedToEqual('version3', done);
          });
        });

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when updating from a downloaded app version to the bundled version', function () {
      beforeEach(function (done) {
        downloadAndServeVersionLocally('version2', function () {
          WebAppMockRemoteServer.serveVersion('version1', done);
        });
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should only serve the new verson after a page reload', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          expectVersionServedToEqual('version2', function () {
            WebAppLocalServer.simulatePageReload(function () {
              expectVersionServedToEqual('version1', done);
            });
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should only download the manifest', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppMockRemoteServer.receivedRequests(expectPathsForRequestsToMatch(['/__cordova/manifest.json'], done));
        });

        WebAppLocalServer.checkForUpdates();
      });

      it("should still serve assets that haven't changed", function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulatePageReload(function () {
            expectAssetToBeServed('some-text.txt', done);
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not redownload the bundled version', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.downloadedVersionExists('version1', function (versionExists) {
            expect(versionExists).toBe(false);
            done();
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should delete the old version after startup completes', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulatePageReload(function () {
            WebAppLocalServer.downloadedVersionExists('version2', function (versionExists) {
              expect(versionExists).toBe(true);

              WebAppLocalServer.startupDidComplete(function () {
                WebAppLocalServer.downloadedVersionExists('version2', function (versionExists) {
                  expect(versionExists).toBe(false);

                  done();
                });
              });
            });
          });
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should remember the new version after a restart', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          WebAppLocalServer.simulateAppRestart(function () {
            expectVersionServedToEqual('version1', done);
          });
        });

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when checking for updates while there is no new version', function () {
      beforeEach(function (done) {
        downloadAndServeVersionLocally('version2', function () {
          WebAppMockRemoteServer.serveVersion('version2', done);
        });
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });

      it('should not download any files except for the manifest', function (done) {
        setTimeout(function () {
          WebAppMockRemoteServer.receivedRequests(expectPathsForRequestsToMatch(['/__cordova/manifest.json'], done));
        }, 500);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading a missing asset', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('version2_with_missing_asset', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toEqual('Non-success status code 404 for asset: /app/template.mobileapp.js');
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading an invalid asset', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('version2_with_invalid_asset', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toEqual('Hash mismatch for asset: /app/template.mobileapp.js');
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading an index page with the wrong version', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('version2_with_version_mismatch', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toEqual('Version mismatch for index page, expected: version2, actual: version3');
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading an index page with a missing ROOT_URL', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('missing_root_url', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toEqual('Could not find ROOT_URL in downloaded asset bundle');
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading an index page with the wrong ROOT_URL', function () {
      beforeEach(function (done) {
        downloadAndServeVersionLocally('127.0.0.1_root_url', function () {
          WebAppMockRemoteServer.serveVersion('wrong_root_url', done);
        });
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toContain(
            'ROOT_URL in downloaded asset bundle would change current ROOT_URL to localhost.',
          );
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading an index page with a missing appId', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('missing_app_id', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toEqual('Could not find appId in downloaded asset bundle');
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading an index page with the wrong appId', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('wrong_app_id', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toContain('appId in downloaded asset bundle does not match current appId');
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading a version with a missing cordovaCompatibilityVersion', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('missing_cordova_compatibility_version', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toEqual('Asset manifest does not have a cordovaCompatibilityVersion');
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when downloading a version with a different cordovaCompatibilityVersion', function () {
      beforeEach(function (done) {
        WebAppMockRemoteServer.serveVersion('different_cordova_compatibility_version', done);
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should invoke the onError callback with an error', function (done) {
        WebAppLocalServer.onError(function (error) {
          expect(error.message).toEqual(
            'Skipping downloading new version because \
the Cordova platform version or plugin versions have changed and are potentially incompatible',
          );
          done();
        });

        WebAppLocalServer.checkForUpdates();
      });

      it('should not invoke the onNewVersionReady callback', function (done) {
        WebAppLocalServer.onNewVersionReady(function () {
          fail();
          done();
        });

        // Wait 500ms for the test to fail
        waitForTestToFail(500, done);

        WebAppLocalServer.checkForUpdates();
      });
    });

    describe('when resuming a partial download with the same version', function () {
      beforeEach(function (done) {
        WebAppLocalServer.simulatePartialDownload('version2', function () {
          WebAppMockRemoteServer.serveVersion('version2', function () {
            WebAppLocalServer.onNewVersionReady(done);
            WebAppLocalServer.checkForUpdates();
          });
        });
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should only download the manifest, the index page, and the remaining assets', function (done) {
        WebAppMockRemoteServer.receivedRequests(
          expectPathsForRequestsToMatch(
            [
              '/__cordova/manifest.json',
              '/__cordova/',
              '/__cordova/app/template.mobileapp.js',
              '/__cordova/app/3f6275657e6db3a21acb37d0f6c207cf83871e90.map',
            ],
            done,
          ),
        );
      });

      it('should only serve the new verson after a page reload', function (done) {
        expectVersionServedToEqual('version1', function () {
          WebAppLocalServer.simulatePageReload(function () {
            expectVersionServedToEqual('version2', done);
          });
        });
      });

      it('should serve assets that have been downloaded before', function (done) {
        WebAppLocalServer.simulatePageReload(function () {
          expectAssetToBeServed('some-file', 'some-file (changed)', done);
        });
      });
    });

    describe('when resuming a partial download with a different version', function () {
      beforeEach(function (done) {
        WebAppLocalServer.simulatePartialDownload('version2', function () {
          WebAppMockRemoteServer.serveVersion('version3', function () {
            WebAppLocalServer.onNewVersionReady(done);
            WebAppLocalServer.checkForUpdates();
          });
        });
      });

      afterEach(function (done) {
        WebAppLocalServer.resetToInitialState(done);
      });

      it('should only download the manifest, the index page, and both remaining and changed assets', function (done) {
        WebAppMockRemoteServer.receivedRequests(
          expectPathsForRequestsToMatch(
            [
              '/__cordova/manifest.json',
              '/__cordova/',
              '/__cordova/app/template.mobileapp.js',
              '/__cordova/app/36e96c1d40459ae12164569599c9c0a203b36db7.map',
              '/__cordova/some-file',
            ],
            done,
          ),
        );
      });

      it('should only serve the new verson after a page reload', function (done) {
        expectVersionServedToEqual('version1', function () {
          WebAppLocalServer.simulatePageReload(function () {
            expectVersionServedToEqual('version3', done);
          });
        });
      });

      it('should serve assets that have been downloaded before', function (done) {
        WebAppLocalServer.simulatePageReload(function () {
          expectAssetToBeServed('some-other-file', done);
        });
      });

      it('should serve changed assets even if they have been downloaded before', function (done) {
        WebAppLocalServer.simulatePageReload(function () {
          expectAssetToBeServed('some-file', 'some-file (changed again)', done);
        });
      });
    });
  });
};

// Helpers

function fetchFromLocalServer(path) {
  return fetch('http://localhost:' + localServerPort + path, {
    // Without this, fetch won't send cookies
    credentials: 'include',
  });
}

function expectIndexPageToBeServed(done) {
  return function (response) {
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toEqual('text/html');
    response.text().then(function (html) {
      expect(html).toContain('<title>mobileapp</title>');
      done();
    });
  };
}

function expectAssetToBeServed(filename, content, done) {
  if (done == null) {
    done = content;
    content = filename;
  }

  fetchFromLocalServer('/' + filename).then(function (response) {
    expect(response.status).toBe(200);
    response.text().then(function (text) {
      expect(text).toContain(filename);
      done();
    });
  });
}

function downloadAndServeVersionLocally(version, done) {
  WebAppMockRemoteServer.serveVersion(version, function () {
    WebAppLocalServer.onNewVersionReady(function () {
      WebAppLocalServer.simulatePageReload(done);
    });

    WebAppLocalServer.checkForUpdates();
  });
}

function expectVersionServedToEqual(expectedVersion, done) {
  fetchFromLocalServer('/').then(function (response) {
    expect(response.status).toBe(200);
    expect(response.headers.get('Content-Type')).toEqual('text/html');
    response.text().then(function (html) {
      var config = runtimeConfigFromHTML(html);
      var version = config.autoupdateVersionCordova;
      expect(version).toEqual(expectedVersion);
      done();
    });
  });
}

function runtimeConfigFromHTML(html) {
  var regex = /__meteor_runtime_config__ = JSON.parse\(decodeURIComponent\("([^"]*)"\)\)/;
  var matches = html.match(regex);
  if (!matches) {
    fail("Can't find __meteor_runtime_config__");
  }
  return JSON.parse(decodeURIComponent(matches[1]));
}

function pathsForRequests(requests) {
  return _.pluck(requests, 'path');
}

function expectPathsForRequestsToMatch(expectedPaths, done) {
  return function (requests) {
    var paths = pathsForRequests(requests);
    expect(paths).toMatchArray(expectedPaths);
    done();
  };
}

function waitForTestToFail(delay, done) {
  // Wait delay ms for the test to fail
  setTimeout(function () {
    // Hack to avoid SPEC HAS NO EXPECTATIONS
    expect(true).toBe(true);
    done();
  }, delay);
}
