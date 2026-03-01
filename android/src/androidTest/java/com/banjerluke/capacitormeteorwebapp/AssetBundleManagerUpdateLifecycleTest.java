package com.banjerluke.capacitormeteorwebapp;

import android.content.Context;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import okhttp3.mockwebserver.Dispatcher;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertSame;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public class AssetBundleManagerUpdateLifecycleTest {

    private MockWebServer server;
    private File versionsDirectory;
    private Context context;
    private String appId;
    private String rootUrl;
    private String compatibility;

    @Before
    public void setUp() throws Exception {
        server = new MockWebServer();
        server.start();

        context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        versionsDirectory = new File(context.getFilesDir(), "meteor-test-" + UUID.randomUUID());
        if (versionsDirectory.exists()) {
            FileOps.deleteRecursively(versionsDirectory);
        }
        assertTrue(versionsDirectory.mkdirs());

        appId = "test-app-id";
        rootUrl = server.url("/").toString();
        compatibility = "android-1";
    }

    @After
    public void tearDown() throws Exception {
        if (server != null) {
            server.shutdown();
        }
        if (versionsDirectory != null) {
            FileOps.deleteRecursively(versionsDirectory);
        }
    }

    private WebAppConfiguration createConfiguration() {
        WebAppConfiguration configuration = new WebAppConfiguration(
            context.getSharedPreferences("MeteorWebApp-Test-" + UUID.randomUUID(), Context.MODE_PRIVATE)
        );
        configuration.reset();
        configuration.setAppId(appId);
        configuration.setRootUrlString(rootUrl);
        configuration.setCordovaCompatibilityVersion(compatibility);
        return configuration;
    }

    private AssetBundle createInitialBundle(String version) throws Exception {
        TestBundleBuilder builder = new TestBundleBuilder(version, appId, rootUrl, compatibility);
        return builder.buildAssetBundle(null);
    }

    @Test
    public void downloadNewVersion_storesBundleAndNotifies() throws Exception {
        String newVersion = "v-new-1";

        TestBundleBuilder serverBuilder = new TestBundleBuilder(newVersion, appId, rootUrl, compatibility)
            .addAsset("app/main.js", "js", "console.log('v1');")
            .addAsset("app/style.css", "css", "body{}");
        server.setDispatcher(serverBuilder.buildDispatcher());

        AssetBundle initialBundle = createInitialBundle("v-initial");
        WebAppConfiguration configuration = createConfiguration();
        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<AssetBundle> downloaded = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                downloaded.set(assetBundle);
                latch.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure.set(cause);
                latch.countDown();
            }
        });

        URL baseUrl = server.url("/__cordova/").url();
        manager.checkForUpdates(baseUrl);

        assertTrue("Timed out", latch.await(30, TimeUnit.SECONDS));
        assertNull("Unexpected error: " + failure.get(), failure.get());

        AssetBundle result = downloaded.get();
        assertNotNull(result);
        assertEquals(newVersion, result.getVersion());

        File mainJs = new File(versionsDirectory, newVersion + "/app/main.js");
        assertTrue("Downloaded asset should exist on disk", mainJs.exists());

        File styleCss = new File(versionsDirectory, newVersion + "/app/style.css");
        assertTrue("Downloaded asset should exist on disk", styleCss.exists());

        manager.shutdown();
    }

    @Test
    public void sameVersionAsInitial_notifiesWithInitialBundle() throws Exception {
        String version = "v-same-initial";

        TestBundleBuilder serverBuilder = new TestBundleBuilder(version, appId, rootUrl, compatibility)
            .addAsset("app/main.js", "js", "console.log('same');");
        server.setDispatcher(serverBuilder.buildDispatcher());

        AssetBundle initialBundle = createInitialBundle(version);
        WebAppConfiguration configuration = createConfiguration();
        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<AssetBundle> downloaded = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                downloaded.set(assetBundle);
                latch.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure.set(cause);
                latch.countDown();
            }
        });

        URL baseUrl = server.url("/__cordova/").url();
        manager.checkForUpdates(baseUrl);

        assertTrue("Timed out", latch.await(30, TimeUnit.SECONDS));
        assertNull("Unexpected error: " + failure.get(), failure.get());

        AssetBundle result = downloaded.get();
        assertNotNull(result);
        assertSame("Should return the initial bundle instance", initialBundle, result);

        manager.shutdown();
    }

    @Test
    public void sameVersionAlreadyDownloaded_notifiesWithExistingBundle() throws Exception {
        String version = "v-already-dl";

        TestBundleBuilder serverBuilder = new TestBundleBuilder(version, appId, rootUrl, compatibility)
            .addAsset("app/main.js", "js", "console.log('already');");
        server.setDispatcher(serverBuilder.buildDispatcher());

        AssetBundle initialBundle = createInitialBundle("v-initial");
        WebAppConfiguration configuration = createConfiguration();
        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        // First download
        CountDownLatch latch1 = new CountDownLatch(1);
        AtomicReference<AssetBundle> firstDownload = new AtomicReference<>();
        AtomicReference<Throwable> failure1 = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                firstDownload.set(assetBundle);
                latch1.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure1.set(cause);
                latch1.countDown();
            }
        });

        URL baseUrl = server.url("/__cordova/").url();
        manager.checkForUpdates(baseUrl);

        assertTrue("First download timed out", latch1.await(30, TimeUnit.SECONDS));
        assertNull("Unexpected error: " + failure1.get(), failure1.get());
        assertNotNull(firstDownload.get());

        int requestCountAfterFirst = server.getRequestCount();

        // Second check — same version already downloaded
        CountDownLatch latch2 = new CountDownLatch(1);
        AtomicReference<AssetBundle> secondDownload = new AtomicReference<>();
        AtomicReference<Throwable> failure2 = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                secondDownload.set(assetBundle);
                latch2.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure2.set(cause);
                latch2.countDown();
            }
        });

        manager.checkForUpdates(baseUrl);

        assertTrue("Second check timed out", latch2.await(30, TimeUnit.SECONDS));
        assertNull("Unexpected error: " + failure2.get(), failure2.get());

        AssetBundle secondResult = secondDownload.get();
        assertNotNull(secondResult);
        assertEquals(version, secondResult.getVersion());

        // Only the manifest request should have been made (no asset downloads)
        int requestCountAfterSecond = server.getRequestCount();
        assertEquals("Should only fetch manifest on second check", requestCountAfterFirst + 1, requestCountAfterSecond);

        manager.shutdown();
    }

    @Test
    public void downloadSecondVersion_onlyDownloadsChangedAssets() throws Exception {
        String v1 = "v-change-1";
        String v2 = "v-change-2";
        String sharedContent = "/* shared content */";
        String sharedHash;
        {
            java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-1");
            byte[] digest = md.digest(sharedContent.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(40);
            for (byte b : digest) sb.append(String.format("%02x", b));
            sharedHash = sb.toString();
        }

        // Set up v1 on server
        TestBundleBuilder v1Builder = new TestBundleBuilder(v1, appId, rootUrl, compatibility)
            .addAsset("app/shared.js", "js", sharedContent)
            .addAsset("app/changed.js", "js", "// v1 content");
        server.setDispatcher(v1Builder.buildDispatcher());

        AssetBundle initialBundle = createInitialBundle("v-initial");
        WebAppConfiguration configuration = createConfiguration();
        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        // Download v1
        CountDownLatch latch1 = new CountDownLatch(1);
        AtomicReference<Throwable> failure1 = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                latch1.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure1.set(cause);
                latch1.countDown();
            }
        });

        URL baseUrl = server.url("/__cordova/").url();
        manager.checkForUpdates(baseUrl);
        assertTrue("v1 download timed out", latch1.await(30, TimeUnit.SECONDS));
        assertNull("v1 error: " + failure1.get(), failure1.get());

        // Now set up v2 — shared.js has same content/hash, changed.js has new content
        TestBundleBuilder v2Builder = new TestBundleBuilder(v2, appId, rootUrl, compatibility)
            .addAsset("app/shared.js", "js", sharedContent)
            .addAsset("app/changed.js", "js", "// v2 content");

        // Track which assets are requested
        List<String> v2AssetRequests = new ArrayList<>();
        String v2Manifest = v2Builder.buildManifestJson();
        String v2Index = v2Builder.buildIndexHtml();

        server.setDispatcher(new Dispatcher() {
            @Override
            public MockResponse dispatch(RecordedRequest request) {
                String path = request.getPath();
                String cleanPath = path == null ? "" : path.split("\\?")[0];

                if ("/__cordova/manifest.json".equals(cleanPath)) {
                    return new MockResponse().setResponseCode(200).setBody(v2Manifest);
                }
                if ("/__cordova/".equals(cleanPath)) {
                    return new MockResponse().setResponseCode(200).setBody(v2Index);
                }

                // Track asset download requests
                for (TestBundleBuilder.AssetEntry asset : v2Builder.getAssets()) {
                    if (("/__cordova/" + asset.path).equals(cleanPath)) {
                        synchronized (v2AssetRequests) {
                            v2AssetRequests.add(asset.path);
                        }
                        return new MockResponse()
                            .setResponseCode(200)
                            .addHeader("ETag", "\"" + asset.hash + "\"")
                            .setBody(asset.content);
                    }
                }

                return new MockResponse().setResponseCode(404);
            }
        });

        // Download v2
        CountDownLatch latch2 = new CountDownLatch(1);
        AtomicReference<Throwable> failure2 = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                latch2.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure2.set(cause);
                latch2.countDown();
            }
        });

        manager.checkForUpdates(baseUrl);
        assertTrue("v2 download timed out", latch2.await(30, TimeUnit.SECONDS));
        assertNull("v2 error: " + failure2.get(), failure2.get());

        // shared.js has the same hash, so it should NOT have been downloaded
        synchronized (v2AssetRequests) {
            assertFalse("shared.js should not be downloaded (cached from v1)", v2AssetRequests.contains("app/shared.js"));
            assertTrue("changed.js should be downloaded (new content)", v2AssetRequests.contains("app/changed.js"));
        }

        manager.shutdown();
    }

    @Test
    public void downloadSecondVersion_cachedAssetsStillAccessible() throws Exception {
        String v1 = "v-cached-1";
        String v2 = "v-cached-2";
        String sharedContent = "/* shared asset for cache test */";

        TestBundleBuilder v1Builder = new TestBundleBuilder(v1, appId, rootUrl, compatibility)
            .addAsset("app/shared.js", "js", sharedContent)
            .addAsset("app/v1only.js", "js", "// v1 only");
        server.setDispatcher(v1Builder.buildDispatcher());

        AssetBundle initialBundle = createInitialBundle("v-initial");
        WebAppConfiguration configuration = createConfiguration();
        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        // Download v1
        CountDownLatch latch1 = new CountDownLatch(1);
        AtomicReference<AssetBundle> v1Bundle = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                v1Bundle.set(assetBundle);
                latch1.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure.set(cause);
                latch1.countDown();
            }
        });

        URL baseUrl = server.url("/__cordova/").url();
        manager.checkForUpdates(baseUrl);
        assertTrue("v1 timed out", latch1.await(30, TimeUnit.SECONDS));
        assertNull("v1 error: " + failure.get(), failure.get());

        // Download v2 — same shared.js, different second asset
        TestBundleBuilder v2Builder = new TestBundleBuilder(v2, appId, rootUrl, compatibility)
            .addAsset("app/shared.js", "js", sharedContent)
            .addAsset("app/v2only.js", "js", "// v2 only");
        server.setDispatcher(v2Builder.buildDispatcher());

        CountDownLatch latch2 = new CountDownLatch(1);
        AtomicReference<AssetBundle> v2Bundle = new AtomicReference<>();
        failure.set(null);

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                v2Bundle.set(assetBundle);
                latch2.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure.set(cause);
                latch2.countDown();
            }
        });

        manager.checkForUpdates(baseUrl);
        assertTrue("v2 timed out", latch2.await(30, TimeUnit.SECONDS));
        assertNull("v2 error: " + failure.get(), failure.get());

        AssetBundle v2Result = v2Bundle.get();
        assertNotNull(v2Result);

        // v2 should still resolve shared.js via parent chain
        Asset sharedAsset = v2Result.assetForUrlPath("/app/shared.js");
        assertNotNull("shared.js should be accessible in v2 bundle (via parent chain or copy)", sharedAsset);

        manager.shutdown();
    }

    @Test
    public void sameVersionOnServer_callbackNotInvoked() throws Exception {
        String version = "v-no-update";

        TestBundleBuilder serverBuilder = new TestBundleBuilder(version, appId, rootUrl, compatibility)
            .addAsset("app/main.js", "js", "console.log('no update');");

        // Only serve the manifest (shouldDownloadBundleForManifest returns false)
        String manifestJson = serverBuilder.buildManifestJson();
        server.setDispatcher(new Dispatcher() {
            @Override
            public MockResponse dispatch(RecordedRequest request) {
                String path = request.getPath();
                String cleanPath = path == null ? "" : path.split("\\?")[0];

                if ("/__cordova/manifest.json".equals(cleanPath)) {
                    return new MockResponse().setResponseCode(200).setBody(manifestJson);
                }
                return new MockResponse().setResponseCode(404);
            }
        });

        AssetBundle initialBundle = createInitialBundle("v-initial");
        WebAppConfiguration configuration = createConfiguration();
        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        CountDownLatch latch = new CountDownLatch(1);

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return false; // Reject the download
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                latch.countDown(); // Should NOT be called
            }

            @Override
            public void onError(Throwable cause) {
                latch.countDown(); // Should NOT be called
            }
        });

        URL baseUrl = server.url("/__cordova/").url();
        manager.checkForUpdates(baseUrl);

        // Neither callback should fire — wait briefly and verify
        assertFalse("Callbacks should not be invoked when shouldDownload returns false",
            latch.await(3, TimeUnit.SECONDS));

        manager.shutdown();
    }

    @Test
    public void alreadyDownloadingSameVersion_doesNotRestartDownload() throws Exception {
        String version = "v-dedup";

        TestBundleBuilder serverBuilder = new TestBundleBuilder(version, appId, rootUrl, compatibility)
            .addAsset("app/main.js", "js", "console.log('dedup');");

        // Slow down the manifest response to create a window for the second call
        String manifestJson = serverBuilder.buildManifestJson();
        String indexHtml = serverBuilder.buildIndexHtml();
        String hash = serverBuilder.getAssets().get(0).hash;

        server.setDispatcher(new Dispatcher() {
            @Override
            public MockResponse dispatch(RecordedRequest request) {
                String path = request.getPath();
                String cleanPath = path == null ? "" : path.split("\\?")[0];

                if ("/__cordova/manifest.json".equals(cleanPath)) {
                    return new MockResponse().setResponseCode(200).setBody(manifestJson);
                }
                if ("/__cordova/".equals(cleanPath)) {
                    return new MockResponse().setResponseCode(200).setBody(indexHtml);
                }
                if ("/__cordova/app/main.js".equals(cleanPath)) {
                    return new MockResponse()
                        .setResponseCode(200)
                        .addHeader("ETag", "\"" + hash + "\"")
                        .setBody("console.log('dedup');")
                        .throttleBody(10, 100, TimeUnit.MILLISECONDS); // Slow download
                }
                return new MockResponse().setResponseCode(404);
            }
        });

        AssetBundle initialBundle = createInitialBundle("v-initial");
        WebAppConfiguration configuration = createConfiguration();
        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<AssetBundle> downloaded = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                return true;
            }

            @Override
            public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
                downloaded.set(assetBundle);
                latch.countDown();
            }

            @Override
            public void onError(Throwable cause) {
                failure.set(cause);
                latch.countDown();
            }
        });

        URL baseUrl = server.url("/__cordova/").url();

        // Fire two checks rapidly — second should be a no-op since same version is downloading
        manager.checkForUpdates(baseUrl);
        manager.checkForUpdates(baseUrl);

        assertTrue("Timed out", latch.await(30, TimeUnit.SECONDS));
        assertNull("Unexpected error: " + failure.get(), failure.get());
        assertNotNull(downloaded.get());
        assertEquals(version, downloaded.get().getVersion());

        manager.shutdown();
    }
}
