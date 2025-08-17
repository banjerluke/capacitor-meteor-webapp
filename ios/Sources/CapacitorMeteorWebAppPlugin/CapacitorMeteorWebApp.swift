import Foundation
import WebKit

// Protocol for Capacitor bridge to avoid direct dependency
public protocol CapacitorBridge: AnyObject {
    func setServerBasePath(_ path: String)
    func getWebView() -> AnyObject?
    var webView: WKWebView? { get }
}

@objc public class CapacitorMeteorWebApp: NSObject, AssetBundleManagerDelegate {

    // MARK: - Properties

    /// Persistent configuration settings for the webapp
    private(set) var configuration: WebAppConfiguration!

    /// The asset bundle manager handles downloading and managing bundles
    private(set) var assetBundleManager: AssetBundleManager!

    /// The asset bundle currently used to serve assets from
    private var currentAssetBundle: AssetBundle! {
        didSet {
            if currentAssetBundle != nil {
                configuration.appId = currentAssetBundle.appId
                configuration.rootURL = currentAssetBundle.rootURL
                configuration.cordovaCompatibilityVersion = currentAssetBundle.cordovaCompatibilityVersion
                NSLog("Serving asset bundle version: \(currentAssetBundle.version)")
            }
        }
    }

    /// Downloaded asset bundles are considered pending until the next page reload
    /// because we don't want the app to end up in an inconsistent state by
    /// loading assets from different bundles.
    private var pendingAssetBundle: AssetBundle?

    /// Timer used to wait for startup to complete after a reload
    private var startupTimer: Timer?

    /// The number of seconds to wait for startup to complete, after which
    /// we revert to the last known good version
    private var startupTimeoutInterval: TimeInterval = 30.0

    /// Semaphore to prevent concurrent bundle switches
    private let bundleSwitchSemaphore = DispatchSemaphore(value: 1)

    /// The www directory in the app bundle
    private var wwwDirectoryURL: URL!

    /// Reference to Capacitor bridge for bundle switching
    private weak var capacitorBridge: CapacitorBridge?

    /// Track if we switched to a new version (for startup timer)
    private var switchedToNewVersion = false

    /// Directory for serving organized bundles
    private var servingDirectoryURL: URL!

    // MARK: - Initialization

    public init(capacitorBridge: CapacitorBridge? = nil) {
        super.init()

        self.capacitorBridge = capacitorBridge

        // Initialize configuration
        configuration = WebAppConfiguration()

        // Set www directory URL
        wwwDirectoryURL = Bundle.main.resourceURL?.appendingPathComponent("www")

        // Initialize asset bundles
        initializeAssetBundles()

        // Setup startup timer
        setupStartupTimer()
    }

