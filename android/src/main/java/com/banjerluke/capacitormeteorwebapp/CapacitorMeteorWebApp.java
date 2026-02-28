package com.banjerluke.capacitormeteorwebapp;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import com.getcapacitor.Bridge;

import java.io.File;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class CapacitorMeteorWebApp implements AssetBundleManager.Callback {

    interface ResultCallback {
        void onComplete(Throwable error);
    }

    interface EventCallback {
        void onUpdateAvailable(String version);
        void onError(String message);
    }

    private static final String PREFERENCES_NAME = "MeteorWebApp";
    private static final long STARTUP_TIMEOUT_MS = 30_000L;

    private final Bridge bridge;
    private final Context context;
    private final Handler mainHandler;
    private final ExecutorService bundleSwitchExecutor;

    private final WebAppConfiguration configuration;

    private final Runnable startupTimeoutRunnable = this::onStartupTimeout;

    private AssetBundleManager assetBundleManager;
    private AssetBundle initialAssetBundle;
    private AssetBundle currentAssetBundle;
    private AssetBundle pendingAssetBundle;

    private File versionsDirectory;
    private File servingDirectory;

    private boolean isPaused;

    private boolean startupTimerRunning;
    private long startupDeadlineUptimeMs;
    private long startupRemainingMs = -1L;

    private EventCallback eventCallback;

    CapacitorMeteorWebApp(Bridge bridge) throws WebAppError {
        this.bridge = bridge;
        this.context = bridge.getContext().getApplicationContext();
        this.mainHandler = new Handler(Looper.getMainLooper());
        this.bundleSwitchExecutor = Executors.newSingleThreadExecutor();

        SharedPreferences preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        this.configuration = new WebAppConfiguration(preferences);

        initializeAssetBundles();
    }

    void setEventCallback(EventCallback eventCallback) {
        this.eventCallback = eventCallback;
    }

    void checkForUpdates(ResultCallback callback) {
        try {
            String rootUrlString = configuration.getRootUrlString();
            if (rootUrlString == null) {
                callback.onComplete(
                    new WebAppError(
                        WebAppError.Type.NO_ROOT_URL_CONFIGURED,
                        "checkForUpdates requires ROOT_URL to be configured"
                    )
                );
                return;
            }

            URL rootUrl = new URL(rootUrlString);
            URL baseUrl = new URL(rootUrl, "__cordova/");
            assetBundleManager.checkForUpdates(baseUrl);
            callback.onComplete(null);
        } catch (MalformedURLException e) {
            callback.onComplete(
                new WebAppError(
                    WebAppError.Type.NO_ROOT_URL_CONFIGURED,
                    "Invalid ROOT_URL configured: " + configuration.getRootUrlString(),
                    e
                )
            );
        }
    }

    void startupDidComplete(ResultCallback callback) {
        stopStartupTimer();

        if (currentAssetBundle != null) {
            configuration.setLastKnownGoodVersion(currentAssetBundle.getVersion());
            assetBundleManager.removeAllDownloadedAssetBundlesExceptForVersion(currentAssetBundle.getVersion());
        }

        callback.onComplete(null);
    }

    String getCurrentVersion() {
        if (currentAssetBundle == null) {
            return "unknown";
        }
        return currentAssetBundle.getVersion();
    }

    boolean isUpdateAvailable() {
        return pendingAssetBundle != null;
    }

    void reload(ResultCallback callback) {
        bundleSwitchExecutor.execute(() -> {
            try {
                performReload();
                callback.onComplete(null);
            } catch (Throwable error) {
                callback.onComplete(error);
            }
        });
    }

    void handleOnPause() {
        isPaused = true;
        pauseStartupTimer();
    }

    void handleOnResume() {
        isPaused = false;
        resumeStartupTimer();
    }

    void handleOnDestroy() {
        stopStartupTimer();
        bundleSwitchExecutor.shutdownNow();
        if (assetBundleManager != null) {
            assetBundleManager.shutdown();
        }
    }

    private void initializeAssetBundles() throws WebAppError {
        AssetBundle.ResourceReader initialBundleReader = relativePath ->
            context.getAssets().open("public/" + relativePath);

        initialAssetBundle = AssetBundle.fromReader("assets/public", initialBundleReader, null);

        versionsDirectory = new File(context.getFilesDir(), "meteor");
        servingDirectory = new File(context.getFilesDir(), "meteor-serving");

        String lastSeenInitialVersion = configuration.getLastSeenInitialVersion();
        if (!Objects.equals(lastSeenInitialVersion, initialAssetBundle.getVersion())) {
            FileOps.deleteRecursively(versionsDirectory);
            FileOps.deleteRecursively(servingDirectory);
            configuration.reset();
        }

        configuration.setLastSeenInitialVersion(initialAssetBundle.getVersion());

        if (!versionsDirectory.exists() && !versionsDirectory.mkdirs() && !versionsDirectory.isDirectory()) {
            throw new WebAppError(
                WebAppError.Type.INITIALIZATION_FAILED,
                "Could not create versions directory: " + versionsDirectory.getAbsolutePath()
            );
        }

        if (!servingDirectory.exists() && !servingDirectory.mkdirs() && !servingDirectory.isDirectory()) {
            throw new WebAppError(
                WebAppError.Type.INITIALIZATION_FAILED,
                "Could not create serving directory: " + servingDirectory.getAbsolutePath()
            );
        }

        assetBundleManager = new AssetBundleManager(context, configuration, versionsDirectory, initialAssetBundle);
        assetBundleManager.setCallback(this);

        selectCurrentAssetBundle();
        pendingAssetBundle = null;
        setupCurrentBundle(false);
    }

    private void selectCurrentAssetBundle() {
        String lastDownloadedVersion = configuration.getLastDownloadedVersion();
        if (lastDownloadedVersion != null) {
            AssetBundle downloadedBundle = assetBundleManager.downloadedAssetBundleWithVersion(lastDownloadedVersion);
            if (downloadedBundle != null) {
                setCurrentAssetBundle(downloadedBundle);

                String lastKnownGood = configuration.getLastKnownGoodVersion();
                if (!lastDownloadedVersion.equals(lastKnownGood)) {
                    startStartupTimer();
                }
                return;
            }
        }

        setCurrentAssetBundle(initialAssetBundle);
    }

    private void setupCurrentBundle(boolean forceSwitchToInitialAssetPath) throws WebAppError {
        if (currentAssetBundle == null) {
            return;
        }

        if (currentAssetBundle == initialAssetBundle) {
            if (forceSwitchToInitialAssetPath) {
                setServerAssetPath("public");
            }

            cleanupOldServingDirectories(null);
            return;
        }

        File bundleServingDirectory = new File(servingDirectory, currentAssetBundle.getVersion());
        if (bundleServingDirectory.exists()) {
            FileOps.deleteRecursively(bundleServingDirectory);
        }

        BundleOrganizer.organizeBundle(currentAssetBundle, bundleServingDirectory);
        setServerBasePath(bundleServingDirectory.getAbsolutePath());

        cleanupOldServingDirectories(currentAssetBundle.getVersion());
    }

    private void cleanupOldServingDirectories(String versionToKeep) {
        File[] contents = servingDirectory.listFiles();
        if (contents == null) {
            return;
        }

        for (File entry : contents) {
            if (!entry.isDirectory()) {
                continue;
            }

            if (versionToKeep != null && versionToKeep.equals(entry.getName())) {
                continue;
            }

            FileOps.deleteRecursively(entry);
        }
    }

    private void performReload() throws WebAppError {
        if (pendingAssetBundle == null) {
            throw new WebAppError(
                WebAppError.Type.NO_PENDING_VERSION,
                "No pending version available to reload"
            );
        }

        AssetBundle targetBundle = pendingAssetBundle;
        File bundleServingDirectory = new File(servingDirectory, targetBundle.getVersion());
        if (bundleServingDirectory.exists()) {
            FileOps.deleteRecursively(bundleServingDirectory);
        }

        BundleOrganizer.organizeBundle(targetBundle, bundleServingDirectory);

        setCurrentAssetBundle(targetBundle);
        pendingAssetBundle = null;
        setServerBasePath(bundleServingDirectory.getAbsolutePath());
        startStartupTimer();
    }

    private void revertToLastKnownGoodVersion() {
        bundleSwitchExecutor.execute(() -> {
            if (currentAssetBundle == null) {
                return;
            }

            configuration.addBlacklistedVersion(currentAssetBundle.getVersion());

            AssetBundle fallbackBundle = null;
            String lastKnownGoodVersion = configuration.getLastKnownGoodVersion();
            if (lastKnownGoodVersion != null) {
                fallbackBundle = assetBundleManager.downloadedAssetBundleWithVersion(lastKnownGoodVersion);
            }

            if (fallbackBundle == null && currentAssetBundle != initialAssetBundle) {
                fallbackBundle = initialAssetBundle;
            }

            if (fallbackBundle == null) {
                notifyError("No suitable version available to revert to");
                return;
            }

            try {
                pendingAssetBundle = fallbackBundle;
                forceReload();
            } catch (Throwable cause) {
                notifyError(errorMessageForThrowable(cause));
            }
        });
    }

    private void forceReload() throws WebAppError {
        if (pendingAssetBundle != null) {
            setCurrentAssetBundle(pendingAssetBundle);
            pendingAssetBundle = null;
        }

        if (currentAssetBundle == initialAssetBundle) {
            setupCurrentBundle(true);
        } else {
            setupCurrentBundle(false);
        }
    }

    private void setCurrentAssetBundle(AssetBundle assetBundle) {
        currentAssetBundle = assetBundle;

        if (currentAssetBundle == null) {
            return;
        }

        configuration.setAppId(currentAssetBundle.getAppId());
        configuration.setRootUrlString(currentAssetBundle.getRootUrlString());
        configuration.setCordovaCompatibilityVersion(currentAssetBundle.getCordovaCompatibilityVersion());
    }

    private void setServerBasePath(String path) throws WebAppError {
        if (bridge == null) {
            throw new WebAppError(
                WebAppError.Type.BRIDGE_UNAVAILABLE,
                "Bridge unavailable while setting server base path"
            );
        }

        mainHandler.post(() -> bridge.setServerBasePath(path));
    }

    private void setServerAssetPath(String path) throws WebAppError {
        if (bridge == null) {
            throw new WebAppError(
                WebAppError.Type.BRIDGE_UNAVAILABLE,
                "Bridge unavailable while setting server asset path"
            );
        }

        mainHandler.post(() -> bridge.setServerAssetPath(path));
    }

    private void onStartupTimeout() {
        startupTimerRunning = false;
        startupRemainingMs = -1L;
        startupDeadlineUptimeMs = 0L;
        revertToLastKnownGoodVersion();
    }

    private void startStartupTimer() {
        mainHandler.post(() -> {
            stopStartupTimerOnMainThread();

            startupRemainingMs = STARTUP_TIMEOUT_MS;
            if (isPaused) {
                return;
            }

            startupDeadlineUptimeMs = SystemClock.uptimeMillis() + startupRemainingMs;
            startupTimerRunning = true;
            mainHandler.postDelayed(startupTimeoutRunnable, startupRemainingMs);
        });
    }

    private void stopStartupTimer() {
        mainHandler.post(this::stopStartupTimerOnMainThread);
    }

    private void stopStartupTimerOnMainThread() {
        mainHandler.removeCallbacks(startupTimeoutRunnable);
        startupTimerRunning = false;
        startupRemainingMs = -1L;
        startupDeadlineUptimeMs = 0L;
    }

    private void pauseStartupTimer() {
        mainHandler.post(() -> {
            if (!startupTimerRunning) {
                return;
            }

            long remaining = startupDeadlineUptimeMs - SystemClock.uptimeMillis();
            startupRemainingMs = Math.max(0L, remaining);

            mainHandler.removeCallbacks(startupTimeoutRunnable);
            startupTimerRunning = false;
            startupDeadlineUptimeMs = 0L;
        });
    }

    private void resumeStartupTimer() {
        mainHandler.post(() -> {
            if (startupTimerRunning) {
                return;
            }

            if (startupRemainingMs < 0L) {
                return;
            }

            if (startupRemainingMs <= 0L) {
                onStartupTimeout();
                return;
            }

            startupDeadlineUptimeMs = SystemClock.uptimeMillis() + startupRemainingMs;
            startupTimerRunning = true;
            mainHandler.postDelayed(startupTimeoutRunnable, startupRemainingMs);
        });
    }

    private void notifyUpdateAvailable(String version) {
        EventCallback callback = eventCallback;
        if (callback == null) {
            return;
        }
        mainHandler.post(() -> callback.onUpdateAvailable(version));
    }

    private void notifyError(String message) {
        EventCallback callback = eventCallback;
        if (callback == null) {
            return;
        }
        mainHandler.post(() -> callback.onError(message));
    }

    private String errorMessageForThrowable(Throwable throwable) {
        if (throwable == null) {
            return "Unknown error";
        }

        String message = throwable.getMessage();
        if (message == null || message.isEmpty()) {
            return throwable.getClass().getSimpleName();
        }

        return message;
    }

    @Override
    public boolean shouldDownloadBundleForManifest(AssetManifest manifest) {
        if (currentAssetBundle != null && currentAssetBundle.getVersion().equals(manifest.version)) {
            return false;
        }

        if (pendingAssetBundle != null && pendingAssetBundle.getVersion().equals(manifest.version)) {
            return false;
        }

        Set<String> blacklistedVersions = configuration.getBlacklistedVersions();
        if (blacklistedVersions.contains(manifest.version)) {
            notifyError("Skipping downloading blacklisted version: " + manifest.version);
            return false;
        }

        String currentCompatibility = configuration.getCordovaCompatibilityVersion();
        if (currentCompatibility != null && !currentCompatibility.equals(manifest.cordovaCompatibilityVersion)) {
            notifyError(
                "Skipping downloading new version because the Cordova compatibility version is potentially incompatible"
            );
            return false;
        }

        return true;
    }

    @Override
    public void onFinishedDownloadingAssetBundle(AssetBundle assetBundle) {
        bundleSwitchExecutor.execute(() -> {
            configuration.setLastDownloadedVersion(assetBundle.getVersion());
            pendingAssetBundle = assetBundle;
            notifyUpdateAvailable(assetBundle.getVersion());
        });
    }

    @Override
    public void onError(Throwable cause) {
        notifyError(errorMessageForThrowable(cause));
    }
}
