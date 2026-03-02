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
import java.util.Arrays;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import okhttp3.mockwebserver.MockWebServer;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

@RunWith(AndroidJUnit4.class)
public class ShouldDownloadFilterTest {

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

    private int countDownloadedVersionDirectories() {
        File[] entries = versionsDirectory.listFiles();
        if (entries == null) {
            return 0;
        }

        return (int) Arrays.stream(entries)
            .filter(File::isDirectory)
            .filter(file -> !"Downloading".equals(file.getName()))
            .filter(file -> !"PartialDownload".equals(file.getName()))
            .count();
    }

    @Test
    public void differentCompatibilityVersion_skipsDownload() throws Exception {
        String version = "v-compat-skip";

        // Server has a DIFFERENT compatibility version
        TestBundleBuilder builder = new TestBundleBuilder(version, appId, rootUrl, "android-2")
            .addAsset("app/main.js", "js", "console.log('compat');");
        server.setDispatcher(builder.buildDispatcher());

        // Initial bundle and config use "android-1"
        TestBundleBuilder initialBuilder = new TestBundleBuilder("v-initial", appId, rootUrl, compatibility);
        AssetBundle initialBundle = initialBuilder.buildAssetBundle(null);
        WebAppConfiguration configuration = createConfiguration();

        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<AssetBundle> downloaded = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        // Use the same filtering logic as CapacitorMeteorWebApp
        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                String currentCompat = configuration.getCordovaCompatibilityVersion();
                if (currentCompat != null && !currentCompat.equals(manifest.cordovaCompatibilityVersion)) {
                    return false;
                }
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

        // Neither callback should fire
        assertFalse("Should skip download for incompatible version",
            latch.await(3, TimeUnit.SECONDS));
        assertNull("No success callback expected", downloaded.get());
        assertNull("No error callback expected", failure.get());
        assertEquals("Only manifest should be requested", 1, server.getRequestCount());
        assertEquals("No downloaded versions should be written", 0, countDownloadedVersionDirectories());

        manager.shutdown();
    }

    @Test
    public void blacklistedVersion_skipsDownload() throws Exception {
        String version = "v-blacklisted";

        TestBundleBuilder builder = new TestBundleBuilder(version, appId, rootUrl, compatibility)
            .addAsset("app/main.js", "js", "console.log('blacklisted');");
        server.setDispatcher(builder.buildDispatcher());

        TestBundleBuilder initialBuilder = new TestBundleBuilder("v-initial", appId, rootUrl, compatibility);
        AssetBundle initialBundle = initialBuilder.buildAssetBundle(null);
        WebAppConfiguration configuration = createConfiguration();

        // Blacklist the version (call twice — first adds to retry, second blacklists)
        configuration.addBlacklistedVersion(version);
        configuration.addBlacklistedVersion(version);
        assertTrue("Version should be blacklisted", configuration.getBlacklistedVersions().contains(version));

        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<AssetBundle> downloaded = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                if (configuration.getBlacklistedVersions().contains(manifest.version)) {
                    return false;
                }
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

        assertFalse("Should skip download for blacklisted version",
            latch.await(3, TimeUnit.SECONDS));
        assertNull("No success callback expected", downloaded.get());
        assertNull("No error callback expected", failure.get());
        assertEquals("Only manifest should be requested", 1, server.getRequestCount());
        assertEquals("No downloaded versions should be written", 0, countDownloadedVersionDirectories());

        manager.shutdown();
    }

    @Test
    public void currentVersionMatchesManifest_skipsDownload() throws Exception {
        String currentVersion = "v-current-match";

        // Server has the same version as what we'll set as "current"
        TestBundleBuilder builder = new TestBundleBuilder(currentVersion, appId, rootUrl, compatibility)
            .addAsset("app/main.js", "js", "console.log('current');");
        server.setDispatcher(builder.buildDispatcher());

        TestBundleBuilder initialBuilder = new TestBundleBuilder("v-initial", appId, rootUrl, compatibility);
        AssetBundle initialBundle = initialBuilder.buildAssetBundle(null);

        // Build a "current" bundle with the same version as server
        TestBundleBuilder currentBuilder = new TestBundleBuilder(currentVersion, appId, rootUrl, compatibility);
        AssetBundle currentBundle = currentBuilder.buildAssetBundle(null);

        WebAppConfiguration configuration = createConfiguration();

        AssetBundleManager manager = new AssetBundleManager(context, configuration, versionsDirectory, initialBundle);

        CountDownLatch latch = new CountDownLatch(1);
        AtomicReference<AssetBundle> downloaded = new AtomicReference<>();
        AtomicReference<Throwable> failure = new AtomicReference<>();

        manager.setCallback(new AssetBundleManager.Callback() {
            @Override
            public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
                // Simulate CapacitorMeteorWebApp logic
                if (currentBundle.getVersion().equals(manifest.version)) {
                    return false;
                }
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

        assertFalse("Should skip download when current version matches manifest",
            latch.await(3, TimeUnit.SECONDS));
        assertNull("No success callback expected", downloaded.get());
        assertNull("No error callback expected", failure.get());
        assertEquals("Only manifest should be requested", 1, server.getRequestCount());
        assertEquals("No downloaded versions should be written", 0, countDownloadedVersionDirectories());

        manager.shutdown();
    }
}