    private func initializeAssetBundles() {
        assetBundleManager = nil

        // The initial asset bundle consists of the assets bundled with the app
        let initialAssetBundle: AssetBundle
        do {
            let directoryURL = wwwDirectoryURL.appendingPathComponent("application")
            initialAssetBundle = try AssetBundle(directoryURL: directoryURL)
        } catch {
            NSLog("Could not load initial asset bundle: \(error)")
            return
        }

        let fileManager = FileManager.default

        // Downloaded versions are stored in Library/NoCloud/meteor
        let libraryDirectoryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let versionsDirectoryURL = libraryDirectoryURL.appendingPathComponent("NoCloud/meteor")

        // Serving directory for organized bundles
        servingDirectoryURL = libraryDirectoryURL.appendingPathComponent("NoCloud/meteor-serving")

        // If the last seen initial version is different from the currently bundled
        // version, we delete the versions directory and reset configuration
        if configuration.lastSeenInitialVersion != initialAssetBundle.version {
            do {
                if fileManager.fileExists(atPath: versionsDirectoryURL.path) {
                    try fileManager.removeItem(at: versionsDirectoryURL)
                }
                if fileManager.fileExists(atPath: servingDirectoryURL.path) {
                    try fileManager.removeItem(at: servingDirectoryURL)
                }
            } catch {
                NSLog("Could not remove versions directory: \(error)")
            }

            configuration.reset()
        }

        // We keep track of the last seen initial version
        configuration.lastSeenInitialVersion = initialAssetBundle.version

        // Create directories if they don't exist
        do {
            if !fileManager.fileExists(atPath: versionsDirectoryURL.path) {
                try fileManager.createDirectory(at: versionsDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
            if !fileManager.fileExists(atPath: servingDirectoryURL.path) {
                try fileManager.createDirectory(at: servingDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            NSLog("Could not create directories: \(error)")
            return
        }

        assetBundleManager = AssetBundleManager(configuration: configuration, versionsDirectoryURL: versionsDirectoryURL, initialAssetBundle: initialAssetBundle)
        assetBundleManager.delegate = self

        // If a last downloaded version has been set and the asset bundle exists,
        // we set it as the current asset bundle
        if let lastDownloadedVersion = configuration.lastDownloadedVersion,
           let downloadedAssetBundle = assetBundleManager.downloadedAssetBundleWithVersion(lastDownloadedVersion) {
            currentAssetBundle = downloadedAssetBundle
            if configuration.lastKnownGoodVersion != lastDownloadedVersion {
                startStartupTimer()
            }
        } else {
            currentAssetBundle = initialAssetBundle
        }

        pendingAssetBundle = nil

        // Organize and serve the current bundle
        setupCurrentBundle()
    }

    private func setupStartupTimer() {
        startupTimer = Timer(queue: DispatchQueue.global(qos: .utility)) { [weak self] in
            NSLog("App startup timed out, reverting to last known good version")
            self?.revertToLastKnownGoodVersion()
        }
    }

    private func setupCurrentBundle() {
        guard let currentAssetBundle = currentAssetBundle else { return }

        do {
            let bundleServingDirectory = servingDirectoryURL.appendingPathComponent(currentAssetBundle.version)

            // Remove existing serving directory for this version
            if FileManager.default.fileExists(atPath: bundleServingDirectory.path) {
                try FileManager.default.removeItem(at: bundleServingDirectory)
            }

            // Organize the bundle for serving
            try BundleOrganizer.organizeBundle(currentAssetBundle, in: bundleServingDirectory)

            // Set Capacitor's server base path to serve from organized bundle
            setServerBasePath(bundleServingDirectory)

        } catch {
            NSLog("Could not setup current bundle: \(error)")
        }
    }

    private func setServerBasePath(_ path: URL) {
        guard let bridge = capacitorBridge else {
            NSLog("No Capacitor bridge available for setting server base path")
            return
        }

        // Use Capacitor's setServerBasePath to change serving directory
        bridge.setServerBasePath(path.path)
    }

    private func startStartupTimer() {
        // Don't start the startup timer if the app started up in the background
        #if canImport(UIKit)
        if UIApplication.shared.applicationState == .active {
            NSLog("App startup timer started")
            startupTimer?.start(withTimeInterval: startupTimeoutInterval)
        }
        #else
        NSLog("App startup timer started")
        startupTimer?.start(withTimeInterval: startupTimeoutInterval)
        #endif
    }

    // MARK: - Public Methods

    /**
     * Check for available updates from the Meteor server
     */
    public func checkForUpdates(completion: @escaping (Error?) -> Void) {
        guard let rootURL = configuration.rootURL else {
            let error = WebAppError.downloadFailure(reason: "checkForUpdates requires a rootURL to be configured", underlyingError: nil)
            completion(error)
            return
        }

        let baseURL = rootURL.appendingPathComponent("__cordova/")
        assetBundleManager.checkForUpdatesWithBaseURL(baseURL)

        completion(nil)
    }

    /**
     * Notify the plugin that app startup is complete
     */
    public func startupDidComplete(completion: @escaping (Error?) -> Void) {
        NSLog("App startup confirmed")
        startupTimer?.stop()

        // If startup completed successfully, we consider a version good
        configuration.lastKnownGoodVersion = currentAssetBundle.version

        // Clean up old asset bundles in the background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.assetBundleManager.removeAllDownloadedAssetBundlesExceptFor(self.currentAssetBundle)
            } catch {
                NSLog("Could not remove unused asset bundles: \(error)")
            }
        }

        completion(nil)
    }

    /**
     * Get the current app version
     */
    public func getCurrentVersion() -> String {
        return currentAssetBundle?.version ?? "unknown"
    }

    /**
     * Check if an update is available and ready to install
     */
    public func isUpdateAvailable() -> Bool {
        return pendingAssetBundle != nil
    }

    /**
     * Reload the app with the latest available version
     */
    public func reload(completion: @escaping (Error?) -> Void) {
        bundleSwitchSemaphore.wait()
        defer { bundleSwitchSemaphore.signal() }

        // If there is a pending asset bundle, we switch to it atomically
        guard let pendingAssetBundle = pendingAssetBundle else {
            let error = WebAppError.downloadFailure(reason: "No pending version to switch to", underlyingError: nil)
            completion(error)
            return
        }

        NSLog("Switching to pending version \(pendingAssetBundle.version)")

        do {
            // Organize the pending bundle for serving
            let bundleServingDirectory = servingDirectoryURL.appendingPathComponent(pendingAssetBundle.version)

            // Remove existing serving directory for this version
            if FileManager.default.fileExists(atPath: bundleServingDirectory.path) {
                try FileManager.default.removeItem(at: bundleServingDirectory)
            }

            // Organize the bundle
            try BundleOrganizer.organizeBundle(pendingAssetBundle, in: bundleServingDirectory)

            // Make atomic switch
            currentAssetBundle = pendingAssetBundle
            self.pendingAssetBundle = nil
            switchedToNewVersion = true

            // Set new server base path
            setServerBasePath(bundleServingDirectory)

            // Reload the WebView
            reloadWebView()

            // Start startup timer to track successful loading
            startStartupTimer()

            completion(nil)

        } catch {
            completion(error)
        }
    }

    private func reloadWebView() {
        guard let bridge = capacitorBridge,
              let webView = bridge.webView else {
            NSLog("Could not get WebView for reload")
            return
        }

        DispatchQueue.main.async {
            webView.reload()
        }
    }

    // MARK: - Recovery and Error Handling

    private func revertToLastKnownGoodVersion() {
        bundleSwitchSemaphore.wait()
        defer { bundleSwitchSemaphore.signal() }

        // Blacklist the current version, so we don't update to it again right away
        configuration.addBlacklistedVersion(currentAssetBundle.version)

        // If there is a last known good version and we can load the bundle, revert to it
        if let lastKnownGoodVersion = configuration.lastKnownGoodVersion,
           let lastKnownGoodAssetBundle = assetBundleManager.downloadedAssetBundleWithVersion(lastKnownGoodVersion) {
            pendingAssetBundle = lastKnownGoodAssetBundle
            // Else, revert to the initial asset bundle, unless that is what we are currently serving
        } else if currentAssetBundle.version != assetBundleManager.initialAssetBundle.version {
            pendingAssetBundle = assetBundleManager.initialAssetBundle
        }

        // Only reload if we have a pending asset bundle to reload
        if pendingAssetBundle != nil {
            forceReload()
        } else {
            NSLog("There is no last good version we can revert to")
        }
    }

    private func forceReload() {
        guard let bridge = capacitorBridge,
              let webView = bridge.webView else {
            NSLog("Could not get WebView for force reload")
            return
        }

        DispatchQueue.main.async {
            webView.reloadFromOrigin()
        }
    }

    // MARK: - Lifecycle Handling

    public func onPageReload() {
        // If there is a pending asset bundle, we make it the current
        if let pendingAssetBundle = pendingAssetBundle {
            currentAssetBundle = pendingAssetBundle
            self.pendingAssetBundle = nil
        }

        if switchedToNewVersion {
            switchedToNewVersion = false
            startStartupTimer()
        }
    }

    public func onApplicationDidEnterBackground() {
        // Stop startup timer when going into the background, to avoid
        // blacklisting a version just because the web view has been suspended
        startupTimer?.stop()
    }

    // MARK: - AssetBundleManagerDelegate

    func assetBundleManager(_ assetBundleManager: AssetBundleManager, shouldDownloadBundleForManifest manifest: AssetManifest) -> Bool {
        // No need to redownload the current or the pending version
        if currentAssetBundle.version == manifest.version || pendingAssetBundle?.version == manifest.version {
            return false
        }

        // Don't download blacklisted versions
        if configuration.blacklistedVersions.contains(manifest.version) {
            NSLog("Skipping blacklisted version: \(manifest.version)")
            return false
        }

        // Don't download versions potentially incompatible with the bundled native code
        if manifest.cordovaCompatibilityVersion != configuration.cordovaCompatibilityVersion {
            NSLog("Skipping incompatible version: \(manifest.version)")
            return false
        }

        return true
    }

    func assetBundleManager(_ assetBundleManager: AssetBundleManager, didFinishDownloadingBundle assetBundle: AssetBundle) {
        NSLog("Finished downloading new asset bundle version: \(assetBundle.version)")

        configuration.lastDownloadedVersion = assetBundle.version
        pendingAssetBundle = assetBundle

        // Notify any listeners that a new version is ready
        notifyUpdateAvailable(version: assetBundle.version)
    }

    func assetBundleManager(_ assetBundleManager: AssetBundleManager, didFailDownloadingBundleWithError error: Error) {
        NSLog("Download failure: \(error)")
        notifyUpdateFailed(error: error)
    }

    // MARK: - Event Notifications

    private func notifyUpdateAvailable(version: String) {
        // Can be overridden by subclasses or used by plugin bridge
    }

    private func notifyUpdateFailed(error: Error) {
        // Can be overridden by subclasses or used by plugin bridge
    }
}
